// Renouvellement de session sérialisé et rejeu unique (R8, contrat §4).
//
// Quatre invariants, chacun correspondant à un piège recensé au §6 de quickstart.md :
//
//   1. **un seul renouvellement en vol** — dix requêtes parallèles qui en
//      déclencheraient dix atteindraient le plafond de 30 appels/minute ; les
//      concurrentes attendent le même `Future` ;
//   2. **rotation enregistrée** — le nouveau jeton de renouvellement remplace
//      l'ancien, sinon la session tombe au renouvellement suivant ;
//   3. **rejeu unique** — une requête n'est rejouée qu'une fois ; un second 401 met
//      fin à la session ;
//   4. **instance HTTP séparée** pour l'appel de renouvellement — sinon son propre
//      401 relancerait un renouvellement, en récursion infinie.
//
// Les routes d'authentification sont exclues du renouvellement et du rejeu.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/request_markers.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';

export 'package:prestgo_mobile/core/api/request_markers.dart';

/// Chemin de renouvellement — jamais intercepté par cet intercepteur.
const String kRefreshPath = '/auth/refresh';

/// ⚠️ Volontairement un `Interceptor` et **non** un `QueuedInterceptor`.
///
/// La file de `QueuedInterceptor` sérialise les rappels : rejouer la requête
/// d'origine depuis `onError` passe par la même instance `dio`, dont le rappel
/// d'erreur attend une file que l'appel extérieur détient toujours — interblocage
/// dès que le rejeu échoue à son tour.
///
/// La mise en file exigée par R8 est assurée autrement, et plus précisément : le
/// `Future` de renouvellement partagé (invariant 1) fait attendre toutes les
/// requêtes concurrentes sur **le même** appel, et la comparaison du jeton employé
/// couvre celles qui arrivent après coup.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required SecureTokenStore tokenStore,
    required Dio refreshDio,
    required Dio Function() client,
    required Future<void> Function() onSessionExpired,
  }) : _tokenStore = tokenStore,
       _refreshDio = refreshDio,
       _client = client,
       _onSessionExpired = onSessionExpired;

  final SecureTokenStore _tokenStore;

  /// Instance **sans** `AuthInterceptor` (invariant 4).
  final Dio _refreshDio;

  /// Instance complète, utilisée pour rejouer la requête d'origine.
  ///
  /// Fournie par une fonction pour rompre le cycle de construction entre le client
  /// et ses intercepteurs.
  final Dio Function() _client;

  final Future<void> Function() _onSessionExpired;

  /// Renouvellement actuellement en vol (invariant 1).
  Future<AuthTokens?>? _refreshInFlight;

  /// Vrai tant qu'un renouvellement est en cours — exposé pour les tests.
  bool get isRefreshing => _refreshInFlight != null;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (_skipHeader(options) || options.headers.containsKey('Authorization')) {
      handler.next(options);
      return;
    }

    final AuthTokens? tokens = await _tokenStore.read();
    if (tokens != null) {
      options
        ..headers['Authorization'] = 'Bearer ${tokens.accessToken}'
        // Mémorise le jeton effectivement employé : sur 401, il permet de
        // distinguer « mon jeton est périmé » de « quelqu'un a déjà renouvelé
        // pendant que j'attendais » (cf. onError).
        ..extra[kAccessTokenUsedExtra] = tokens.accessToken;
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions options = err.requestOptions;
    final Object? error = err.error;
    final bool isAuthFailure = error is ApiException
        ? error.isAuth
        : err.response?.statusCode == 401;

    if (!isAuthFailure || _isExcludedFromRefresh(options)) {
      handler.next(err);
      return;
    }

    // Invariant 3 : une seule reprise par requête. Un second 401 signifie que le
    // jeton fraîchement obtenu est déjà refusé — la session est bel et bien close.
    if (options.extra[kAuthRetriedExtra] == true) {
      await _endSession();
      handler.next(err);
      return;
    }

    // `QueuedInterceptor` sérialise les rappels : quand N requêtes partent
    // ensemble avec le même jeton périmé, elles arrivent ici l'une après l'autre.
    // Sans ce test, la deuxième déclencherait un second renouvellement — le
    // premier étant déjà terminé, `_refreshInFlight` est retombé à `null`. On
    // compare donc le jeton *employé par la requête* au jeton *actuellement
    // stocké* : s'il a changé, quelqu'un a renouvelé pendant l'attente et il n'y a
    // qu'à rejouer (invariant 1).
    final AuthTokens? stored = await _tokenStore.read();
    final Object? used = options.extra[kAccessTokenUsedExtra];
    final bool alreadyRenewed =
        stored != null && used is String && stored.accessToken != used;

    final AuthTokens? tokens = alreadyRenewed ? stored : await _refreshOnce();
    if (tokens == null) {
      handler.next(err);
      return;
    }

    options
      ..extra[kAuthRetriedExtra] = true
      ..extra[kAccessTokenUsedExtra] = tokens.accessToken
      ..headers['Authorization'] = 'Bearer ${tokens.accessToken}';

    try {
      final Response<Object?> response = await _client().fetch<Object?>(
        options,
      );
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  /// Renouvelle la session, en partageant l'appel entre tous les demandeurs.
  ///
  /// Les requêtes concurrentes attendent **le même** `Future` : c'est l'invariant 1.
  Future<AuthTokens?> _refreshOnce() {
    final Future<AuthTokens?>? inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final Future<AuthTokens?> started = _performRefresh();
    _refreshInFlight = started;
    return started.whenComplete(() => _refreshInFlight = null);
  }

  Future<AuthTokens?> _performRefresh() async {
    final AuthTokens? current = await _tokenStore.read();
    if (current == null) {
      await _endSession();
      return null;
    }

    try {
      final Response<Object?> response = await _refreshDio.post<Object?>(
        kRefreshPath,
        data: <String, Object?>{'refreshToken': current.refreshToken},
      );

      final AuthTokens? renewed = _readTokens(response.data);
      if (renewed == null) {
        await _endSession();
        return null;
      }

      // Invariant 2 : la rotation est enregistrée en une écriture atomique.
      await _tokenStore.write(renewed);
      return renewed;
    } on DioException {
      // Compte suspendu entre-temps, jeton révoqué, service indisponible : dans
      // tous les cas l'application purge et revient à la connexion plutôt que de
      // boucler.
      await _endSession();
      return null;
    }
  }

  Future<void> _endSession() async {
    await _tokenStore.clearAll();
    await _onSessionExpired();
  }

  static AuthTokens? _readTokens(Object? body) {
    if (body is! Map<Object?, Object?>) {
      return null;
    }
    final JsonMap json = body.cast<String, Object?>();
    final Object? data = json['data'];
    if (data is! Map<Object?, Object?>) {
      return null;
    }
    final AuthTokens tokens = AuthTokens.fromJson(data.cast<String, Object?>());
    return tokens.isComplete ? tokens : null;
  }

  /// Requêtes qui ne reçoivent pas l'en-tête d'autorisation.
  ///
  /// Seul le renouvellement en est privé : il porte son jeton dans le corps. En
  /// particulier `POST /auth/logout` **reçoit** l'en-tête, sans quoi le service ne
  /// saurait pas quelle session fermer.
  static bool _skipHeader(RequestOptions options) =>
      options.extra[kSkipAuthExtra] == true || _route(options) == kRefreshPath;

  /// Routes exclues du renouvellement et du rejeu : toutes les routes
  /// d'authentification, dont les débits sont serrés, et celles qui vérifient un
  /// mot de passe saisi — leur 401 ne parle pas de la session (`kSkipRefreshExtra`).
  static bool _isExcludedFromRefresh(RequestOptions options) =>
      options.extra[kSkipAuthExtra] == true ||
      options.extra[kSkipRefreshExtra] == true ||
      _route(options).startsWith('/auth/');

  static String _route(RequestOptions options) {
    final String path = options.path;
    return path.startsWith('/') ? path : '/$path';
  }
}
