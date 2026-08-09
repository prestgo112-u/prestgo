// Séquence de déconnexion (T073, FR-011, scénario 1.9).
//
// L'ordre est imposé, et chaque étape a une raison d'être à sa place :
//
//   1. **désenregistrer l'appareil** — tant que la session vit encore, sans quoi le
//      service refuserait l'appel ; sinon l'appareil continuerait de recevoir les
//      notifications du compte quitté ;
//   2. **fermer la session** — avec le jeton de renouvellement, pour révoquer
//      précisément celle-ci et non une autre ;
//   3. **purger** — stockage sécurisé, base locale, puis recréation du conteneur
//      d'état (SC-012) ;
//   4. **revenir à la connexion**.
//
// Les deux premières étapes sont **au mieux** : hors ligne, jeton déjà expiré, service
// indisponible — leur échec ne doit pas retenir l'utilisateur sur un compte qu'il
// veut quitter. La purge, elle, a toujours lieu. C'est exactement l'inverse d'une
// séquence transactionnelle, et c'est voulu : ce qui compte est qu'aucune donnée du
// compte précédent ne reste sur l'appareil.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/app/push_driver.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';

class LogoutController {
  const LogoutController({
    required AuthRepository repository,
    required SecureTokenStore tokenStore,
    required Future<void> Function() onUnregisterDevice,
    required Future<void> Function() onPurge,
  }) : _repository = repository,
       _tokenStore = tokenStore,
       _onUnregisterDevice = onUnregisterDevice,
       _onPurge = onPurge;

  final AuthRepository _repository;
  final SecureTokenStore _tokenStore;
  final Future<void> Function() _onUnregisterDevice;
  final Future<void> Function() _onPurge;

  /// Déroule la séquence. N'échoue jamais.
  Future<void> signOut() async {
    final AuthTokens? tokens = await _tokenStore.read();

    // Étape 1 — au mieux, mais IMPÉRATIVEMENT avant la fermeture de session :
    // la route de désenregistrement exige un jeton valide (scénario 7.5).
    await _onUnregisterDevice();

    // Étape 2 — au mieux.
    try {
      await _repository.signOut(refreshToken: tokens?.refreshToken);
    } on ApiException {
      // Session déjà close, réseau absent : rien à corriger, on continue.
    }

    // Étapes 3 et 4 — inconditionnelles.
    await _onPurge();
  }
}

final Provider<LogoutController> logoutControllerProvider =
    Provider<LogoutController>(
      (Ref ref) => LogoutController(
        repository: ref.watch(authRepositoryProvider),
        tokenStore: ref.watch(secureTokenStoreProvider),
        // `PushService.unregisterBeforeLogout` n'échoue jamais : l'appel réseau
        // est au mieux, la purge du jeton local a toujours lieu.
        onUnregisterDevice: () =>
            ref.read(pushServiceProvider).unregisterBeforeLogout(),
        onPurge: () => ref.read(sessionControllerProvider.notifier).signOut(),
      ),
    );
