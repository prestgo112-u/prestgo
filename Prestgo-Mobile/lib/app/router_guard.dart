// Gardien **unique** — fonction pure (contracts/navigation-routes.md §2).
//
// Concentrer la décision ici, plutôt que dans chaque écran, est ce qui garantit
// qu'aucune branche n'est oubliée : dossier suspendu, refusé avec re-soumission
// bloquée, profil incomplet. C'est aussi ce qui la rend testable sans widget.

import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/session/routing_profile.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';

/// Écran d'atterrissage d'un compte donné — la table du §1.4 de data-model.md,
/// une ligne par branche.
String landingFor(RoutingProfile profile) {
  if (!profile.hasProviderProfile) {
    return Routes.clientHome;
  }
  return switch (profile.providerValidationStatus) {
    ProviderValidationStatus.approved => Routes.providerDashboard,
    ProviderValidationStatus.profileIncomplete => Routes.providerChecklist,
    ProviderValidationStatus.pendingReview ||
    ProviderValidationStatus.changesRequested ||
    ProviderValidationStatus.rejected ||
    ProviderValidationStatus.suspended => Routes.providerStatus,
    // Dossier tout juste créé, sans statut : la checklist est la reprise naturelle.
    null => Routes.providerChecklist,
  };
}

/// Routes d'authentification dont un compte connecté doit être détourné.
///
/// `autoLogin` (C5) en fait partie : cet écran vient précisément d'ouvrir la session,
/// et n'a plus rien à afficher une fois le profil chargé. Sans cette ligne, il
/// resterait sur son indicateur d'attente indéfiniment.
///
/// `verify` n'y est **pas** : un compte connecté qui vérifie un contact modifié doit
/// pouvoir y rester (FR-017).
const Set<String> authOnlyRoutes = <String>{
  Routes.login,
  Routes.phoneLogin,
  Routes.register,
  Routes.forgotPassword,
  Routes.resetPassword,
  Routes.autoLogin,
};

/// Route mémorisée dans `?from=`, ou `null`.
///
/// Écarte une cible qui serait elle-même un écran d'authentification : la
/// redirection tournerait en boucle. Un `from` fabriqué à la main est donc sans
/// danger — il ne peut que ramener vers une route ordinaire.
String? memorisedRoute(String? fullLocation) {
  if (fullLocation == null) {
    return null;
  }
  final String? target = Uri.tryParse(
    fullLocation,
  )?.queryParameters[Routes.redirectQueryParameter];
  if (target == null || target.isEmpty) {
    return null;
  }
  final String path = Uri.tryParse(target)?.path ?? target;
  if (authOnlyRoutes.contains(path) || path == Routes.splash) {
    return null;
  }
  return target;
}

/// Renvoie la route de destination, ou `null` pour laisser passer.
///
/// [profile] vaut `null` tant que le profil n'a pas été chargé. Le cache le sert
/// immédiatement au démarrage, y compris hors ligne, ce qui rend ce cas bref.
/// [location] est le **chemin** demandé, sans chaîne de requête ;
/// [fullLocation] le porte avec ses paramètres, pour être restauré à l'identique
/// après authentification (scénario 2.4 : « Réserver » sans compte revient sur la
/// même fiche).
String? resolveRedirect({
  required String location,
  required SessionStatus status,
  required RoutingProfile? profile,
  String? fullLocation,
}) {
  // 3. Jetons pas encore lus → écran de démarrage, puis réévaluation.
  if (status == SessionStatus.unknown) {
    return location == Routes.splash ? null : Routes.splash;
  }

  if (status == SessionStatus.unauthenticated) {
    // L'application s'ouvre sur la **connexion**, et non sur l'accueil public.
    //
    // La consultation sans compte reste entière — `/`, la recherche et les fiches
    // demeurent publiques (spec.md §89-90) — mais elle se rejoint depuis l'écran de
    // connexion, par « Découvrir sans compte ». Seul le point d'entrée change.
    if (location == Routes.splash) {
      return Routes.login;
    }
    // 1. Route publique → laisser passer. 2. Route protégée → connexion, en
    // mémorisant la route demandée pour y revenir après authentification (FR-028).
    return Routes.isPublic(location)
        ? null
        : Routes.loginWithRedirect(fullLocation ?? location);
  }

  // Session présente, profil pas encore chargé.
  if (profile == null) {
    // ⚠️ Les écrans d'authentification font exception, et c'est indispensable :
    // ils **pilotent** la séquence « jetons → profil → destination ». Les détourner
    // vers l'écran de démarrage les démonterait au milieu de cette séquence — leur
    // `context` cesse d'être monté, la navigation finale n'a jamais lieu, et la
    // route mémorisée par `?from=` est perdue. L'utilisateur atterrit sur l'accueil
    // au lieu de revenir là où il était (FR-028, scénario 2.4).
    if (authOnlyRoutes.contains(location)) {
      return null;
    }
    return location == Routes.splash ? null : Routes.splash;
  }

  // 5. Compte non actif → connexion, avec purge déclenchée par l'appelant.
  if (!profile.isActive) {
    return location == Routes.login ? null : Routes.login;
  }

  final String landing = landingFor(profile);

  // Un compte connecté n'a rien à faire sur un écran d'authentification.
  //
  // C'est ici, et non dans l'écran de connexion, qu'est honorée la route mémorisée
  // par `?from=` (FR-028, scénario 2.4). L'écran ne peut pas s'en charger : au
  // moment où le profil arrive, le gardien l'a déjà remplacé — son `context` n'est
  // plus monté et sa navigation finale n'a jamais lieu. Le gardien, lui, voit
  // toujours l'adresse complète.
  if (authOnlyRoutes.contains(location)) {
    return memorisedRoute(fullLocation) ?? landing;
  }
  if (location == Routes.splash) {
    return landing;
  }

  // 4. Aiguillage par rôle.
  if (Routes.isProviderSpace(location)) {
    if (!profile.hasProviderProfile) {
      return Routes.clientHome;
    }
    final ProviderValidationStatus? validation =
        profile.providerValidationStatus;
    if (validation == null || !validation.opensProviderSpace) {
      // `pending_review` renvoie vers le suivi du dossier — mais l'espace client
      // reste, lui, parfaitement accessible.
      return landing;
    }
    return null;
  }

  if (Routes.isProviderOnboarding(location)) {
    // Un dossier approuvé n'a plus d'onboarding à dérouler.
    if (profile.providerValidationStatus?.opensProviderSpace ?? false) {
      return Routes.providerDashboard;
    }
    return null;
  }

  // Toutes les routes client et communes restent ouvertes, y compris à un
  // prestataire : un compte à double casquette bascule sans se reconnecter.
  return null;
}
