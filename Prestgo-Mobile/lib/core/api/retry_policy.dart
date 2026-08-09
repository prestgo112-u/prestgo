// Politique de rejeu par type de requête (porte G4).
//
// Voir contracts/retry-and-idempotency.md §1. La règle est une **fonction pure** de
// (méthode, chemin, échec, tentative) : elle se teste sans réseau, et l'intercepteur
// qui l'applique n'a aucune décision à prendre.

import 'package:dio/dio.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';

/// Clé d'extra comptant les tentatives déjà consommées par une requête.
const String kRetryAttemptExtra = 'prestgo.retryAttempt';

/// Clé d'extra permettant à un appelant d'exclure explicitement une requête du
/// rejeu automatique (envoi de fichier, cf. R7).
const String kNoRetryExtra = 'prestgo.noRetry';

/// Familles de requêtes, chacune avec sa propre tolérance au rejeu.
enum RequestKind {
  /// Lecture sans effet de bord.
  read,

  /// `POST /missions` — protégé par `Idempotency-Key`.
  booking,

  /// Écriture idempotente par construction : le résultat ne dépend pas du nombre
  /// d'appels.
  idempotentWrite,

  /// Transition de mission : un rejeu après succès non reçu renvoie « Action
  /// impossible depuis le statut … », incompréhensible pour l'utilisateur.
  missionTransition,

  /// Dépôt d'avis : un rejeu renvoie 409 « avis déjà déposé », traité comme un
  /// succès par l'écran — mais jamais rejoué automatiquement.
  review,

  /// Envoi de message : aucune clé d'idempotence, un rejeu créerait un doublon.
  message,

  /// Envoi de fichier : corps multipart à usage unique.
  fileUpload,

  /// Routes d'authentification : débits serrés, un rejeu déclencherait un 429.
  auth,

  /// Toute autre écriture.
  unsafeWrite,
}

/// Décision de rejeu.
class RetryPolicy {
  const RetryPolicy();

  /// Attentes des lectures : 500 ms puis 1,5 s.
  static const List<Duration> readBackoff = <Duration>[
    Duration(milliseconds: 500),
    Duration(milliseconds: 1500),
  ];

  /// Attentes de `POST /missions` : 1 s puis 3 s (§3 du contrat).
  static const List<Duration> bookingBackoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 3),
  ];

  /// Attente unique des écritures idempotentes.
  static const List<Duration> idempotentWriteBackoff = <Duration>[
    Duration(milliseconds: 500),
  ];

  /// Attente avant de réessayer un 409 « déjà en cours de traitement ».
  static const Duration bookingInFlightBackoff = Duration(seconds: 2);

  /// Nombre de reprises admises sur un 409 « déjà en cours de traitement ».
  static const int bookingInFlightMaxAttempts = 2;

  /// Classe une requête d'après sa méthode et son chemin.
  ///
  /// [path] est le chemin **relatif à la base d'API** : il ne contient donc pas
  /// `/api/v1`.
  static RequestKind classify({required String method, required String path}) {
    final String verb = method.toUpperCase();
    final String route = _normalisePath(path);

    if (route.startsWith('/auth/')) {
      return RequestKind.auth;
    }
    if (verb == 'GET' || verb == 'HEAD') {
      return RequestKind.read;
    }
    if (verb == 'POST' && route == '/files/upload') {
      return RequestKind.fileUpload;
    }
    if (verb == 'POST' && route == '/missions') {
      return RequestKind.booking;
    }
    if (verb == 'POST' && _missionTransition.hasMatch(route)) {
      return RequestKind.missionTransition;
    }
    if (verb == 'POST' && _missionReview.hasMatch(route)) {
      return RequestKind.review;
    }
    if (verb == 'POST' && _threadMessage.hasMatch(route)) {
      return RequestKind.message;
    }
    if (_isIdempotentWrite(verb, route)) {
      return RequestKind.idempotentWrite;
    }
    return RequestKind.unsafeWrite;
  }

  /// Attente avant la prochaine tentative, ou `null` si la requête ne doit pas être
  /// rejouée.
  ///
  /// [attempt] est le nombre de tentatives **déjà** effectuées (0 pour le premier
  /// échec).
  Duration? delayFor({
    required RequestKind kind,
    required ApiException error,
    required int attempt,
  }) {
    // Un débit dépassé ne se rejoue jamais : l'écran affiche un message d'attente
    // et désactive l'action.
    if (error.isRateLimited || error.isCancelled) {
      return null;
    }

    switch (kind) {
      case RequestKind.read:
        return _at(readBackoff, attempt, allowed: error.isTransient);
      case RequestKind.booking:
        return _at(bookingBackoff, attempt, allowed: error.isTransient);
      case RequestKind.idempotentWrite:
        return _at(idempotentWriteBackoff, attempt, allowed: error.isTransient);
      case RequestKind.missionTransition:
      case RequestKind.review:
      case RequestKind.message:
      case RequestKind.fileUpload:
      case RequestKind.auth:
      case RequestKind.unsafeWrite:
        return null;
    }
  }

  static Duration? _at(
    List<Duration> backoff,
    int attempt, {
    required bool allowed,
  }) {
    if (!allowed || attempt < 0 || attempt >= backoff.length) {
      return null;
    }
    return backoff[attempt];
  }

  static bool _isIdempotentWrite(String verb, String route) {
    if (verb == 'PUT' &&
        (route == '/providers/me/zones' ||
            route == '/providers/me/availabilities')) {
      return true;
    }
    if ((verb == 'POST' || verb == 'DELETE') && _favorite.hasMatch(route)) {
      return true;
    }
    if (verb == 'PATCH' && _notificationRead.hasMatch(route)) {
      return true;
    }
    if (verb == 'POST' && route == '/me/devices') {
      return true;
    }
    return false;
  }

  /// Retire la chaîne de requête et le `/` final.
  static String _normalisePath(String path) {
    String route = path;
    final int query = route.indexOf('?');
    if (query != -1) {
      route = route.substring(0, query);
    }
    if (route.length > 1 && route.endsWith('/')) {
      route = route.substring(0, route.length - 1);
    }
    return route.startsWith('/') ? route : '/$route';
  }

  static final RegExp _missionTransition = RegExp(
    r'^/missions/[^/]+/(accept|refuse|start|complete|cancel)$',
  );
  static final RegExp _missionReview = RegExp(r'^/missions/[^/]+/review$');
  static final RegExp _threadMessage = RegExp(
    r'^/messages/threads/[^/]+/messages$',
  );
  static final RegExp _favorite = RegExp(r'^/me/favorites/[^/]+$');
  static final RegExp _notificationRead = RegExp(
    r'^/me/notifications/[^/]+/read$',
  );
}

/// Applique [RetryPolicy] aux échecs remontés par `dio`.
///
/// Placé **après** `EnvelopeInterceptor` dans la chaîne : il raisonne sur des
/// `ApiException`, jamais sur des codes HTTP.
class RetryInterceptor extends Interceptor {
  RetryInterceptor({
    required Dio dio,
    RetryPolicy policy = const RetryPolicy(),
    Future<void> Function(Duration) wait = Future<void>.delayed,
  }) : _dio = dio,
       _policy = policy,
       _wait = wait;

  final Dio _dio;
  final RetryPolicy _policy;
  final Future<void> Function(Duration) _wait;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final RequestOptions options = err.requestOptions;
    final Object? error = err.error;

    if (error is! ApiException || options.extra[kNoRetryExtra] == true) {
      handler.next(err);
      return;
    }

    final int attempt = (options.extra[kRetryAttemptExtra] as int?) ?? 0;
    final RequestKind kind = RetryPolicy.classify(
      method: options.method,
      path: options.path,
    );
    final Duration? delay = _policy.delayFor(
      kind: kind,
      error: error,
      attempt: attempt,
    );

    if (delay == null) {
      handler.next(err);
      return;
    }

    await _wait(delay);

    options.extra[kRetryAttemptExtra] = attempt + 1;
    try {
      final Response<Object?> response = await _dio.fetch<Object?>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }
}
