// T137 — Parcours US3 de bout en bout : scénarios 3.1 à 3.5 de quickstart.md.
//
// Le suivi client : onglets, détail, annulation avec avertissement de tardiveté,
// reports. Le service simulé porte l'état qu'exigent les scénarios — notamment une
// demande de report en attente dont l'**auteur** varie : c'est lui qui décide si
// les boutons Accepter/Refuser existent (scénario 3.4).
//
// Comme pour US1 et US2, les scénarios sont exposés par [runUs3Scenarios] et
// déroulés par deux points d'entrée : sur appareil (`integration_test/`) et sans
// appareil (`test/flows/`), ce dernier étant le seul que `flutter test` atteint —
// donc le seul que l'intégration continue exécute.
//
// La composition d'une demande de report (sélecteurs de date et d'heure) a ses
// propres vérifications de widgets ; ici elle part par le dépôt, comme US2 ouvrait
// son brouillon sans rejouer la composition — le scénario 3.3 porte sur
// l'**indisponibilité de la seconde demande**, pas sur les sélecteurs.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/app/router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/features/missions/data/reschedule_repository.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_providers.dart';
import 'package:prestgo_mobile/features/missions/presentation/reschedule_request_screen.dart';

import '../../test/support/fixtures.dart';
import '../../test/support/recording_adapter.dart';
import '../../test/support/screen_harness.dart';
import '../support/app_harness.dart';

const String kMeId = 'c4f8a2e1-9d3b-4e5a-8f6c-1a2b3c4d5e6f';
const String kProviderId = '66cb6dd8-f882-4944-91ab-b5c052e01b3d';
const String kMissionId = 'b86332d9-14a0-4ec8-b5d0-d0158ae1824d';

/// Service simulé du suivi de missions.
class MissionBackend {
  /// Une demande de report est-elle en attente sur la mission ?
  bool hasPendingReschedule = false;

  /// Auteur de la demande en attente — c'est lui qui décide des boutons (3.4).
  String pendingCreatedBy = kProviderId;

  /// Horaire de la mission, quand le scénario a besoin d'une proximité précise
  /// avec « maintenant » (avertissement de tardiveté, scénario 3.2).
  DateTime? scheduledAtOverride;

  /// Réponse servie à l'annulation.
  String cancelCase = 'cancelledLate';

  /// Réponse servie à l'acceptation d'un report.
  String acceptCase = 'accepted';

  final List<String> journal = <String>[];

  int callsTo(String path) => journal.where((String p) => p == path).length;

  AdapterResponse handle(RequestOptions options, int index) {
    final String path = options.path;
    journal.add(path);

    switch (path) {
      case '/me':
        return fixture('auth/me', 'client');

      case '/me/missions':
        return switch (options.uri.queryParameters['status']) {
          'pending_provider,confirmed' => fixture('missions/list', 'upcoming'),
          'completed,closed' => fixture('missions/list', 'completedTab'),
          _ => fixture('missions/list', 'empty'),
        };

      case '/missions/$kMissionId':
        return envelope(_detail());

      case '/missions/$kMissionId/history':
        return fixture('missions/history', 'timeline');

      case '/missions/$kMissionId/reschedules':
        return fixture('missions/reschedules', 'historyAll');

      case '/missions/$kMissionId/cancel':
        return fixture('missions/cancel', cancelCase);

      case '/missions/$kMissionId/reschedule':
        // Le service n'admet qu'une demande en attente : la seconde est refusée.
        if (hasPendingReschedule) {
          return fixture('missions/reschedules', 'alreadyPending');
        }
        hasPendingReschedule = true;
        return fixture('missions/reschedules', 'requested');

      default:
        if (path.endsWith('/accept')) {
          return fixture('missions/reschedules', acceptCase);
        }
        if (path.endsWith('/reject')) {
          return fixture('missions/reschedules', 'rejected');
        }
        return (
          404,
          <String, Object?>{
            'success': false,
            'message': 'Route non simulée : $path',
          },
        );
    }
  }

  /// Le détail, recomposé d'après l'état du scénario.
  JsonMap _detail() {
    // Copie profonde : les fixtures sont partagées entre les tests.
    final JsonMap detail =
        (jsonDecode(jsonEncode(fixtureData('missions/detail', 'confirmed')))
                as Map<Object?, Object?>)
            .cast<String, Object?>();

    if (scheduledAtOverride case final DateTime scheduledAt) {
      detail['scheduledAt'] = MissionDates.toApi(scheduledAt);
    }
    if (hasPendingReschedule) {
      final JsonMap pending =
          (jsonDecode(
                    jsonEncode(
                      (fixtureData(
                                'missions/detail',
                                'withPendingReschedule',
                              )['reschedules']!
                              as List<Object?>)
                          .first,
                    ),
                  )
                  as Map<Object?, Object?>)
              .cast<String, Object?>();
      pending['createdBy'] = pendingCreatedBy;
      detail['reschedules'] = <Object?>[pending];
    }
    return detail;
  }
}

/// Déroule les scénarios 3.1 à 3.5.
void runUs3Scenarios() {
  late MissionBackend backend;
  late RecordingAdapter adapter;
  late LocalDatabase database;
  late InMemoryTokenStore tokenStore;
  late ProviderContainer container;

  setUp(() {
    backend = MissionBackend();
    adapter = RecordingAdapter(backend.handle);
    database = LocalDatabase.memory();
    tokenStore = InMemoryTokenStore();
    container = buildAppContainer(
      adapter: adapter,
      database: database,
      tokenStore: tokenStore,
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

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Laisse les minuteries de snackbar s'éteindre avant la fin du test.
  Future<void> drainSnackBars(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 5));

  // --- 3.1 — Un onglet = un appel ---------------------------------------------

  testWidgets('3.1 — l’onglet Terminées part en UN appel, deux statuts', (
    WidgetTester tester,
  ) async {
    signIn();
    await start(tester, at: Routes.missions);

    await tester.tap(find.text('Terminées'));
    await tester.pumpAndSettle();

    final List<RequestOptions> completedCalls = adapter
        .callsToPath('/me/missions')
        .where(
          (RequestOptions call) =>
              call.uri.queryParameters['status'] == 'completed,closed',
        )
        .toList();
    expect(
      completedCalls,
      hasLength(1),
      reason: 'deux statuts, UN appel — jamais un appel par statut (3.1)',
    );

    // L'union arrive dans la même liste : une terminée ET une clôturée.
    expect(find.text('Réparation de fuite simple'), findsOneWidget);
    expect(find.text('Débouchage canalisation'), findsOneWidget);
  });

  // --- 3.2 — Avertissement de tardiveté AVANT l'envoi -------------------------

  testWidgets('3.2 — l’avertissement précède l’appel, le verdict le suit', (
    WidgetTester tester,
  ) async {
    // Une mission à moins du préavis de 6 h : annuler maintenant est tardif.
    backend.scheduledAtOverride = DateTime.now().add(const Duration(hours: 2));
    signIn();
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    await scrollTo(tester, find.text('Annuler la mission'));
    await tester.tap(find.text('Annuler la mission'));
    await tester.pumpAndSettle();

    // L'avertissement est là, et RIEN n'est encore parti.
    expect(
      find.text('Cette annulation sera enregistrée comme tardive.'),
      findsOneWidget,
    );
    expect(backend.callsTo('/missions/$kMissionId/cancel'), 0);

    await tester.enterText(
      find.widgetWithText(TextField, 'Motif (obligatoire)'),
      'Empêchement de dernière minute',
    );
    await tester.tap(find.text('Confirmer l’annulation'));
    await tester.pumpAndSettle();

    expect(backend.callsTo('/missions/$kMissionId/cancel'), 1);
    // Le verdict du service, affiché tel quel.
    expect(
      find.text("Mission annulée. L'annulation est enregistrée comme tardive."),
      findsOneWidget,
    );

    await drainSnackBars(tester);
  });

  // --- 3.3 — Une seule demande de report en attente ---------------------------

  testWidgets('3.3 — la seconde demande est indisponible tant que la première '
      'attend', (WidgetTester tester) async {
    signIn();
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    // Sans demande en attente, l'action est ouverte.
    await scrollTo(tester, find.text('Proposer un report'));
    OutlinedButton button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Proposer un report'),
    );
    expect(button.onPressed, isNotNull);

    // Première demande — elle part et le service la retient. `runAsync` :
    // l'appel vit hors d'un écran, le temps simulé ne le ferait jamais aboutir.
    await tester.runAsync(
      () => container
          .read(rescheduleRepositoryProvider)
          .propose(
            kMissionId,
            newDate: DateTime.now().add(const Duration(days: 3)),
            reason: 'Je ne serai pas là mercredi.',
          ),
    );
    expect(backend.hasPendingReschedule, isTrue);

    // Le détail rechargé grise l'action, avec son explication (3.3).
    container.invalidate(missionDetailProvider(kMissionId));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Proposer un report'));

    button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Proposer un report'),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('Une demande de report est déjà en attente de réponse.'),
      findsOneWidget,
    );
  });

  // --- 3.4 — Sa propre demande : aucun bouton ---------------------------------

  testWidgets('3.4 — aucun bouton Accepter/Refuser sur SA propre demande', (
    WidgetTester tester,
  ) async {
    backend
      ..hasPendingReschedule = true
      ..pendingCreatedBy = kMeId;
    signIn();
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    expect(
      find.text('Votre demande de report est en attente de réponse'),
      findsOneWidget,
    );
    expect(find.text('Accepter'), findsNothing);
    expect(find.text('Refuser'), findsNothing);
  });

  testWidgets('3.4 bis — la demande de l’autre partie, elle, se répond', (
    WidgetTester tester,
  ) async {
    backend.hasPendingReschedule = true;
    signIn();
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    expect(find.text('L’autre partie propose un report'), findsOneWidget);
    expect(find.text('Accepter'), findsOneWidget);
    expect(find.text('Refuser'), findsOneWidget);
  });

  // --- 3.5 — Créneau revalidé à l'acceptation ---------------------------------

  testWidgets('3.5 — un créneau devenu indisponible ouvre la '
      'contre-proposition', (WidgetTester tester) async {
    backend
      ..hasPendingReschedule = true
      ..acceptCase = 'slotGone';
    signIn();
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    await tester.tap(find.text('Accepter'));
    await tester.pumpAndSettle();

    // Le refus du service n'est pas une impasse : une issue est proposée.
    expect(find.text('Créneau indisponible'), findsOneWidget);
    expect(
      find.textContaining("Le prestataire n'est plus disponible"),
      findsOneWidget,
    );

    await tester.tap(find.text('Proposer une autre date'));
    await tester.pumpAndSettle();

    expect(find.byType(RescheduleRequestScreen), findsOneWidget);
    expect(
      find.text(
        'Le créneau accepté n’est plus disponible : proposez une autre date.',
      ),
      findsOneWidget,
    );
  });
}
