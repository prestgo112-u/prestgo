// T176 — Tableau de bord à blocs indépendants et boutons d'action par état.
//
// Ce que ces tests protègent :
//   • **l'échec d'un bloc n'éteint pas les autres** (FR-065, scénario 5.1) : le
//     bloc en erreur affiche SON message et SA reprise, les voisins vivent ;
//   • **les boutons suivent la table des états** (FR-041, scénario 5.2) :
//     « Refuser » et « Annuler la mission » ne coexistent JAMAIS, aucune action
//     sur un état terminal ;
//   • **la fenêtre de démarrage** (FR-042, scénario 5.3) : bouton indisponible
//     hors fenêtre, heure d'activation affichée — seuil lu auprès du service ;
//   • **le motif est exigé avant l'envoi** (FR-044, scénario 5.4) : un refus
//     sans motif ne part jamais sur le réseau.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_detail.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_actions_bar.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/dashboard_screen.dart';

import '../support/fixtures.dart';
import '../support/recording_adapter.dart';
import '../support/screen_harness.dart';

/// Service simulé du tableau de bord — chaque bloc peut échouer seul.
AdapterScenario dashboardBackend({
  bool pendingFails = false,
  List<String>? journal,
}) => (RequestOptions options, int index) {
  journal?.add('${options.method} ${options.path}');
  switch (options.path) {
    case '/providers/me':
      return fixture('provider/self', 'overviewApproved');
    case '/providers/me/missions':
      final String status = options.uri.queryParameters['status'] ?? '';
      if (status.contains('pending_provider')) {
        if (pendingFails) {
          return (
            500,
            <String, Object?>{
              'success': false,
              'message': 'Le service est momentanément indisponible.',
            },
          );
        }
        return fixture('provider_missions/list', 'pendingRequests');
      }
      return fixture('provider_missions/list', 'today');
    case '/me/notifications/unread-count':
      return (
        200,
        <String, Object?>{
          'success': true,
          'message': 'OK',
          'data': <String, Object?>{'unread': 2},
        },
      );
    default:
      return (
        404,
        <String, Object?>{'success': false, 'message': 'Route non simulée'},
      );
  }
};

/// Détail de mission recomposé pour la barre d'actions : statut et horaire
/// imposés par le test.
MissionDetail detailWith({required String status, DateTime? scheduledAt}) {
  final JsonMap json = JsonMap.of(fixtureData('missions/detail', 'confirmed'));
  json['status'] = status;
  if (scheduledAt != null) {
    json['scheduledAt'] = MissionDates.toApi(scheduledAt);
  }
  return MissionDetail.fromJson(json);
}

/// Barre d'actions montée seule, sur un service simulé de transitions.
ScreenHarness actionsHarness({String transitionCase = 'refused'}) =>
    ScreenHarness((RequestOptions options, int index) {
      if (options.path.startsWith('/missions/')) {
        return fixture('provider_missions/transitions', transitionCase);
      }
      return (
        404,
        <String, Object?>{'success': false, 'message': 'Route non simulée'},
      );
    });

void main() {
  setUpAll(() => initializeDateFormatting(AppFormats.locale));

  group('Tableau de bord (T167, scénario 5.1)', () {
    testWidgets('un bloc en erreur affiche SA reprise — les autres blocs '
        'restent servis', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(
        dashboardBackend(pendingFails: true),
      );
      await harness.pump(tester, const ProviderDashboardScreen());
      await tester.pumpAndSettle();

      // Le bloc en échec : son message et sa reprise.
      expect(find.text('Demandes en attente'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);

      // Les blocs voisins vivent : les missions du jour sont là…
      expect(find.text('Missions du jour'), findsOneWidget);
      expect(find.text('Réparation de fuite simple'), findsOneWidget);
      expect(find.text('Débouchage canalisation'), findsOneWidget);
      // …l'interrupteur de disponibilité aussi, avec son explication (5.6).
      expect(find.text('Occupé'), findsOneWidget);
      expect(
        find.text('Votre fiche est visible et les clients peuvent réserver.'),
        findsOneWidget,
      );
      // …et la pastille de notifications (le « 2 » du compteur de missions du
      // jour existe aussi : on vérifie le bloc, pas l'unicité du chiffre).
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('2'), findsAtLeastNWidgets(1));

      await harness.dispose(tester);
    });

    testWidgets('tous les blocs servis : demandes avec compte à rebours '
        'd’expiration (FR-043)', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(dashboardBackend());
      await harness.pump(tester, const ProviderDashboardScreen());
      await tester.pumpAndSettle();

      expect(find.text('Installation de chauffe-eau'), findsOneWidget);
      // Les demandes de la capture sont créées il y a plus de 24 h :
      // l'expiration est imminente — le badge le dit, il ne la constate pas.
      expect(find.text('Expiration imminente'), findsNWidgets(2));

      await harness.dispose(tester);
    });
  });

  group('Boutons d’action par état (T170, scénario 5.2)', () {
    Future<ScreenHarness> pumpBar(
      WidgetTester tester,
      MissionDetail mission,
    ) async {
      final ScreenHarness harness = actionsHarness();
      await harness.pump(
        tester,
        Scaffold(body: MissionActionsBar(mission: mission)),
      );
      await tester.pumpAndSettle();
      return harness;
    }

    testWidgets('pending_provider : Accepter et Refuser SEULS — jamais '
        '« Annuler »', (WidgetTester tester) async {
      final ScreenHarness harness = await pumpBar(
        tester,
        detailWith(status: 'pending_provider'),
      );

      expect(find.text('Accepter'), findsOneWidget);
      expect(find.text('Refuser'), findsOneWidget);
      expect(find.text('Annuler la mission'), findsNothing);
      expect(find.text('Démarrer la mission'), findsNothing);
      expect(find.text('Terminer la mission'), findsNothing);

      await harness.dispose(tester);
    });

    testWidgets('confirmed : Démarrer et Annuler — plus de Refuser', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpBar(
        tester,
        detailWith(
          status: 'confirmed',
          scheduledAt: DateTime.now().add(const Duration(minutes: 30)),
        ),
      );

      expect(find.text('Démarrer la mission'), findsOneWidget);
      expect(find.text('Annuler la mission'), findsOneWidget);
      expect(find.text('Refuser'), findsNothing);

      await harness.dispose(tester);
    });

    testWidgets('in_progress : Terminer seul', (WidgetTester tester) async {
      final ScreenHarness harness = await pumpBar(
        tester,
        detailWith(status: 'in_progress'),
      );

      expect(find.text('Terminer la mission'), findsOneWidget);
      expect(find.text('Accepter'), findsNothing);
      expect(find.text('Annuler la mission'), findsNothing);

      await harness.dispose(tester);
    });

    testWidgets('état terminal : AUCUNE action (FR-041)', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpBar(
        tester,
        detailWith(status: 'cancelled'),
      );

      // `bySubtype` : les variantes `.icon` des boutons sont des sous-types.
      expect(find.bySubtype<ButtonStyleButton>(), findsNothing);

      await harness.dispose(tester);
    });
  });

  group('Fenêtre de démarrage (T171, scénario 5.3)', () {
    testWidgets('hors fenêtre : bouton indisponible ET heure d’activation '
        'affichée', (WidgetTester tester) async {
      // 4 h avant l'horaire, fenêtre de repli 120 min : fermée.
      final ScreenHarness harness = actionsHarness();
      await harness.pump(
        tester,
        Scaffold(
          body: MissionActionsBar(
            mission: detailWith(
              status: 'confirmed',
              scheduledAt: DateTime.now().add(const Duration(hours: 4)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final FilledButton start = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Démarrer la mission'),
          matching: find.bySubtype<FilledButton>(),
        ),
      );
      expect(start.onPressed, isNull);
      expect(find.textContaining('Disponible à partir'), findsOneWidget);
      expect(
        harness.adapter.calls,
        isEmpty,
        reason: 'un bouton fermé ne déclenche jamais d’appel',
      );

      await harness.dispose(tester);
    });

    testWidgets('dans la fenêtre : le bouton est ouvert, sans mention', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = actionsHarness();
      await harness.pump(
        tester,
        Scaffold(
          body: MissionActionsBar(
            mission: detailWith(
              status: 'confirmed',
              scheduledAt: DateTime.now().add(const Duration(minutes: 90)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final FilledButton start = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Démarrer la mission'),
          matching: find.bySubtype<FilledButton>(),
        ),
      );
      expect(start.onPressed, isNotNull);
      expect(find.textContaining('Disponible à partir'), findsNothing);

      await harness.dispose(tester);
    });
  });

  group('Motif obligatoire (T173, scénario 5.4)', () {
    testWidgets('un refus sans motif est bloqué AVANT tout appel réseau', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = actionsHarness();
      await harness.pump(
        tester,
        Scaffold(
          body: MissionActionsBar(
            mission: detailWith(status: 'pending_provider'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Refuser'));
      await tester.pumpAndSettle();

      // Confirmer sans motif : le contrôle local bloque, rien ne part (5.4).
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser la mission'));
      await tester.pumpAndSettle();
      expect(
        find.text('Indiquez un motif d’au moins 3 caractères.'),
        findsOneWidget,
      );
      expect(harness.adapter.calls, isEmpty);

      // Avec un motif, l'appel part avec le motif dans le corps.
      await tester.enterText(
        find.widgetWithText(TextField, 'Motif (obligatoire)'),
        'Déjà engagé sur un autre chantier.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Refuser la mission'));
      await tester.pumpAndSettle();

      expect(harness.adapter.calls, hasLength(1));
      expect(harness.api.lastUrl, endsWith('/refuse'));
      expect(harness.api.lastBody, <String, Object?>{
        'reason': 'Déjà engagé sur un autre chantier.',
      });

      await harness.dispose(tester);
    });
  });
}
