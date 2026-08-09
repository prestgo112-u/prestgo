// Table des routes et **gardien unique**.
//
// Un seul `redirect` porte l'authentification et l'aiguillage par rôle : aucun écran
// ne réimplémente de contrôle d'accès (contracts/navigation-routes.md).
//
// Les deux seules entrées du gardien sont l'état de session et le profil ; ce sont
// donc les deux seuls déclencheurs de réévaluation. Le profil vient du contrôleur de
// la fonctionnalité `profile` : il n'existe pas de second état « de routage » qui
// pourrait en diverger.
//
// Les destinations non encore écrites restent des emplacements portant le numéro de
// la tâche qui les remplacera.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/placeholder_screen.dart';
import 'package:prestgo_mobile/app/router_guard.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/app/splash_screen.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/auth/data/dto/otp_dto.dart';
import 'package:prestgo_mobile/features/auth/presentation/login/login_screen.dart';
import 'package:prestgo_mobile/features/auth/presentation/login/phone_login_screen.dart';
import 'package:prestgo_mobile/features/auth/presentation/logout_action.dart';
import 'package:prestgo_mobile/features/auth/presentation/password/forgot_password_screen.dart';
import 'package:prestgo_mobile/features/auth/presentation/password/reset_password_screen.dart';
import 'package:prestgo_mobile/features/auth/presentation/register/register_screen.dart';
import 'package:prestgo_mobile/features/auth/presentation/verify/auto_login_screen.dart';
import 'package:prestgo_mobile/features/auth/presentation/verify/verify_screen.dart';
import 'package:prestgo_mobile/features/booking/presentation/booking_summary_screen.dart';
import 'package:prestgo_mobile/features/booking/presentation/pack_selection_screen.dart';
import 'package:prestgo_mobile/features/booking/presentation/schedule_picker_screen.dart';
import 'package:prestgo_mobile/features/disputes/presentation/dispute_screen.dart';
import 'package:prestgo_mobile/features/messaging/presentation/conversation_screen.dart';
import 'package:prestgo_mobile/features/messaging/presentation/threads_screen.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_detail_screen.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_history_view.dart';
import 'package:prestgo_mobile/features/missions/presentation/my_missions_screen.dart';
import 'package:prestgo_mobile/features/notifications/presentation/devices_screen.dart';
import 'package:prestgo_mobile/features/notifications/presentation/notifications_screen.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';
import 'package:prestgo_mobile/features/profile/presentation/address_form_screen.dart';
import 'package:prestgo_mobile/features/profile/presentation/addresses_controller.dart';
import 'package:prestgo_mobile/features/profile/presentation/addresses_screen.dart';
import 'package:prestgo_mobile/features/profile/presentation/change_password_screen.dart';
import 'package:prestgo_mobile/features/profile/presentation/deactivate_account_screen.dart';
import 'package:prestgo_mobile/features/profile/presentation/favorites_screen.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';
import 'package:prestgo_mobile/features/profile/presentation/profile_edit_screen.dart';
import 'package:prestgo_mobile/features/profile/presentation/profile_screen.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/checklist_screen.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/onboarding_intro_screen.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_profile_form_screen.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/status_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/availabilities_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/dashboard_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/documents_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/portfolio_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/provider_missions_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/provider_profile_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/services_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/unavailabilities_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/zones_screen.dart';
import 'package:prestgo_mobile/features/reviews/presentation/my_reviews_screen.dart';
import 'package:prestgo_mobile/features/search/presentation/provider_profile_screen.dart';
import 'package:prestgo_mobile/features/search/presentation/provider_reviews_screen.dart';
import 'package:prestgo_mobile/features/search/presentation/search_screen.dart';

final Provider<GoRouter> goRouterProvider = Provider<GoRouter>((Ref ref) {
  // `go_router` réévalue sa redirection sur notification : session et profil sont
  // les deux seules entrées du gardien, donc les deux seuls déclencheurs.
  final ValueNotifier<int> refresh = ValueNotifier<int>(0);
  ref
    ..listen<SessionState>(
      sessionControllerProvider,
      (SessionState? previous, SessionState next) => refresh.value++,
    )
    ..listen<RoutingProfile?>(
      routingProfileProvider,
      (RoutingProfile? previous, RoutingProfile? next) => refresh.value++,
    )
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) => resolveRedirect(
      location: state.uri.path,
      fullLocation: state.uri.toString(),
      status: ref.read(sessionControllerProvider).status,
      profile: ref.read(routingProfileProvider),
    ),
    routes: _routes,
  );
});

GoRoute _placeholder(
  String path,
  String title,
  String task, {
  List<Widget> actions = const <Widget>[],
}) => GoRoute(
  path: path,
  builder: (BuildContext context, GoRouterState state) =>
      PlaceholderScreen(title: title, task: task, actions: actions),
);

/// Route mémorisée à restaurer après authentification (`?from=…`).
String? _redirectTarget(GoRouterState state) =>
    state.uri.queryParameters[Routes.redirectQueryParameter];

final List<RouteBase> _routes = <RouteBase>[
  GoRoute(
    path: Routes.splash,
    builder: (BuildContext context, GoRouterState state) =>
        const SplashScreen(),
  ),

  // --- Publiques ----------------------------------------------------------------
  //
  // Recherche et fiches sont consultables **sans compte** (FR-022) : aucune de ces
  // routes n'exige de session, et le gardien les laisse passer.
  GoRoute(
    path: Routes.home,
    builder: (BuildContext context, GoRouterState state) =>
        const SearchScreen(),
  ),
  GoRoute(
    path: Routes.search,
    builder: (BuildContext context, GoRouterState state) =>
        const SearchScreen(),
  ),
  GoRoute(
    path: Routes.providerProfile,
    builder: (BuildContext context, GoRouterState state) =>
        ProviderProfileScreen(providerId: state.pathParameters['id'] ?? ''),
    routes: <RouteBase>[
      GoRoute(
        path: 'reviews',
        builder: (BuildContext context, GoRouterState state) =>
            ProviderReviewsScreen(providerId: state.pathParameters['id'] ?? ''),
      ),
    ],
  ),

  GoRoute(
    path: Routes.login,
    builder: (BuildContext context, GoRouterState state) =>
        LoginScreen(redirectTo: _redirectTarget(state)),
  ),
  GoRoute(
    path: Routes.phoneLogin,
    builder: (BuildContext context, GoRouterState state) =>
        PhoneLoginScreen(redirectTo: _redirectTarget(state)),
  ),
  GoRoute(
    path: Routes.register,
    builder: (BuildContext context, GoRouterState state) =>
        const RegisterScreen(),
  ),
  // Déclarée **avant** `/verify` n'est pas nécessaire — les deux chemins sont
  // distincts — mais leur voisinage rend la parenté visible.
  GoRoute(
    path: Routes.autoLogin,
    builder: (BuildContext context, GoRouterState state) =>
        const AutoLoginScreen(),
  ),
  GoRoute(
    path: Routes.verify,
    builder: (BuildContext context, GoRouterState state) {
      final Map<String, String> query = state.uri.queryParameters;
      return VerifyScreen(
        target: query[Routes.targetQueryParameter] ?? '',
        purpose: switch (query[Routes.purposeQueryParameter]) {
          'email_verification' => OtpPurpose.emailVerification,
          _ => OtpPurpose.phoneVerification,
        },
        origin: VerificationOrigin.parse(query[Routes.originQueryParameter]),
      );
    },
  ),
  GoRoute(
    path: Routes.forgotPassword,
    builder: (BuildContext context, GoRouterState state) =>
        const ForgotPasswordScreen(),
  ),
  GoRoute(
    path: Routes.resetPassword,
    builder: (BuildContext context, GoRouterState state) => ResetPasswordScreen(
      token: state.uri.queryParameters[Routes.tokenQueryParameter],
    ),
  ),

  // --- Espace client ------------------------------------------------------------
  // Atterrissage du client. L'écran reste à construire, mais il porte dès
  // maintenant la déconnexion : sans elle, un client connecté ne peut plus quitter
  // sa session — aucun lien ne part d'ici, et la session est restaurée au démarrage.
  _placeholder(
    Routes.clientHome,
    'Accueil',
    'T098',
    actions: const <Widget>[LogoutAction()],
  ),

  // Parcours de réservation : trois routes, un seul brouillon. Le prestataire est
  // porté par la première ; les deux suivantes lisent l'état.
  GoRoute(
    path: Routes.bookingNew,
    builder: (BuildContext context, GoRouterState state) => PackSelectionScreen(
      providerId:
          state.uri.queryParameters[Routes.providerQueryParameter] ?? '',
    ),
  ),
  GoRoute(
    path: Routes.bookingSchedule,
    builder: (BuildContext context, GoRouterState state) =>
        const SchedulePickerScreen(),
  ),
  GoRoute(
    path: Routes.bookingSummary,
    builder: (BuildContext context, GoRouterState state) =>
        const BookingSummaryScreen(),
  ),

  GoRoute(
    path: Routes.missions,
    builder: (BuildContext context, GoRouterState state) =>
        const MyMissionsScreen(),
  ),
  GoRoute(
    path: Routes.missionDetail,
    builder: (BuildContext context, GoRouterState state) =>
        MissionDetailScreen(missionId: state.pathParameters['id'] ?? ''),
    routes: <RouteBase>[
      GoRoute(
        path: 'history',
        builder: (BuildContext context, GoRouterState state) =>
            MissionHistoryScreen(missionId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: 'dispute',
        builder: (BuildContext context, GoRouterState state) =>
            DisputeScreen(missionId: state.pathParameters['id'] ?? ''),
      ),
    ],
  ),

  GoRoute(
    path: Routes.favorites,
    builder: (BuildContext context, GoRouterState state) =>
        const FavoritesScreen(),
  ),
  GoRoute(
    path: Routes.reviews,
    builder: (BuildContext context, GoRouterState state) =>
        const MyReviewsScreen(),
  ),

  // --- Commun aux deux rôles ----------------------------------------------------
  GoRoute(
    path: Routes.threads,
    builder: (BuildContext context, GoRouterState state) =>
        const ThreadsScreen(),
  ),
  GoRoute(
    path: Routes.conversation,
    builder: (BuildContext context, GoRouterState state) => ConversationScreen(
      threadId: state.pathParameters['id'] ?? '',
      missionId: state.uri.queryParameters[Routes.missionQueryParameter],
    ),
  ),
  GoRoute(
    path: Routes.notifications,
    builder: (BuildContext context, GoRouterState state) =>
        const NotificationsScreen(),
  ),

  GoRoute(
    path: Routes.profile,
    builder: (BuildContext context, GoRouterState state) =>
        const ProfileScreen(),
  ),
  GoRoute(
    path: Routes.profileEdit,
    builder: (BuildContext context, GoRouterState state) =>
        const _ProfileEditRoute(),
  ),
  GoRoute(
    path: Routes.profilePassword,
    builder: (BuildContext context, GoRouterState state) =>
        const ChangePasswordScreen(),
  ),
  GoRoute(
    path: Routes.deactivateAccount,
    builder: (BuildContext context, GoRouterState state) =>
        const DeactivateAccountScreen(),
  ),

  GoRoute(
    path: Routes.addresses,
    builder: (BuildContext context, GoRouterState state) =>
        const AddressesScreen(),
  ),
  // Déclarée avant `/profile/addresses/:id`, sans quoi « new » serait pris pour un
  // identifiant d'adresse.
  GoRoute(
    path: Routes.addressNew,
    builder: (BuildContext context, GoRouterState state) =>
        const AddressFormScreen(),
  ),
  GoRoute(
    path: Routes.addressDetail,
    builder: (BuildContext context, GoRouterState state) =>
        _AddressEditRoute(addressId: state.pathParameters['id'] ?? ''),
  ),
  GoRoute(
    path: Routes.devices,
    builder: (BuildContext context, GoRouterState state) =>
        const DevicesScreen(),
  ),

  // --- Onboarding prestataire ---------------------------------------------------
  GoRoute(
    path: Routes.providerOnboarding,
    builder: (BuildContext context, GoRouterState state) =>
        const OnboardingIntroScreen(),
  ),
  GoRoute(
    path: Routes.providerOnboardingProfile,
    builder: (BuildContext context, GoRouterState state) =>
        const ProviderProfileFormScreen(),
  ),
  GoRoute(
    path: Routes.providerChecklist,
    builder: (BuildContext context, GoRouterState state) =>
        const ChecklistScreen(),
  ),
  GoRoute(
    path: Routes.providerStatus,
    builder: (BuildContext context, GoRouterState state) =>
        const ProviderStatusScreen(),
  ),

  // --- Espace prestataire -------------------------------------------------------
  GoRoute(
    path: Routes.providerDashboard,
    builder: (BuildContext context, GoRouterState state) =>
        const ProviderDashboardScreen(),
  ),
  GoRoute(
    path: Routes.providerMissions,
    builder: (BuildContext context, GoRouterState state) =>
        const ProviderMissionsScreen(),
  ),
  GoRoute(
    path: Routes.providerProfileSpace,
    builder: (BuildContext context, GoRouterState state) =>
        const ProviderSpaceProfileScreen(),
  ),
  GoRoute(
    path: Routes.providerServices,
    builder: (BuildContext context, GoRouterState state) =>
        const ProviderServicesScreen(),
  ),
  GoRoute(
    path: Routes.providerZones,
    builder: (BuildContext context, GoRouterState state) =>
        const ProviderZonesScreen(),
  ),
  GoRoute(
    path: Routes.providerAvailabilities,
    builder: (BuildContext context, GoRouterState state) =>
        const ProviderAvailabilitiesScreen(),
  ),
  GoRoute(
    path: Routes.providerUnavailabilities,
    builder: (BuildContext context, GoRouterState state) =>
        const ProviderUnavailabilitiesScreen(),
  ),
  GoRoute(
    path: Routes.providerDocuments,
    builder: (BuildContext context, GoRouterState state) =>
        const ProviderDocumentsScreen(),
  ),
  GoRoute(
    path: Routes.providerPortfolio,
    builder: (BuildContext context, GoRouterState state) =>
        const ProviderPortfolioScreen(),
  ),
];

/// L'édition du profil part des valeurs actuelles : elle attend donc que le profil
/// soit chargé, plutôt que d'ouvrir un formulaire vide qui écraserait l'identité.
class _ProfileEditRoute extends ConsumerWidget {
  const _ProfileEditRoute();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Me? me = ref.watch(meControllerProvider).value;
    return me == null
        ? const LoadingView(label: 'Chargement du profil…')
        : ProfileEditScreen(me: me);
  }
}

/// Même principe pour une adresse : le formulaire part de ses valeurs actuelles.
///
/// Une adresse introuvable dans le carnet ouvre une **création** plutôt qu'un écran
/// d'erreur : c'est le cas d'un lien profond vers une adresse supprimée entre-temps.
class _AddressEditRoute extends ConsumerWidget {
  const _AddressEditRoute({required this.addressId});

  final String addressId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Address>> addresses = ref.watch(addressesProvider);
    if (addresses.isLoading) {
      return const LoadingView(label: 'Chargement de l’adresse…');
    }
    final Address? address = addresses.value
        ?.where((Address a) => a.id == addressId)
        .firstOrNull;
    return AddressFormScreen(address: address);
  }
}
