// État de session et purge globale (R14, SC-012).
//
// À la déconnexion comme à la désactivation, trois choses se produisent, dans cet
// ordre : le stockage sécurisé est vidé, la base locale est vidée, puis le
// conteneur d'état est **recréé**.
//
// Recréer le conteneur plutôt qu'invalider les providers un par un est délibéré :
// une invalidation ciblée laisse toujours passer un cache oublié, et l'exigence est
// qu'aucune donnée du compte précédent ne reste affichable après un changement de
// compte sur le même appareil.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';

/// Signal de recréation du conteneur d'état.
///
/// Il vit **hors** du conteneur Riverpod — sans quoi il disparaîtrait avec lui au
/// moment précis où il doit déclencher la reconstruction. `PrestgoApp` l'écoute et
/// remonte un `ProviderScope` neuf à chaque incrément.
class SessionResetSignal extends ValueNotifier<int> {
  SessionResetSignal() : super(0);

  /// Demande la recréation du conteneur.
  void bump() => value = value + 1;
}

/// Instance unique, partagée par l'amorçage et le contrôleur de session.
final SessionResetSignal sessionResetSignal = SessionResetSignal();

/// Où en est la session au démarrage et après chaque transition.
enum SessionStatus {
  /// Jetons pas encore lus : l'application affiche son écran de démarrage.
  unknown,

  /// Jetons présents — le profil reste à charger pour décider de l'atterrissage.
  authenticated,

  /// Aucune session ouverte.
  unauthenticated,
}

class SessionState {
  const SessionState({required this.status, this.tokens});

  const SessionState.unknown() : status = SessionStatus.unknown, tokens = null;

  const SessionState.signedOut()
    : status = SessionStatus.unauthenticated,
      tokens = null;

  final SessionStatus status;

  /// Jetons courants ; jamais journalisés ni remontés dans un incident.
  final AuthTokens? tokens;

  bool get isAuthenticated => status == SessionStatus.authenticated;
  bool get isResolved => status != SessionStatus.unknown;

  @override
  bool operator ==(Object other) =>
      other is SessionState && other.status == status && other.tokens == tokens;

  @override
  int get hashCode => Object.hash(status, tokens);

  @override
  String toString() => 'SessionState(${status.name})';
}

class SessionController extends Notifier<SessionState> {
  late final SecureTokenStore _tokenStore = ref.read(secureTokenStoreProvider);
  late final CacheDao _cache = ref.read(cacheDaoProvider);

  @override
  SessionState build() => const SessionState.unknown();

  /// Lit les jetons au démarrage et publie l'état correspondant.
  ///
  /// Ne joint pas le réseau : l'aiguillage se fait ensuite sur le profil servi par
  /// le cache, ce qui permet de router au démarrage même hors ligne.
  Future<SessionState> restore() async {
    final AuthTokens? tokens = await _tokenStore.read();
    final SessionState restored = tokens == null
        ? const SessionState.signedOut()
        : SessionState(status: SessionStatus.authenticated, tokens: tokens);
    state = restored;
    return restored;
  }

  /// Ouvre une session après une authentification réussie.
  ///
  /// La base locale est purgée **avant** d'écrire les jetons : un compte peut
  /// succéder à un autre sur le même appareil, et rien de ce que le compte
  /// précédent a mis en cache ne doit rester lisible (SC-012). Dans les parcours
  /// normaux la purge de déconnexion est déjà passée et l'opération est à vide —
  /// c'est une ceinture, pas le mécanisme principal. Le conteneur, lui, n'est
  /// **pas** recréé ici : le gardien est en train de lire `?from=` pour ramener
  /// l'utilisateur sur sa route d'origine, et la recréation l'emporterait.
  Future<void> signIn(AuthTokens tokens) async {
    await _cache.purgeAll();
    await _tokenStore.write(tokens);
    state = SessionState(status: SessionStatus.authenticated, tokens: tokens);
  }

  /// Ferme la session et purge tout.
  ///
  /// Les étapes réseau (désenregistrement de l'appareil, `POST /auth/logout`) sont
  /// menées **avant** par la séquence de déconnexion (T073) et sont « au mieux » :
  /// leur échec ne doit pas empêcher la purge locale (scénario 1.9).
  Future<void> signOut() => _purge();

  /// Renouvellement impossible : le service a clos la session de son côté.
  ///
  /// Appelé par `AuthInterceptor`. Purge et retour à la connexion, jamais de
  /// boucle de renouvellement.
  Future<void> onSessionExpired() => _purge();

  Future<void> _purge() async {
    await _tokenStore.clearAll();
    await _cache.purgeAll();
    state = const SessionState.signedOut();
    // Recrée le conteneur : tout provider encore vivant est abandonné avec lui.
    sessionResetSignal.bump();
  }
}

final Provider<SecureTokenStore> secureTokenStoreProvider =
    Provider<SecureTokenStore>((Ref ref) => SecureTokenStore());

final NotifierProvider<SessionController, SessionState>
sessionControllerProvider = NotifierProvider<SessionController, SessionState>(
  SessionController.new,
);
