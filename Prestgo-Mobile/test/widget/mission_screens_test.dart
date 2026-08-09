// T136 — Onglets de « Mes missions », détail, états vides par onglet.
//
// Ce que ces tests protègent :
//   • **un onglet = un appel** avec les statuts joints — la promesse du scénario
//     3.1 se vérifie dans le journal du service simulé, pas à l'écran ;
//   • **« — » pour un montant absent** — jamais « 0 XOF » ;
//   • **l'annulation tardive est signalée** sur le détail ;
//   • **jamais Accepter/Refuser sur sa propre demande de report** (scénario 3.4).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_detail.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_list_item.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_detail_screen.dart';
import 'package:prestgo_mobile/features/missions/presentation/my_missions_screen.dart';
import 'package:prestgo_mobile/features/missions/presentation/reschedule_response_view.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';

import '../support/fixtures.dart';
import '../support/recording_adapter.dart';
import '../support/screen_harness.dart';

const String kMissionId = 'b86332d9-14a0-4ec8-b5d0-d0158ae1824d';

/// Profil client des captures — l'identité de « moi » dans les tests.
Me get meClient => Me.fromJson(fixtureData('auth/me', 'client'));

/// Contrôleur de profil arrêté sur une valeur connue : le vrai contrôleur
/// exigerait une session complète, hors sujet pour un test d'écran de mission.
class StubMeController extends MeController {
  StubMeController(this._me);

  final Me? _me;

  @override
  Future<Me?> build() async => _me;
}

/// Sert les missions d'après le paramètre `status`, comme le ferait le service.
AdapterScenario missionsBackend({
  Map<String, String> listCases = const <String, String>{},
  String detailCase = 'confirmed',
  List<String>? journal,
}) => (RequestOptions options, int index) {
  journal?.add(options.uri.toString());
  if (options.path == '/me/missions') {
    final String status = options.uri.queryParameters['status'] ?? '';
    return fixture('missions/list', listCases[status] ?? 'empty');
  }
  if (options.path == '/missions/$kMissionId') {
    return fixture('missions/detail', detailCase);
  }
  return (
    404,
    <String, Object?>{'success': false, 'message': 'Route non simulée'},
  );
};

Future<ScreenHarness> pumpWithMe(
  WidgetTester tester,
  Widget screen, {
  required AdapterScenario backend,
  Me? me,
}) async {
  final ScreenHarness harness = ScreenHarness(backend);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...harness.overrides,
        meControllerProvider.overrideWith(() => StubMeController(me)),
      ],
      child: MaterialApp(home: screen),
    ),
  );
  await tester.pump();
  return harness;
}

void main() {
  setUpAll(() => initializeDateFormatting(AppFormats.locale));

  group('Mes missions — un onglet = un appel (scénario 3.1)', () {
    testWidgets('l’onglet À venir part en un appel, statuts joints', (
      WidgetTester tester,
    ) async {
      final List<String> journal = <String>[];
      final ScreenHarness harness = await pumpWithMe(
        tester,
        const MyMissionsScreen(),
        backend: missionsBackend(
          listCases: const <String, String>{
            'pending_provider,confirmed': 'upcoming',
          },
          journal: journal,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        journal.where((String url) => url.contains('/me/missions')),
        hasLength(1),
        reason: 'deux statuts, UN appel — jamais un appel par statut',
      );
      expect(journal.single, contains('status=pending_provider%2Cconfirmed'));
      expect(find.text('Installation de chauffe-eau'), findsOneWidget);
      expect(find.text('Réparation de fuite simple'), findsOneWidget);

      await harness.dispose(tester);
    });

    testWidgets('l’onglet Terminées demande completed,closed en un appel', (
      WidgetTester tester,
    ) async {
      final List<String> journal = <String>[];
      final ScreenHarness harness = await pumpWithMe(
        tester,
        const MyMissionsScreen(),
        backend: missionsBackend(
          listCases: const <String, String>{
            'pending_provider,confirmed': 'upcoming',
            'completed,closed': 'completedTab',
          },
          journal: journal,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terminées'));
      await tester.pumpAndSettle();

      expect(
        journal.where(
          (String url) => url.contains('status=completed%2Cclosed'),
        ),
        hasLength(1),
      );
      // L'union des deux statuts arrive dans la même liste.
      expect(find.text('Débouchage canalisation'), findsOneWidget);

      await harness.dispose(tester);
    });

    testWidgets('un montant absent s’affiche « — », jamais 0 XOF', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpWithMe(
        tester,
        const MyMissionsScreen(),
        backend: missionsBackend(
          listCases: const <String, String>{
            'pending_provider,confirmed': 'confirmedOnly',
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('0 XOF'), findsNothing);

      await harness.dispose(tester);
    });
  });

  group('États vides — un message par onglet (FR-037)', () {
    testWidgets('À venir : message dédié et bouton « Réserver »', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpWithMe(
        tester,
        const MyMissionsScreen(),
        backend: missionsBackend(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aucune mission à venir'), findsOneWidget);
      expect(find.text('Réserver une prestation'), findsOneWidget);

      await harness.dispose(tester);
    });

    testWidgets('Annulées : message dédié, sans incitation à réserver', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpWithMe(
        tester,
        const MyMissionsScreen(),
        backend: missionsBackend(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annulées'));
      await tester.pumpAndSettle();

      expect(find.text('Aucune mission annulée'), findsOneWidget);
      expect(find.text('Réserver une prestation'), findsNothing);

      await harness.dispose(tester);
    });
  });

  group('Détail de mission', () {
    testWidgets('montant « — », conversation et actions client présentes', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpWithMe(
        tester,
        const MissionDetailScreen(missionId: kMissionId),
        backend: missionsBackend(),
        me: meClient,
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirmée'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      expect(find.textContaining('0 XOF'), findsNothing);
      expect(find.text('Ouvrir la conversation'), findsOneWidget);
      expect(find.text('Proposer un report'), findsOneWidget);
      expect(find.text('Annuler la mission'), findsOneWidget);
      // Aucune coordonnée personnelle de l'autre partie.
      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('+225'), findsNothing);

      await harness.dispose(tester);
    });

    testWidgets('vu par un autre compte, aucune action client', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpWithMe(
        tester,
        const MissionDetailScreen(missionId: kMissionId),
        backend: missionsBackend(),
        // Profil inconnu : les actions réservées au client sont retenues.
      );
      await tester.pumpAndSettle();

      expect(find.text('Annuler la mission'), findsNothing);
      expect(find.text('Proposer un report'), findsNothing);
      expect(find.text('Ouvrir la conversation'), findsOneWidget);

      await harness.dispose(tester);
    });

    testWidgets('une annulation tardive est signalée explicitement', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpWithMe(
        tester,
        const MissionDetailScreen(
          missionId: 'f2a772a3-58f5-4b3d-e915-1549cf25c681',
        ),
        backend: (RequestOptions options, int index) =>
            fixture('missions/detail', 'cancelledLate'),
        me: meClient,
      );
      await tester.pumpAndSettle();

      expect(find.text('Mission annulée — annulation tardive'), findsOneWidget);
      expect(
        find.text('Motif : Empêchement de dernière minute'),
        findsOneWidget,
      );

      await harness.dispose(tester);
    });

    testWidgets(
      'une demande en attente grise « Proposer un report » (scénario 3.3)',
      (WidgetTester tester) async {
        final ScreenHarness harness = await pumpWithMe(
          tester,
          const MissionDetailScreen(missionId: kMissionId),
          backend: missionsBackend(detailCase: 'withPendingReschedule'),
          me: meClient,
        );
        await tester.pumpAndSettle();

        // La carte de report allonge la page : l'action est sous le pli.
        await tester.scrollUntilVisible(
          find.text('Proposer un report'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        final Finder button = find.widgetWithText(
          OutlinedButton,
          'Proposer un report',
        );
        expect(button, findsOneWidget);
        expect(
          tester.widget<OutlinedButton>(button).onPressed,
          isNull,
          reason: 'une seule demande en attente à la fois',
        );
        expect(
          find.text('Une demande de report est déjà en attente de réponse.'),
          findsOneWidget,
        );

        await harness.dispose(tester);
      },
    );
  });

  group('Réponse à un report (scénario 3.4)', () {
    MissionDetail missionWithPending() => MissionDetail.fromJson(
      fixtureData('missions/detail', 'withPendingReschedule'),
    );

    testWidgets('demande de l’autre partie : Accepter et Refuser visibles', (
      WidgetTester tester,
    ) async {
      final MissionDetail mission = missionWithPending();
      final ScreenHarness harness = await pumpWithMe(
        tester,
        Scaffold(
          body: RescheduleResponseView(
            mission: mission,
            reschedule: mission.pendingReschedule!,
          ),
        ),
        backend: missionsBackend(),
        me: meClient,
      );
      await tester.pump();

      expect(find.text('L’autre partie propose un report'), findsOneWidget);
      expect(find.text('Accepter'), findsOneWidget);
      expect(find.text('Refuser'), findsOneWidget);

      await harness.dispose(tester);
    });

    testWidgets('sa propre demande : AUCUN bouton de réponse', (
      WidgetTester tester,
    ) async {
      final MissionDetail mission = missionWithPending();
      // La même demande, vue par son auteur (le prestataire).
      final Me provider = Me.fromJson(<String, Object?>{
        ...fixtureData('auth/me', 'client'),
        'id': mission.pendingReschedule!.createdBy,
      });
      final ScreenHarness harness = await pumpWithMe(
        tester,
        Scaffold(
          body: RescheduleResponseView(
            mission: mission,
            reschedule: mission.pendingReschedule!,
          ),
        ),
        backend: missionsBackend(),
        me: provider,
      );
      await tester.pump();

      expect(
        find.text('Votre demande de report est en attente de réponse'),
        findsOneWidget,
      );
      expect(find.text('Accepter'), findsNothing);
      expect(find.text('Refuser'), findsNothing);

      await harness.dispose(tester);
    });

    testWidgets('profil inconnu : aucune action non plus', (
      WidgetTester tester,
    ) async {
      final MissionDetail mission = missionWithPending();
      final ScreenHarness harness = await pumpWithMe(
        tester,
        Scaffold(
          body: RescheduleResponseView(
            mission: mission,
            reschedule: mission.pendingReschedule!,
          ),
        ),
        backend: missionsBackend(),
      );
      await tester.pump();

      expect(find.text('Accepter'), findsNothing);
      expect(find.text('Refuser'), findsNothing);

      await harness.dispose(tester);
    });
  });

  group('Ligne de mission', () {
    testWidgets('statut, lieu et horaire sont lisibles d’un coup d’œil', (
      WidgetTester tester,
    ) async {
      final MissionListItem mission = MissionListItem.fromJson(
        (fixtureBody('missions/list', 'upcoming')['data']! as List<Object?>)
                .first
            as Map<String, Object?>,
      );
      final ScreenHarness harness = await pumpWithMe(
        tester,
        Scaffold(body: MissionTile(mission: mission)),
        backend: missionsBackend(),
      );
      await tester.pump();

      expect(find.text('Installation de chauffe-eau'), findsOneWidget);
      expect(find.text('En attente du prestataire'), findsOneWidget);
      expect(find.textContaining('Cocody, Abidjan'), findsOneWidget);

      await harness.dispose(tester);
    });
  });
}
