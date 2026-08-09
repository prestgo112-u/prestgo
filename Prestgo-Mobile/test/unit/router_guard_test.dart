// Gardien unique du routeur (T039) — contracts/navigation-routes.md §2.
//
// Ce test couvre l'authentification et la mémorisation de la route d'origine. Les
// sept branches de `providerValidationStatus` sont vérifiées avec la table
// d'aiguillage par rôle, au moment d'US1 (T065).

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/app/router_guard.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/session/routing_profile.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';

const RoutingProfile client = RoutingProfile(
  userStatus: UserStatus.active,
  hasProviderProfile: false,
);

String? redirect(
  String location, {
  SessionStatus status = SessionStatus.authenticated,
  RoutingProfile? profile = client,
  String? fullLocation,
}) => resolveRedirect(
  location: location,
  status: status,
  profile: profile,
  fullLocation: fullLocation,
);

void main() {
  group('Session non résolue', () {
    test('tout mène à l’écran de démarrage', () {
      expect(
        redirect(Routes.home, status: SessionStatus.unknown, profile: null),
        Routes.splash,
      );
      expect(
        redirect(Routes.splash, status: SessionStatus.unknown, profile: null),
        isNull,
      );
    });

    test('une session ouverte au profil non chargé attend aussi', () {
      expect(redirect(Routes.clientHome, profile: null), Routes.splash);
    });

    test('sauf sur un écran d’authentification, qui pilote le chargement', () {
      // Le détourner le démonterait au milieu de sa séquence, et la route
      // mémorisée par `?from=` serait perdue (FR-028, scénario 2.4).
      for (final String location in authOnlyRoutes) {
        expect(redirect(location, profile: null), isNull, reason: location);
      }
    });
  });

  group('Sans session', () {
    test('les routes publiques passent', () {
      for (final String location in <String>[
        Routes.home,
        Routes.search,
        '/providers/p-1',
        '/providers/p-1/reviews',
        Routes.login,
        Routes.register,
        Routes.verify,
        Routes.forgotPassword,
        Routes.resetPassword,
      ]) {
        expect(
          redirect(
            location,
            status: SessionStatus.unauthenticated,
            profile: null,
          ),
          isNull,
          reason: location,
        );
      }
    });

    test('une route protégée renvoie à la connexion', () {
      expect(
        redirect(
          Routes.missions,
          status: SessionStatus.unauthenticated,
          profile: null,
        ),
        startsWith(Routes.login),
      );
    });

    test(
      'la route d’origine est mémorisée avec ses paramètres (scénario 2.4)',
      () {
        const String origin = '/booking/new?providerId=p-1&packId=k-2';

        final String? target = redirect(
          '/booking/new',
          status: SessionStatus.unauthenticated,
          profile: null,
          fullLocation: origin,
        );

        expect(target, isNotNull);
        final Uri uri = Uri.parse(target!);
        expect(uri.path, Routes.login);
        expect(uri.queryParameters[Routes.redirectQueryParameter], origin);
      },
    );

    test('l’écran de démarrage bascule sur la connexion', () {
      // L'application s'ouvre sur la connexion, et non plus sur l'accueil public.
      // La consultation sans compte reste entière — l'assertion suivante le
      // vérifie — mais elle se rejoint depuis cet écran, plus l'inverse.
      expect(
        redirect(
          Routes.splash,
          status: SessionStatus.unauthenticated,
          profile: null,
        ),
        Routes.login,
      );
    });

    test('l’accueil public reste atteignable sans compte', () {
      expect(
        redirect(
          Routes.home,
          status: SessionStatus.unauthenticated,
          profile: null,
        ),
        isNull,
      );
    });
  });

  group('Avec session', () {
    test('un écran d’authentification renvoie à l’atterrissage', () {
      for (final String location in authOnlyRoutes) {
        expect(redirect(location), Routes.clientHome, reason: location);
      }
    });

    test('la route mémorisée l’emporte sur l’atterrissage (scénario 2.4)', () {
      const String origin = '/providers/p-1';

      expect(
        redirect(Routes.login, fullLocation: Routes.loginWithRedirect(origin)),
        origin,
      );
    });

    test('la route mémorisée garde ses paramètres', () {
      const String origin = '/booking/new?providerId=p-1';

      expect(
        redirect(Routes.login, fullLocation: Routes.loginWithRedirect(origin)),
        origin,
      );
    });

    test('une route mémorisée qui boucle est ignorée', () {
      // Un `from` fabriqué à la main pointant vers la connexion elle-même
      // produirait une redirection infinie.
      expect(
        redirect(
          Routes.login,
          fullLocation: Routes.loginWithRedirect(Routes.login),
        ),
        Routes.clientHome,
      );
      expect(
        redirect(
          Routes.login,
          fullLocation: Routes.loginWithRedirect(Routes.splash),
        ),
        Routes.clientHome,
      );
    });

    test('un compte non actif retourne à la connexion', () {
      const RoutingProfile suspended = RoutingProfile(
        userStatus: UserStatus.suspended,
        hasProviderProfile: false,
      );
      expect(redirect(Routes.clientHome, profile: suspended), Routes.login);
      expect(redirect(Routes.login, profile: suspended), isNull);
    });

    test('l’espace client est ouvert sur le seul `status`, jamais sur '
        '`hasClientProfile`', () {
      // Des comptes historiques ont `hasClientProfile` à `false` tout en étant
      // clients : le modèle de routage ne porte volontairement pas ce champ.
      for (final String location in <String>[
        Routes.clientHome,
        Routes.missions,
        Routes.favorites,
        Routes.threads,
        Routes.profile,
        Routes.notifications,
      ]) {
        expect(redirect(location), isNull, reason: location);
      }
    });

    test('un client est refoulé de l’espace prestataire', () {
      expect(redirect(Routes.providerDashboard), Routes.clientHome);
      expect(redirect(Routes.providerMissions), Routes.clientHome);
    });

    test('un client peut entrer dans le parcours « devenir prestataire »', () {
      expect(redirect(Routes.providerOnboarding), isNull);
      expect(redirect(Routes.providerOnboardingProfile), isNull);
    });

    test(
      'un prestataire approuvé garde l’accès aux routes client — bascule sans '
      'reconnexion',
      () {
        const RoutingProfile approved = RoutingProfile(
          userStatus: UserStatus.active,
          hasProviderProfile: true,
          providerValidationStatus: ProviderValidationStatus.approved,
        );

        expect(redirect(Routes.providerDashboard, profile: approved), isNull);
        expect(redirect(Routes.clientHome, profile: approved), isNull);
        expect(redirect(Routes.missions, profile: approved), isNull);
        // Plus d'onboarding à dérouler une fois le dossier approuvé.
        expect(
          redirect(Routes.providerChecklist, profile: approved),
          Routes.providerDashboard,
        );
      },
    );

    test('un dossier en vérification est renvoyé au suivi, mais garde l’espace '
        'client', () {
      const RoutingProfile pending = RoutingProfile(
        userStatus: UserStatus.active,
        hasProviderProfile: true,
        providerValidationStatus: ProviderValidationStatus.pendingReview,
      );

      expect(
        redirect(Routes.providerDashboard, profile: pending),
        Routes.providerStatus,
      );
      expect(redirect(Routes.clientHome, profile: pending), isNull);
      expect(redirect(Routes.missions, profile: pending), isNull);
    });
  });

  group('Classement des routes', () {
    test('l’onboarding n’est pas l’espace prestataire', () {
      expect(Routes.isProviderSpace(Routes.providerChecklist), isFalse);
      expect(Routes.isProviderOnboarding(Routes.providerChecklist), isTrue);
      expect(Routes.isProviderSpace(Routes.providerDashboard), isTrue);
      expect(Routes.isProviderOnboarding(Routes.providerDashboard), isFalse);
    });

    test('la racine et la recherche sont publiques', () {
      expect(Routes.isPublic(Routes.home), isTrue);
      expect(Routes.isPublic('/search'), isTrue);
      expect(Routes.isPublic('/providers/p-1'), isTrue);
      expect(Routes.isPublic(Routes.missions), isFalse);
      expect(Routes.isPublic(Routes.clientHome), isFalse);
    });

    test('⚠️ « /providers » n’est PAS « /provider »', () {
      // La comparaison se fait sur les segments : une comparaison de chaînes
      // brutes classerait la fiche publique dans l'espace prestataire, et tout
      // client connecté qui l'ouvrirait serait renvoyé à son accueil.
      expect(Routes.isProviderSpace('/providers/p-1'), isFalse);
      expect(Routes.isProviderSpace('/providers/p-1/reviews'), isFalse);
      expect(Routes.isProviderSpace(Routes.providerDashboard), isTrue);
      expect(Routes.isProviderSpace(Routes.providerMissions), isTrue);
      expect(Routes.isProviderOnboarding('/providers/p-1'), isFalse);
    });

    test(
      'un client connecté consulte une fiche publique sans être refoulé',
      () {
        expect(redirect('/providers/p-1'), isNull);
        expect(redirect('/providers/p-1/reviews'), isNull);
      },
    );

    test('un préfixe ne déborde pas sur une route voisine', () {
      expect(Routes.isPublic('/searching'), isFalse);
      expect(Routes.isPublic('/logintruc'), isFalse);
      expect(Routes.isPublic('/search'), isTrue);
      expect(Routes.isPublic('/search/results'), isTrue);
    });
  });
}
