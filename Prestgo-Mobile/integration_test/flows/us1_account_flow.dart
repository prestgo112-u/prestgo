// T082 — Parcours US1 de bout en bout : scénarios 1.1 à 1.10 de quickstart.md.
//
// Ce test monte l'application **entière** — routeur, gardien unique, chaîne
// d'intercepteurs, dépôts, écrans — et ne remplace que trois choses : le transport
// HTTP, la base locale et le stockage sécurisé. Tout le reste est le code livré.
//
// C'est ce qui le distingue des tests de contrat et des tests d'écran : ici, ce sont
// les **enchaînements** qui sont vérifiés. Un écran peut être juste et le parcours
// cassé — un code envoyé deux fois, une session ouverte sans profil, un
// renouvellement déclenché en double.
//
// Le service simulé porte un état : un compte y naît `pending`, s'active à la
// vérification, et refuse la connexion tant qu'il ne l'est pas. Sans cet état, les
// scénarios 1.3 et 1.4 ne prouveraient rien.
//
// ⚠️ Ce fichier ne contient **pas** de `main` : les scénarios sont exposés par
// [runUs1Scenarios] et déroulés par deux points d'entrée.
//   • `integration_test/flows/us1_account_flow_test.dart` — sur appareil ou
//     émulateur, avec la liaison d'intégration ;
//   • `test/flows/us1_account_flow_test.dart` — sans appareil, donc dans
//     l'intégration continue, qui n'exécute que `flutter test`.
// Sans ce second point d'entrée, le parcours ne serait vérifié nulle part
// automatiquement : c'est précisément le test qui a le plus de valeur.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/app/router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/config/app_environment.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/features/auth/presentation/logout_controller.dart';
import 'package:prestgo_mobile/features/auth/presentation/register/registration_draft.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';

import '../../test/support/fixtures.dart';
import '../../test/support/recording_adapter.dart';
import '../../test/support/screen_harness.dart';

const String kBaseUrl = 'http://localhost:3000/api/v1';
const String kGoodCode = '418902';
const String kEmail = 'nouveau.client@prestgo.test';
const String kPassword = 'prestgo123!';

/// Service simulé, avec l'état minimal qu'exigent les scénarios.
class FakeBackend {
  bool accountActivated = false;
  int otpAttempts = 0;

  /// Coupure réseau simulée sur toutes les routes.
  bool offline = false;

  /// Le jeton d'accès courant est refusé une fois par route protégée.
  bool accessTokenExpired = false;

  /// Réponse à servir sur `GET /me`.
  String meCase = 'client';

  /// Réponse à servir sur `DELETE /me`.
  String deleteCase = 'deactivated';

  final List<String> journal = <String>[];

  int callsTo(String path) => journal.where((String p) => p == path).length;

  AdapterResponse handle(RequestOptions options, int index) {
    final String path = options.path;
    journal.add(path);

    if (offline) {
      // Une exception traverse `dio` et se présente comme un échec réseau.
      throw const SocketExceptionStub();
    }

    switch (path) {
      case '/auth/register':
        return fixture('auth/register', 'created');

      case '/auth/otp/send':
        otpAttempts = 0;
        return fixture('auth/otp_send', 'sentWithDevCode');

      case '/auth/otp/verify':
        final Map<String, Object?> body = options.data! as Map<String, Object?>;
        if (body['purpose'] == 'login') {
          return fixture('auth/otp_verify', 'loginTokens');
        }
        if (body['code'] == kGoodCode) {
          accountActivated = true;
          return fixture('auth/otp_verify', 'activated');
        }
        otpAttempts++;
        return otpAttempts >= 5
            ? fixture('auth/otp_verify', 'tooManyAttempts')
            : fixture('auth/otp_verify', 'invalidCode');

      case '/auth/login':
        return accountActivated
            ? fixture('auth/login', 'authenticated')
            : fixture('auth/login', 'accountNotActive');

      case '/auth/refresh':
        accessTokenExpired = false;
        return fixture('auth/refresh', 'rotated');

      case '/auth/logout':
        return fixture('auth/logout', 'loggedOut');

      case '/auth/forgot-password':
        return fixture('auth/password_reset', 'forgotAcceptedWithDevToken');

      case '/auth/reset-password':
        return fixture('auth/password_reset', 'resetDone');

      case '/me':
        if (options.method == 'DELETE') {
          return fixture('auth/me_password_and_delete', deleteCase);
        }
        if (accessTokenExpired) {
          return fixture('auth/me', 'unauthenticated');
        }
        return fixture('auth/me', meCase);

      default:
        return (
          404,
          <String, Object?>{
            'success': false,
            'message': 'Route non simulée : $path',
          },
        );
    }
  }
}

/// Marque une coupure réseau : `dio` la présente comme un échec sans réponse.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'Réseau coupé (simulation)';
}

/// Conteneur monté sur le service simulé, avec la vraie chaîne d'intercepteurs.
///
/// `apiDioProvider` et `refreshDioProvider` sont reconstruits par les fonctions de
/// production ; seul l'adaptateur de transport change. C'est indispensable au
/// scénario 1.6, qui porte précisément sur le comportement de `AuthInterceptor`.
ProviderContainer buildContainer(
  FakeBackend backend,
  LocalDatabase database,
  InMemoryTokenStore tokenStore,
) {
  final RecordingAdapter adapter = RecordingAdapter(backend.handle);
  final AppEnvironment environment = AppEnvironment.fromDefines(
    apiBaseUrl: kBaseUrl,
    networkLogsEnabled: false,
  );

  return ProviderContainer(
    overrides: <Override>[
      appEnvironmentProvider.overrideWithValue(environment),
      localDatabaseProvider.overrideWithValue(database),
      secureTokenStoreProvider.overrideWithValue(tokenStore),
      refreshDioProvider.overrideWith((Ref ref) {
        final Dio dio = buildRefreshDio(environment)
          ..httpClientAdapter = adapter;
        return dio;
      }),
      apiDioProvider.overrideWith((Ref ref) {
        final Dio dio = buildAuthenticatedDio(
          environment: environment,
          tokenStore: tokenStore,
          refreshDio: ref.watch(refreshDioProvider),
          onSessionExpired: () =>
              ref.read(sessionControllerProvider.notifier).onSessionExpired(),
        )..httpClientAdapter = adapter;
        return dio;
      }),
    ],
  );
}

/// Application réelle, montée sur un conteneur fourni par le test.
class TestApp extends StatelessWidget {
  const TestApp({required this.container, super.key});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: container,
    child: const _RouterHost(),
  );
}

class _RouterHost extends ConsumerWidget {
  const _RouterHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MaterialApp.router(routerConfig: ref.watch(goRouterProvider));
}

/// Déroule les scénarios 1.1 à 1.10.
void runUs1Scenarios() {
  late FakeBackend backend;
  late LocalDatabase database;
  late InMemoryTokenStore tokenStore;
  late ProviderContainer container;

  setUp(() {
    backend = FakeBackend();
    database = LocalDatabase.memory();
    tokenStore = InMemoryTokenStore();
    container = buildContainer(backend, database, tokenStore);
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> start(WidgetTester tester, {String? at}) async {
    await tester.pumpWidget(TestApp(container: container));
    await tester.pumpAndSettle();
    if (at != null) {
      container.read(goRouterProvider).go(at);
      await tester.pumpAndSettle();
    }
  }

  String currentLocation() => container
      .read(goRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .toString();

  // --- Inscription et activation --------------------------------------------

  testWidgets('1.1 — l’inscription ouvre l’écran de code, qui part tout seul', (
    WidgetTester tester,
  ) async {
    await start(tester, at: Routes.register);

    await tester.tap(find.text('Par email'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Adresse email'),
      kEmail,
    );
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mot de passe'),
      kPassword,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmez le mot de passe'),
      kPassword,
    );
    await tester.tap(find.text('Créer mon compte'));
    await tester.pumpAndSettle();

    expect(backend.callsTo('/auth/register'), 1);
    expect(currentLocation(), startsWith(Routes.verify));
    expect(
      backend.callsTo('/auth/otp/send'),
      1,
      reason: 'aucune action supplémentaire n’est demandée (FR-002)',
    );
    expect(find.textContaining('Valable encore'), findsOneWidget);
  });

  testWidgets(
    '1.2 — cinq codes erronés ferment la saisie, avec un seul message',
    (WidgetTester tester) async {
      await start(
        tester,
        at: Routes.verifyFor(
          target: kEmail,
          purpose: 'email_verification',
          origin: 'activation',
        ),
      );

      for (int attempt = 1; attempt <= 5; attempt++) {
        await tester.enterText(find.byType(TextField), '00000$attempt');
        await tester.pumpAndSettle();
      }

      expect(
        find.text('Trop de tentatives sur ce code. Demandez-en un nouveau.'),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(
        find.text('Code invalide ou expiré'),
        findsNothing,
        reason: 'un seul message est affiché à la fois',
      );
    },
  );

  testWidgets(
    '1.3 — le bon code active le compte et connecte automatiquement',
    (WidgetTester tester) async {
      await start(
        tester,
        at: Routes.verifyFor(
          target: kEmail,
          purpose: 'email_verification',
          origin: 'activation',
        ),
      );

      // Le brouillon d'inscription porte le couple qui servira à la connexion
      // automatique ; il n'a jamais transité par une route ni par le disque.
      container.read(registrationDraftProvider.notifier)
        ..start(RegistrationChannel.email)
        ..update(contact: kEmail, password: kPassword);

      await tester.enterText(find.byType(TextField), kGoodCode);
      await tester.pumpAndSettle();

      expect(backend.accountActivated, isTrue);
      expect(backend.callsTo('/auth/login'), 1);
      expect(tokenStore.tokens?.isComplete, isTrue);
      expect(
        currentLocation(),
        Routes.clientHome,
        reason:
            'l’atterrissage est décidé par le gardien, sur le profil chargé',
      );
    },
  );

  // --- Connexion ------------------------------------------------------------

  testWidgets('1.4 — se connecter avant vérification donne une issue', (
    WidgetTester tester,
  ) async {
    await start(tester, at: Routes.login);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Adresse email'),
      kEmail,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mot de passe'),
      kPassword,
    );
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.textContaining('n’est pas encore utilisable'), findsOneWidget);
    expect(find.text('Vérifier mon compte avec un code'), findsOneWidget);
    expect(tokenStore.tokens, isNull);
  });

  testWidgets('1.5 — l’application rouverte restaure la session', (
    WidgetTester tester,
  ) async {
    tokenStore.tokens = const AuthTokens(
      accessToken: 'access-restauré',
      refreshToken: 'refresh-restauré',
    );

    await start(tester);

    expect(currentLocation(), Routes.clientHome);
    expect(
      find.text('Connexion'),
      findsNothing,
      reason: 'aucun écran de connexion ne doit apparaître',
    );
    expect(backend.callsTo('/me'), 1);
  });

  testWidgets(
    '1.5 bis — le démarrage hors ligne route sur le profil en cache',
    (WidgetTester tester) async {
      tokenStore.tokens = const AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
      );

      // Premier démarrage : le profil est mis en cache.
      await start(tester);
      expect(currentLocation(), Routes.clientHome);

      // Second démarrage, réseau coupé.
      backend.offline = true;
      final ProviderContainer second = buildContainer(
        backend,
        database,
        tokenStore,
      );
      addTearDown(second.dispose);
      await tester.pumpWidget(TestApp(container: second));
      await tester.pumpAndSettle();

      expect(
        second
            .read(goRouterProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .toString(),
        Routes.clientHome,
        reason:
            'sans le cache du profil, l’écran de démarrage resterait affiché',
      );
    },
  );

  testWidgets(
    '1.6 — un jeton expiré est renouvelé une seule fois, malgré la concurrence',
    (WidgetTester tester) async {
      tokenStore.tokens = const AuthTokens(
        accessToken: 'access-périmé',
        refreshToken: 'refresh-valide',
      );
      backend.accessTokenExpired = true;

      final ApiClient client = container.read(apiClientProvider);
      // `runAsync` : ces cinq requêtes s'enchaînent en temps réel, hors de l'horloge
      // simulée du test de widget. Sans lui, le rejeu déclenché depuis `onError`
      // n'aboutirait jamais — rien ne fait avancer le temps pendant l'attente.
      await tester.runAsync(() async {
        await Future.wait<void>(<Future<void>>[
          for (int i = 0; i < 5; i++)
            client
                .get<Me>('/me', parse: parseObject<Me>(Me.fromJson))
                .then((_) {}),
        ]);
      });

      expect(
        backend.callsTo('/auth/refresh'),
        1,
        reason:
            'cinq requêtes concurrentes partagent le même renouvellement : '
            'cinq appels atteindraient le plafond du service (invariant 1)',
      );
      expect(
        tokenStore.tokens?.refreshToken,
        isNot('refresh-valide'),
        reason: 'la rotation doit être enregistrée (invariant 2)',
      );
    },
  );

  testWidgets(
    '1.7 — la connexion par téléphone émet des jetons sans mot de passe',
    (WidgetTester tester) async {
      await start(tester, at: Routes.phoneLogin);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Numéro de téléphone'),
        '+2250700000003',
      );
      await tester.tap(find.text('Recevoir un code'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, kGoodCode);
      await tester.pumpAndSettle();

      expect(tokenStore.tokens?.isComplete, isTrue);
      expect(
        backend.callsTo('/auth/login'),
        0,
        reason: 'aucun mot de passe n’intervient dans ce parcours',
      );
      expect(currentLocation(), Routes.clientHome);
    },
  );

  // --- Mot de passe et sortie de compte -------------------------------------

  testWidgets(
    '1.8 — la réinitialisation ferme la session et ramène à la connexion',
    (WidgetTester tester) async {
      tokenStore.tokens = const AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
      );
      await start(tester);

      container.read(goRouterProvider).go(Routes.forgotPassword);
      await tester.pumpAndSettle();
      // Un compte connecté est détourné des écrans d'authentification : on repasse
      // donc par la déconnexion, comme le ferait l'utilisateur.
      expect(currentLocation(), Routes.clientHome);

      await container.read(sessionControllerProvider.notifier).signOut();
      await tester.pumpAndSettle();

      container.read(goRouterProvider).go(Routes.forgotPassword);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Adresse email'),
        kEmail,
      );
      await tester.tap(find.text('Envoyer le code'));
      await tester.pumpAndSettle();

      // Le jeton de développement pré-remplit le champ : c'est ce qui rend le
      // parcours déroulable sans transport email.
      expect(currentLocation(), startsWith(Routes.resetPassword));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Nouveau mot de passe'),
        'nouveau123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirmez le mot de passe'),
        'nouveau123',
      );
      await tester.tap(find.text('Changer mon mot de passe'));
      await tester.pumpAndSettle();

      expect(backend.callsTo('/auth/reset-password'), 1);
      expect(tokenStore.tokens, isNull);
      expect(currentLocation(), startsWith(Routes.login));
    },
  );

  testWidgets('1.9 — la déconnexion purge tout, même réseau coupé', (
    WidgetTester tester,
  ) async {
    tokenStore.tokens = const AuthTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
    );
    await start(tester);
    expect(currentLocation(), Routes.clientHome);

    // Le profil est en cache après le démarrage : il doit disparaître.
    expect(await container.read(cacheDaoProvider).readProfile(), isNotNull);

    backend.offline = true;
    // `runAsync` : l'appel de déconnexion échoue au niveau du transport, et `dio`
    // arme ses minuteries de délai. L'horloge simulée d'un test de widget ne les
    // ferait jamais expirer.
    await tester.runAsync(
      () => container.read(logoutControllerProvider).signOut(),
    );
    await tester.pumpAndSettle();

    expect(tokenStore.tokens, isNull);
    expect(
      await container.read(cacheDaoProvider).readProfile(),
      isNull,
      reason: 'aucune donnée du compte quitté ne reste sur l’appareil (SC-012)',
    );
    expect(currentLocation(), startsWith(Routes.login));
  });

  testWidgets('1.10 — la désactivation refusée affiche le message du service', (
    WidgetTester tester,
  ) async {
    tokenStore.tokens = const AuthTokens(
      accessToken: 'access',
      refreshToken: 'refresh',
    );
    backend.deleteCase = 'deactivateBlockedByMissions';
    await start(tester);

    container.read(goRouterProvider).go(Routes.deactivateAccount);
    await tester.pumpAndSettle();

    // Double confirmation (FR-012) : la case dit « j'ai lu », le mot de passe dit
    // « c'est bien moi », et la boîte de dialogue demande une dernière fois.
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Votre mot de passe'),
      kPassword,
    );
    await tester.pumpAndSettle();

    final Finder submit = find.widgetWithText(
      FilledButton,
      'Désactiver mon compte',
    );
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Désactiver'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('2 mission(s) confirmée(s) ou en cours'),
      findsOneWidget,
      reason: 'le décompte vient du service et n’est pas reconstruit (FR-088)',
    );
    expect(tokenStore.tokens, isNotNull, reason: 'la session reste ouverte');
  });
}
