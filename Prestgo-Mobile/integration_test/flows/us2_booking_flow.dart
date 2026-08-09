// T119 — Parcours US2 de bout en bout : scénarios 2.1 à 2.10 de quickstart.md.
//
// Le chemin critique de l'application : chercher, ouvrir une fiche, réserver. Le
// service simulé porte l'état qu'exigent les scénarios — notamment une réservation
// déjà enregistrée, sans laquelle 2.9 ne prouverait rien.
//
// Comme pour US1, les scénarios sont exposés par [runUs2Scenarios] et déroulés par
// deux points d'entrée : sur appareil (`integration_test/`) et sans appareil
// (`test/flows/`), ce dernier étant le seul que `flutter test` atteint — donc le seul
// que l'intégration continue exécute.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/app/router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/idempotency.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/location/location_service.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/features/auth/presentation/login/login_screen.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_draft.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_rules.dart';
import 'package:prestgo_mobile/features/booking/presentation/booking_draft_controller.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/search/domain/provider_search.dart';
import 'package:prestgo_mobile/features/search/presentation/search_controller.dart';

import '../../test/support/fixtures.dart';
import '../../test/support/recording_adapter.dart';
import '../../test/support/screen_harness.dart';
import '../support/app_harness.dart';

const String kProviderId = 'p-4c8e1a05-7b3d-4f62-9e08-1a5c7d9e0b3f';
const String kPackId = 'pack-71111111-1111-4111-8111-111111111111';
const String kOptionId = 'opt-81111111-1111-4111-8111-111111111111';

/// Service simulé du parcours de réservation.
class BookingBackend {
  /// Coupure réseau, activable en cours de scénario.
  bool offline = false;

  /// La réservation a-t-elle déjà abouti côté service ?
  ///
  /// C'est cet état qui fait la différence entre 2.9 (« déjà enregistrée ») et une
  /// seconde création — le cœur du scénario.
  bool missionCreated = false;

  /// Réponse à servir sur `POST /missions` tant que rien n'a abouti.
  String createCase = 'created';

  /// Clés d'idempotence reçues, dans l'ordre.
  final List<String> idempotencyKeys = <String>[];

  /// Corps de création reçus.
  final List<Map<String, Object?>> createBodies = <Map<String, Object?>>[];

  final List<String> journal = <String>[];

  int callsTo(String path) => journal.where((String p) => p == path).length;

  AdapterResponse handle(RequestOptions options, int index) {
    final String path = options.path;
    journal.add(path);

    if (offline) {
      throw const NetworkDown();
    }

    switch (path) {
      case '/categories':
        return fixture('booking/catalog', 'categories');
      case '/zones':
        return fixture('booking/catalog', 'zones');
      case '/zones/nearby':
        return fixture('booking/catalog', 'nearby');
      case '/providers/search':
        return fixture('booking/search', 'firstPage');
      case '/providers/$kProviderId/public':
        return fixture('booking/provider_public', 'complete');
      case '/me':
        return fixture('auth/me', 'client');
      case '/me/addresses':
        return fixture('booking/addresses', 'list');
      case '/me/favorites':
        return fixture('booking/favorites', 'empty');
      case '/auth/login':
        return fixture('auth/login', 'authenticated');

      case '/missions':
        final String? key = options.headers[kIdempotencyKeyHeader] as String?;
        if (key != null) {
          idempotencyKeys.add(key);
        }
        createBodies.add(
          (options.data as Map<Object?, Object?>? ?? <Object?, Object?>{})
              .cast<String, Object?>(),
        );

        // Une clé déjà aboutie rend la mission d'origine : rien n'est recréé.
        if (missionCreated) {
          return fixture('booking/booking', 'alreadyRecorded');
        }
        if (createCase == 'created') {
          missionCreated = true;
        }
        return fixture('booking/booking', createCase);

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

/// Déroule les scénarios 2.1 à 2.10.
void runUs2Scenarios() {
  late BookingBackend backend;
  late RecordingAdapter adapter;
  late LocalDatabase database;
  late InMemoryTokenStore tokenStore;
  late FakeLocationService location;
  late ProviderContainer container;

  setUp(() {
    backend = BookingBackend();
    adapter = RecordingAdapter(backend.handle);
    database = LocalDatabase.memory();
    tokenStore = InMemoryTokenStore();
    location = FakeLocationService();
    container = buildAppContainer(
      adapter: adapter,
      database: database,
      tokenStore: tokenStore,
      location: location,
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  void signIn() => tokenStore.tokens = const AuthTokens(
    accessToken: 'access',
    refreshToken: 'refresh',
  );

  Future<void> start(WidgetTester tester, {String? at}) async {
    await tester.pumpWidget(FlowApp(container: container));
    await tester.pumpAndSettle();
    if (at != null) {
      container.read(goRouterProvider).go(at);
      await tester.pumpAndSettle();
    }
  }

  /// Ouvre un brouillon complet sans passer par les écrans — les scénarios qui
  /// portent sur la confirmation n'ont pas à rejouer la composition.
  Future<BookingDraftController> openDraft(WidgetTester tester) async {
    final ProviderPublicProfile provider = ProviderPublicProfile.fromJson(
      fixtureData('booking/provider_public', 'complete'),
    );
    final Address address = Address.fromJson(
      (fixtureBody('booking/addresses', 'list')['data']! as List<Object?>).first
          as Map<String, Object?>,
    );
    final BookingDraftController controller = container.read(
      bookingDraftProvider.notifier,
    );
    controller
      ..start(provider)
      ..selectPack(provider.packs.first)
      ..selectSchedule(DateTime.utc(2026, 8, 3, 9))
      ..selectAddress(address);
    return controller;
  }

  // --- Consultation sans compte ---------------------------------------------

  testWidgets('2.1 — l’accueil est consultable sans compte', (
    WidgetTester tester,
  ) async {
    await start(tester);

    expect(tokenStore.tokens, isNull, reason: 'aucune session');
    expect(locationOf(container), Routes.home);
    expect(
      backend.callsTo('/providers/search'),
      1,
      reason: 'la recherche part sans qu’aucun jeton soit exigé (FR-022)',
    );
    expect(find.text('Adjoua Plomberie'), findsOneWidget);
    expect(
      find.text('Nouveau'),
      findsOneWidget,
      reason: 'le prestataire sans avis n’affiche pas une note de 0',
    );
  });

  testWidgets('2.1 bis — la fiche s’ouvre en un seul appel, sans compte', (
    WidgetTester tester,
  ) async {
    await start(tester, at: Routes.providerProfileFor(kProviderId));

    expect(
      backend.callsTo('/providers/$kProviderId/public'),
      1,
      reason: 'toutes les sections viennent du même appel (FR-027)',
    );
    expect(find.text('Réserver'), findsOneWidget);
  });

  // --- Filtres : les refus du service sont devancés --------------------------

  testWidgets('2.2 — le tri « distance » sans position n’est jamais envoyé', (
    WidgetTester tester,
  ) async {
    await start(tester);

    // La localisation est refusée : le tri par distance doit rester fermé.
    location.result = const LocationResult(outcome: LocationOutcome.denied);
    final LocationResult granted = await container
        .read(searchQueryProvider.notifier)
        .requestPosition();
    await tester.pumpAndSettle();

    expect(granted.isGranted, isFalse);
    expect(
      container.read(searchQueryProvider).isDistanceSortAvailable,
      isFalse,
    );

    // Même demandé explicitement, il n'est pas appliqué.
    container.read(searchQueryProvider.notifier).setSort(SearchSort.distance);
    await tester.pumpAndSettle();
    expect(container.read(searchQueryProvider).sort, isNull);

    for (final RequestOptions call in adapter.callsToPath(
      '/providers/search',
    )) {
      expect(
        call.queryParameters.containsKey('sort'),
        isFalse,
        reason: 'aucun appel refusé côté service (scénario 2.2)',
      );
    }
  });

  testWidgets('2.2 bis — la position accordée rouvre le tri par distance', (
    WidgetTester tester,
  ) async {
    location.result = const LocationResult(
      outcome: LocationOutcome.granted,
      point: GeoPoint(latitude: 5.35, longitude: -3.98),
    );
    await start(tester);

    await container.read(searchQueryProvider.notifier).requestPosition();
    container.read(searchQueryProvider.notifier).setSort(SearchSort.distance);
    await tester.pumpAndSettle();

    expect(container.read(searchQueryProvider).sort, SearchSort.distance);
    expect(
      adapter.callsToPath('/providers/search').last.queryParameters['sort'],
      'distance',
    );
  });

  testWidgets('2.3 — date et heure ne peuvent pas être dissociées', (
    WidgetTester tester,
  ) async {
    await start(tester);

    // Le type l'impose : `SearchSlot` exige les deux. Il n'existe aucun chemin
    // permettant d'envoyer l'une sans l'autre.
    container
        .read(searchQueryProvider.notifier)
        .setSlot(
          SearchSlot(date: DateTime.utc(2026, 8, 3), startTime: '09:00'),
        );
    await tester.pumpAndSettle();

    final RequestOptions call = adapter.callsToPath('/providers/search').last;
    expect(call.queryParameters['date'], '2026-08-03');
    expect(call.queryParameters['startTime'], '09:00');

    for (final RequestOptions previous in adapter.callsToPath(
      '/providers/search',
    )) {
      expect(
        previous.queryParameters.containsKey('date') ==
            previous.queryParameters.containsKey('startTime'),
        isTrue,
        reason: 'les deux partent ensemble, ou pas du tout (scénario 2.3)',
      );
    }
  });

  // --- Mur d'authentification -------------------------------------------------

  testWidgets('2.4 — « Réserver » sans compte passe par la connexion', (
    WidgetTester tester,
  ) async {
    await start(tester, at: Routes.providerProfileFor(kProviderId));

    await tester.tap(find.text('Réserver'));
    await tester.pumpAndSettle();

    expect(locationOf(container), startsWith(Routes.login));
    final LoginScreen login = tester.widget<LoginScreen>(
      find.byType(LoginScreen),
    );
    expect(
      login.redirectTo,
      Routes.providerProfileFor(kProviderId),
      reason:
          'la route mémorisée est **la fiche**, pas l’écran de réservation que '
          'l’utilisateur n’avait pas encore ouvert (scénario 2.4)',
    );
    expect(
      backend.callsTo('/missions'),
      0,
      reason: 'aucune réservation n’est tentée sans session',
    );
  });

  testWidgets('2.4 bis — après connexion, on revient sur la fiche', (
    WidgetTester tester,
  ) async {
    await start(tester, at: Routes.providerProfileFor(kProviderId));
    await tester.tap(find.text('Réserver'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Adresse email'),
      'client.demo@prestgo.test',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Mot de passe'),
      'prestgo123!',
    );
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(tokenStore.tokens?.isComplete, isTrue);
    expect(
      locationOf(container),
      Routes.providerProfileFor(kProviderId),
      reason: 'retour sur la même fiche (scénario 2.4)',
    );
  });

  // --- Composition ------------------------------------------------------------

  testWidgets('2.5 — le total affiché est celui que le service fige', (
    WidgetTester tester,
  ) async {
    signIn();
    await start(tester);

    final BookingDraftController controller = await openDraft(tester);
    controller.toggleOption(kOptionId);
    controller.selectSchedule(DateTime.utc(2026, 8, 3, 9));
    await tester.pumpAndSettle();

    final BookingDraft draft = container.read(bookingDraftProvider)!.draft;
    expect(draft.totalPrice, 6500);
    expect(draft.totalDurationMinutes, 60);

    await tester.runAsync(controller.confirm);
    await tester.pumpAndSettle();

    expect(
      container.read(bookingDraftProvider)!.mission!.quotedAmount,
      draft.totalPrice,
      reason: 'un écart se verrait au récapitulatif, trop tard',
    );
  });

  testWidgets('2.6 — un horaire trop proche n’est pas proposable', (
    WidgetTester tester,
  ) async {
    signIn();
    await start(tester);
    final BookingDraftController controller = await openDraft(tester);

    // Le délai vient du réglage lu au démarrage, pas d'une constante d'écran.
    expect(controller.minLeadTimeMinutes, 60);

    final ProviderPublicProfile provider = container
        .read(bookingDraftProvider)!
        .draft
        .provider;
    final DateTime now = DateTime.utc(2026, 8, 3, 8);
    final List<String> starts = BookingRules.availableStartTimes(
      provider: provider,
      day: DateTime.utc(2026, 8, 3),
      durationMinutes: 45,
      now: now,
      minLeadTimeMinutes: controller.minLeadTimeMinutes,
    ).map((dynamic time) => '$time').toList();

    expect(starts, isNot(contains('08:00')));
    expect(starts.first, '09:00');
  });

  testWidgets('2.7 — un début qui déborde du créneau n’est pas proposé', (
    WidgetTester tester,
  ) async {
    signIn();
    await start(tester);
    await openDraft(tester);

    final ProviderPublicProfile provider = container
        .read(bookingDraftProvider)!
        .draft
        .provider;
    // Lundi, créneau du matin 08:00–12:00, intervention d'une heure.
    final List<String> starts = BookingRules.availableStartTimes(
      provider: provider,
      day: DateTime.utc(2026, 8, 3),
      durationMinutes: 60,
      now: DateTime.utc(2026, 8, 1, 8),
      minLeadTimeMinutes: 60,
    ).map((dynamic time) => '$time').toList();

    expect(starts, contains('11:00'));
    expect(
      starts,
      isNot(contains('11:30')),
      reason: '11:30 + 1 h déborderait de 12:00 (scénario 2.7)',
    );
  });

  // --- Refus corrigeable ------------------------------------------------------

  testWidgets('2.8 — une adresse hors zone ramène à l’étape adresse', (
    WidgetTester tester,
  ) async {
    signIn();
    backend.createCase = 'addressOutOfZone';
    await start(tester);

    final BookingDraftController controller = await openDraft(tester);
    await tester.runAsync(controller.confirm);
    await tester.pumpAndSettle();

    final BookingState booking = container.read(bookingDraftProvider)!;
    expect(booking.correction, isNotNull);
    expect(booking.correction!.step, BookingStep.address);
    expect(
      booking.correction!.showsCoveredZones,
      isTrue,
      reason: 'les zones couvertes sont déjà en mémoire depuis la fiche',
    );
    expect(
      booking.correction!.message,
      "Cette adresse n'est pas dans la zone d'intervention du prestataire",
    );
    // Le brouillon survit au refus : rien n'est à ressaisir (FR-035).
    expect(booking.draft.pack, isNotNull);
    expect(booking.draft.scheduledAt, isNotNull);
  });

  // --- Idempotence : le cœur de la phase --------------------------------------

  testWidgets('2.9 — coupure pendant la confirmation : UNE seule mission', (
    WidgetTester tester,
  ) async {
    signIn();
    await start(tester);
    final BookingDraftController controller = await openDraft(tester);

    // Première tentative : le réseau tombe pendant l'appel.
    backend.offline = true;
    await tester.runAsync(controller.confirm);
    await tester.pumpAndSettle();

    final String? keyAfterFailure = controller.currentKey?.value;
    expect(keyAfterFailure, isNotNull);
    expect(container.read(bookingDraftProvider)!.isConfirmed, isFalse);

    // Le service avait en fait reçu la première requête : elle a abouti.
    backend
      ..offline = false
      ..missionCreated = true;

    // Seconde tentative, sans rien modifier.
    await tester.runAsync(controller.confirm);
    await tester.pumpAndSettle();

    final BookingState booking = container.read(bookingDraftProvider)!;
    expect(booking.isConfirmed, isTrue);
    expect(
      booking.wasAlreadyRecorded,
      isTrue,
      reason: 'le second appel rend la mission d’origine (FR-034)',
    );
    expect(
      backend.idempotencyKeys.toSet(),
      hasLength(1),
      reason:
          'toutes les tentatives sur le même contenu portent LA MÊME clé — '
          'c’est ce qui empêche la seconde réservation',
    );
    expect(backend.idempotencyKeys.first, keyAfterFailure);
  });

  testWidgets('2.10 — modifier une option émet une clé neuve', (
    WidgetTester tester,
  ) async {
    signIn();
    backend.createCase = 'slotTaken';
    await start(tester);
    final BookingDraftController controller = await openDraft(tester);

    await tester.runAsync(controller.confirm);
    await tester.pumpAndSettle();
    final String firstKey = backend.idempotencyKeys.single;

    // Refus métier : le service a libéré la clé. L'utilisateur corrige.
    backend.createCase = 'created';
    controller
      ..toggleOption(kOptionId)
      ..selectSchedule(DateTime.utc(2026, 8, 3, 9));
    await tester.pumpAndSettle();

    await tester.runAsync(controller.confirm);
    await tester.pumpAndSettle();

    expect(backend.idempotencyKeys, hasLength(2));
    expect(
      backend.idempotencyKeys.last,
      isNot(firstKey),
      reason: 'le contenu a changé : une clé neuve est émise (scénario 2.10)',
    );
    expect(container.read(bookingDraftProvider)!.isConfirmed, isTrue);
  });

  testWidgets('la réservation part avec un instant UTC et des options triées', (
    WidgetTester tester,
  ) async {
    signIn();
    await start(tester);
    final BookingDraftController controller = await openDraft(tester);
    controller
      ..toggleOption(kOptionId)
      ..selectSchedule(DateTime.utc(2026, 8, 3, 9));
    await tester.pumpAndSettle();

    await tester.runAsync(controller.confirm);
    await tester.pumpAndSettle();

    final Map<String, Object?> body = backend.createBodies.single;
    expect(body['scheduledAt'], '2026-08-03T09:00:00.000Z');
    expect(body['providerId'], kProviderId);
    expect(body['packId'], kPackId);
    expect(body['optionIds'], <String>[kOptionId]);
  });
}
