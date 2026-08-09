// Profil du compte connecté — source **unique** pour l'affichage et pour
// l'aiguillage (T064, FR-013).
//
// L'ordre de chargement est celui du contrat : cache d'abord, service ensuite. C'est
// ce qui permet à l'application ouverte sans réseau d'atteindre le bon espace au lieu
// de rester sur l'écran de démarrage — et c'est aussi ce qui rend le premier écran
// instantané quand le réseau est là.
//
// Un seul état, et non deux : le routeur lit ce même contrôleur (`lib/app/router.dart`).
// Recopier le profil dans un second état « de routage » l'exposerait à diverger de
// celui qu'affiche l'écran de profil.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/features/profile/data/me_repository.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';

class MeController extends AsyncNotifier<Me?> {
  /// Charge le profil dès qu'une session existe, et le libère quand elle tombe.
  ///
  /// Dépend de `sessionControllerProvider` : une connexion ou une déconnexion
  /// relance donc ce chargement sans que personne ait à y penser.
  @override
  Future<Me?> build() async {
    final SessionState session = ref.watch(sessionControllerProvider);
    if (!session.isAuthenticated) {
      return null;
    }

    final MeRepository repository = ref.read(meRepositoryProvider);
    final Me? cached = await repository.cached();

    try {
      return await repository.fetch();
    } on ApiException catch (error) {
      // Hors ligne avec un profil connu : on route dessus. Le compte a pu changer
      // de statut entre-temps — le service tranchera au prochain appel, et toute
      // action d'écriture est de toute façon refusée sans réseau (porte G1).
      if (cached != null && error.isNetwork) {
        return cached;
      }
      // Session close côté service : `AuthInterceptor` a déjà purgé et remis
      // `SessionStatus.unauthenticated`, ce qui reconstruira ce contrôleur.
      rethrow;
    }
  }

  /// Relit `GET /me`.
  ///
  /// Employé après une action susceptible d'avoir changé l'aiguillage : création
  /// d'un profil prestataire, dossier approuvé, vérification d'un contact.
  Future<void> reload() async {
    state = const AsyncValue<Me?>.loading();
    state = await AsyncValue.guard<Me?>(
      () => ref.read(meRepositoryProvider).fetch(),
    );
  }

  /// Adopte un profil déjà obtenu — la réponse de `PATCH /me`, par exemple.
  ///
  /// Évite un `GET /me` immédiatement après une écriture qui vient précisément de
  /// renvoyer le profil à jour.
  void adopt(Me me) => state = AsyncValue<Me?>.data(me);
}

final AsyncNotifierProvider<MeController, Me?> meControllerProvider =
    AsyncNotifierProvider<MeController, Me?>(MeController.new);

/// Profil retenu par le gardien du routeur, ou `null` tant qu'il est inconnu.
///
/// `null` couvre trois situations que le gardien traite de la même façon (attendre
/// sur l'écran de démarrage) : chargement en cours, absence de session, échec sans
/// cache.
final Provider<RoutingProfile?> routingProfileProvider =
    Provider<RoutingProfile?>(
      (Ref ref) => ref.watch(meControllerProvider).value?.routing,
    );
