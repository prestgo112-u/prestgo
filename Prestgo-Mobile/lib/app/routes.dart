// Constantes de chemins — voir contracts/navigation-routes.md §1.
//
// Aucun chemin n'est écrit en dur dans un écran : c'est ce qui rend le gardien
// unique vérifiable et la table des routes relisible d'un coup d'œil.

abstract final class Routes {
  // --- Publiques (accessibles sans session) -------------------------------------

  static const String home = '/';
  static const String search = '/search';
  static const String providerProfile = '/providers/:id';
  static const String providerReviews = '/providers/:id/reviews';
  static const String login = '/login';
  static const String phoneLogin = '/login/phone';
  static const String register = '/register';
  static const String verify = '/verify';

  /// Écran de transition C5 : le compte vient d'être activé, la connexion se fait
  /// toute seule. Sous `/verify` pour rester dans le périmètre public.
  static const String autoLogin = '/verify/welcome';
  static const String forgotPassword = '/forgot-password';
  static const String resetPassword = '/reset-password';

  // --- Espace client (session requise) ------------------------------------------

  static const String clientHome = '/home';
  static const String bookingNew = '/booking/new';
  static const String bookingSchedule = '/booking/schedule';
  static const String bookingSummary = '/booking/summary';
  static const String missions = '/missions';
  static const String missionDetail = '/missions/:id';
  static const String missionHistory = '/missions/:id/history';
  static const String missionDispute = '/missions/:id/dispute';
  static const String favorites = '/favorites';
  static const String reviews = '/reviews';

  // --- Commun aux deux rôles (session requise) ----------------------------------

  static const String threads = '/threads';
  static const String conversation = '/threads/:id';
  static const String notifications = '/notifications';
  static const String profile = '/profile';
  static const String profileEdit = '/profile/edit';
  static const String profilePassword = '/profile/password';
  static const String addresses = '/profile/addresses';
  static const String addressNew = '/profile/addresses/new';
  static const String addressDetail = '/profile/addresses/:id';
  static const String devices = '/profile/devices';
  static const String deactivateAccount = '/profile/deactivate';

  // --- Onboarding prestataire (session requise) ---------------------------------

  static const String providerOnboarding = '/provider/onboarding';
  static const String providerOnboardingProfile =
      '/provider/onboarding/profile';
  static const String providerChecklist = '/provider/onboarding/checklist';
  static const String providerStatus = '/provider/onboarding/status';

  // --- Espace prestataire (dossier approuvé) ------------------------------------

  static const String providerDashboard = '/provider';
  static const String providerMissions = '/provider/missions';
  static const String providerProfileSpace = '/provider/profile';
  static const String providerServices = '/provider/services';
  static const String providerZones = '/provider/zones';
  static const String providerAvailabilities = '/provider/availabilities';
  static const String providerUnavailabilities = '/provider/unavailabilities';
  static const String providerDocuments = '/provider/documents';
  static const String providerPortfolio = '/provider/portfolio';

  /// Écran de démarrage, le temps de restaurer la session et de lire le profil.
  static const String splash = '/splash';

  // --- Classification employée par le gardien -----------------------------------

  /// Routes accessibles sans session, quelles qu'en soient les circonstances.
  static const Set<String> publicPrefixes = <String>{
    search,
    '/providers',
    login,
    register,
    verify,
    forgotPassword,
    resetPassword,
    splash,
  };

  /// Préfixe des routes de l'onboarding prestataire.
  static const String providerOnboardingPrefix = '/provider/onboarding';

  /// Préfixe de l'espace prestataire approuvé.
  static const String providerPrefix = '/provider';

  /// Vrai si [location] est sous [prefix], au sens des **segments** de chemin.
  ///
  /// ⚠️ La comparaison de chaînes brutes ne convient pas ici, et l'erreur est
  /// coûteuse : `'/providers/p-1'.startsWith('/provider')` vaut `true`. La fiche
  /// publique d'un prestataire serait alors classée dans l'espace prestataire, et
  /// tout client connecté qui l'ouvrirait serait renvoyé à son accueil. Deux routes
  /// que rien ne distingue à la lecture — un « s » — n'ont pourtant rien à voir.
  static bool _isUnder(String location, String prefix) =>
      location == prefix || location.startsWith('$prefix/');

  /// Vrai si [location] est accessible sans session.
  ///
  /// La racine est publique — l'accueil et la recherche sont consultables sans
  /// compte (scénario 2.1 de quickstart.md).
  static bool isPublic(String location) {
    if (location == home) {
      return true;
    }
    return publicPrefixes.any((String prefix) => _isUnder(location, prefix));
  }

  /// Vrai si [location] appartient à l'espace prestataire approuvé.
  ///
  /// L'onboarding en est exclu : il reste accessible à un dossier non approuvé.
  static bool isProviderSpace(String location) =>
      _isUnder(location, providerPrefix) &&
      !_isUnder(location, providerOnboardingPrefix);

  /// Vrai si [location] appartient à l'onboarding prestataire.
  static bool isProviderOnboarding(String location) =>
      _isUnder(location, providerOnboardingPrefix);

  /// Paramètre de requête portant la route à restaurer après authentification.
  static const String redirectQueryParameter = 'from';

  /// `/login?from=<route mémorisée>` — le retour restaure la route **et** ses
  /// paramètres (FR-028, scénario 2.4).
  static String loginWithRedirect(String location) =>
      '$login?$redirectQueryParameter=${Uri.encodeComponent(location)}';

  // --- Paramètres des écrans du parcours de compte ------------------------------
  //
  // Portés par la chaîne de requête et non par un objet `extra` : c'est ce qui rend
  // l'écran de vérification atteignable après un redémarrage, et testable sans
  // reconstituer un état de navigation.

  /// Destinataire du code — numéro de téléphone ou adresse email.
  static const String targetQueryParameter = 'target';

  /// Motif OTP, dans la forme attendue par le service (`phone_verification`…).
  static const String purposeQueryParameter = 'purpose';

  /// Ce qui a conduit à l'écran de vérification : activation d'un compte neuf,
  /// vérification d'un contact modifié, ou connexion par code.
  static const String originQueryParameter = 'origin';

  /// Jeton de réinitialisation, quand il est déjà connu.
  static const String tokenQueryParameter = 'token';

  /// `/verify?target=…&purpose=…&origin=…`.
  static String verifyFor({
    required String target,
    required String purpose,
    required String origin,
  }) =>
      '$verify'
      '?$targetQueryParameter=${Uri.encodeComponent(target)}'
      '&$purposeQueryParameter=$purpose'
      '&$originQueryParameter=$origin';

  /// `/reset-password?token=…` — pré-remplit le champ après un lien reçu.
  static String resetPasswordWithToken(String token) =>
      '$resetPassword?$tokenQueryParameter=${Uri.encodeComponent(token)}';

  // --- Chemins portant un identifiant -------------------------------------------
  //
  // Construits ici plutôt qu'interpolés dans les écrans : c'est ce qui garantit
  // qu'un changement de table de routes se voit à la compilation.

  static String providerProfileFor(String providerId) =>
      '/providers/${Uri.encodeComponent(providerId)}';

  static String providerReviewsFor(String providerId) =>
      '${providerProfileFor(providerId)}/reviews';

  static String addressDetailFor(String addressId) =>
      '/profile/addresses/${Uri.encodeComponent(addressId)}';

  static String missionDetailFor(String missionId) =>
      '/missions/${Uri.encodeComponent(missionId)}';

  static String missionHistoryFor(String missionId) =>
      '${missionDetailFor(missionId)}/history';

  static String missionDisputeFor(String missionId) =>
      '${missionDetailFor(missionId)}/dispute';

  /// [missionId] est la mission porteuse du fil, quand l'appelant la connaît —
  /// détail de mission, notification `chat`. Elle permet à la conversation de
  /// lire le statut du fil (`GET /missions/{id}/thread`, opération 50) sans
  /// dépendre du chargement de `/me/threads`.
  static String conversationFor(String threadId, {String? missionId}) {
    final String base = '/threads/${Uri.encodeComponent(threadId)}';
    if (missionId == null || missionId.isEmpty) {
      return base;
    }
    return '$base?$missionQueryParameter=${Uri.encodeComponent(missionId)}';
  }

  /// Mission porteuse d'une conversation, dans la chaîne de requête.
  static const String missionQueryParameter = 'mission';

  /// Section du détail de mission visée par une notification (`?tab=reschedule`,
  /// `?tab=review`) — contracts/push-payloads.md §1.
  static const String missionTabQueryParameter = 'tab';

  /// Point d'entrée du parcours de réservation d'un prestataire donné.
  static String bookingFor(String providerId) =>
      '$bookingNew?$providerQueryParameter=${Uri.encodeComponent(providerId)}';

  /// Prestataire visé par un parcours de réservation.
  static const String providerQueryParameter = 'providerId';
}
