// T177 — Parcours US5 de bout en bout : scénarios 5.1 à 5.6 de quickstart.md.
//
// La journée du prestataire : tableau de bord composé de blocs indépendants,
// actions de mission conformes à l'état, fenêtre de démarrage, coupure réseau
// sur une transition, interrupteur de disponibilité. Le service simulé porte un
// **état mutable** — le statut de la mission — parce que c'est précisément ce
// que les scénarios font bouger : accepter (5.5), refuser (5.4).
//
// Le scénario 5.5 est le cœur du parcours : la requête d'acceptation **atteint**
// le service (l'état mute) mais la réponse se perd. L'application ne doit
// JAMAIS rejouer (porte G4, FR-046) — elle recharge l'état réel et le montre.
// La chaîne d'intercepteurs traversée est celle de production : ce test vérifie
// donc aussi que la politique de rejeu épargne bien les transitions.
//
// Comme pour US1 à US4, les scénarios sont exposés par [runUs5Scenarios] et
// déroulés par deux points d'entrée : sur appareil (`integration_test/`) et
// sans appareil (`test/flows/`), ce dernier étant le seul que `flutter test`
// atteint — donc le seul que l'intégration continue exécute.

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
import 'package:prestgo_mobile/features/missions/presentation/mission_actions_bar.dart';

import '../../test/support/fixtures.dart';
import '../../test/support/recording_adapter.dart';
import '../../test/support/screen_harness.dart';
import '../support/app_harness.dart';

/// Le prestataire des captures — `provider.id` du détail de mission.
const String kProviderId = '66cb6dd8-f882-4944-91ab-b5c052e01b3d';
const String kMissionId = 'a75221c8-03a0-4dc7-a4c0-c0047ad0713c';

/// Service simulé de la journée du prestataire.
class ProviderDayBackend {
  /// Statut courant de la mission — c'est LUI que les transitions font muter.
  String missionStatus = 'pending_provider';

  /// Horaire de la mission, réglé par chaque scénario (fenêtre de démarrage,
  /// missions du jour).
  DateTime scheduledAt = DateTime.now().add(const Duration(hours: 26));

  /// Date de création de la demande — alimente le compte à rebours (FR-043).
  DateTime createdAt = DateTime.now().subtract(const Duration(hours: 2));

  /// Le bloc « demandes » répond 500 (scénario 5.1).
  bool pendingBlockFails = false;

  /// L'acceptation ABOUTIT côté service mais la réponse se perd (5.5).
  bool cutNetworkOnAccept = false;

  String availabilityStatus = 'available';

  final List<String> journal = <String>[];

  int callsTo(String method, String path) =>
      journal.where((String entry) => entry == '$method $path').length;

  AdapterResponse handle(RequestOptions options, int index) {
    final String path = options.path;
    journal.add('${options.method} $path');
    final JsonMap body = switch (options.data) {
      final Map<Object?, Object?> data => data.cast<String, Object?>(),
      _ => const <String, Object?>{},
    };

    switch (path) {
      case '/me':
        return envelope(_me());

      case '/providers/me':
        if (options.method == 'PATCH') {
          availabilityStatus =
              body['availabilityStatus'] as String? ?? availabilityStatus;
          return envelope(_overview(), message: 'Profil mis à jour');
        }
        return envelope(_overview());

      case '/providers/me/missions':
        return _missions(options);

      case '/me/notifications/unread-count':
        return envelope(<String, Object?>{'unread': 2});

      case '/missions/$kMissionId':
        return envelope(_detail());

      case '/missions/$kMissionId/history':
        return fixture('missions/history', 'timeline');

      case '/missions/$kMissionId/accept':
        // L'appel EST passé : l'état mute, puis la réponse se perd (5.5).
        missionStatus = 'confirmed';
        if (cutNetworkOnAccept) {
          throw const NetworkDown();
        }
        return fixture('provider_missions/transitions', 'accepted');

      case '/missions/$kMissionId/refuse':
        missionStatus = 'cancelled';
        return fixture('provider_missions/transitions', 'refused');

      case '/missions/$kMissionId/start':
        missionStatus = 'in_progress';
        return fixture('provider_missions/transitions', 'started');

      case '/missions/$kMissionId/complete':
        missionStatus = 'completed';
        return fixture('provider_missions/transitions', 'completed');

      case '/missions/$kMissionId/cancel':
        missionStatus = 'cancelled';
        return fixture('provider_missions/transitions', 'cancelled');

      default:
        return (
          404,
          <String, Object?>{
            'success': false,
            'message': 'Route non simulée : ${options.method} $path',
          },
        );
    }
  }

  /// Le compte prestataire approuvé, rattaché AU prestataire des captures.
  JsonMap _me() {
    final JsonMap me = JsonMap.of(fixtureData('auth/me', 'providerApproved'));
    me['providerId'] = kProviderId;
    return me;
  }

  JsonMap _overview() => <String, Object?>{
    'id': kProviderId,
    'publicName': 'Kofi Plomberie',
    'bio': 'Plombier à Abidjan depuis 10 ans.',
    'experienceYears': 10,
    'validationStatus': 'approved',
    'availabilityStatus': availabilityStatus,
    'score': 4.5,
    'reviewsCount': 12,
    'checklist': <String, Object?>{
      'profile': true,
      'services': true,
      'zones': true,
      'availabilities': true,
      'documents': true,
    },
    'requiredDocumentTypes': <String>['id_card'],
    'rejectionReason': null,
    'resubmissionBlocked': false,
    'submittedAt': '2026-07-20T09:00:00.000Z',
    'canSubmit': false,
    'createdAt': '2026-07-19T10:00:00.000Z',
  };

  AdapterResponse _missions(RequestOptions options) {
    final String status = options.uri.queryParameters['status'] ?? '';
    if (status.contains('pending_provider')) {
      if (pendingBlockFails) {
        return (
          500,
          <String, Object?>{
            'success': false,
            'message': 'Le service est momentanément indisponible.',
          },
        );
      }
      return _missionList(included: missionStatus == 'pending_provider');
    }
    return _missionList(
      included: missionStatus == 'confirmed' || missionStatus == 'in_progress',
    );
  }

  AdapterResponse _missionList({required bool included}) {
    final List<Object?> items = <Object?>[if (included) _listItem()];
    return (
      200,
      <String, Object?>{
        'success': true,
        'message': 'OK',
        'data': items,
        'meta': <String, Object?>{
          'page': 1,
          'limit': 20,
          'total': items.length,
        },
      },
    );
  }

  JsonMap _listItem() => <String, Object?>{
    'id': kMissionId,
    'status': missionStatus,
    'scheduledAt': MissionDates.toApi(scheduledAt),
    'quotedAmount': 25000,
    'durationMinutes': 90,
    'packTitle': 'Installation de chauffe-eau',
    'clientName': 'Awa Client',
    'providerId': kProviderId,
    'providerName': 'Kofi Plomberie',
    'providerAvatarFileId': null,
    'city': 'Abidjan',
    'commune': 'Cocody',
    'createdAt': MissionDates.toApi(createdAt),
  };

  /// Le détail, recomposé d'après l'état du scénario.
  JsonMap _detail() {
    // Copie profonde : les fixtures sont partagées entre les tests.
    final JsonMap detail =
        (jsonDecode(jsonEncode(fixtureData('missions/detail', 'confirmed')))
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    detail['id'] = kMissionId;
    detail['status'] = missionStatus;
    detail['scheduledAt'] = MissionDates.toApi(scheduledAt);
    return detail;
  }
}

/// Déroule les scénarios 5.1 à 5.6.
void runUs5Scenarios() {
  late ProviderDayBackend backend;
  late RecordingAdapter adapter;
  late LocalDatabase database;
  late InMemoryTokenStore tokenStore;
  late ProviderContainer container;

  setUp(() {
    backend = ProviderDayBackend();
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

  // --- 5.1 — Un bloc en erreur, les autres restent affichés --------------------

  testWidgets('5.1 — le bloc « demandes » en panne n’éteint NI les missions '
      'du jour NI la disponibilité', (WidgetTester tester) async {
    backend
      ..missionStatus = 'confirmed'
      // Aujourd'hui, pour apparaître dans le bloc « missions du jour ».
      ..scheduledAt = DateTime.now().add(const Duration(minutes: 30))
      ..pendingBlockFails = true;
    signIn();
    await start(tester);

    // Le gardien a routé le compte approuvé sur son tableau de bord.
    expect(locationOf(container), Routes.providerDashboard);

    // Le bloc en panne : son message et SA reprise — rien de plus.
    expect(find.text('Demandes en attente'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);

    // Les blocs voisins vivent (FR-065) : la mission du jour est là…
    expect(find.text('Installation de chauffe-eau'), findsOneWidget);
    // …et l'interrupteur de disponibilité aussi.
    expect(find.text('Occupé'), findsOneWidget);
  });

  // --- 5.2 — Demande non acceptée : Accepter et Refuser seuls ------------------

  testWidgets('5.2 — sur une demande en attente : « Accepter » et « Refuser » '
      'seuls, jamais « Annuler »', (WidgetTester tester) async {
    signIn();
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    await scrollTo(tester, find.text('Accepter'));
    expect(find.text('Accepter'), findsOneWidget);
    expect(find.text('Refuser'), findsOneWidget);
    expect(find.text('Annuler la mission'), findsNothing);
    expect(find.text('Démarrer la mission'), findsNothing);
    expect(find.text('Terminer la mission'), findsNothing);
  });

  // --- 5.3 — Démarrer trop tôt : bouton fermé + heure d'activation -------------

  testWidgets('5.3 — hors fenêtre, « Démarrer » est indisponible et annonce '
      'son heure d’activation', (WidgetTester tester) async {
    backend
      ..missionStatus = 'confirmed'
      // 4 h avant l'horaire, fenêtre de 120 min : fermée pour 2 h encore.
      ..scheduledAt = DateTime.now().add(const Duration(hours: 4));
    signIn();
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    await scrollTo(tester, find.text('Démarrer la mission'));
    final FilledButton startButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Démarrer la mission'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );
    expect(startButton.onPressed, isNull);
    expect(find.textContaining('Disponible à partir'), findsOneWidget);
    expect(
      backend.callsTo('POST', '/missions/$kMissionId/start'),
      0,
      reason: 'un bouton fermé ne part jamais sur le réseau (5.3)',
    );
  });

  // --- 5.4 — Refuser sans motif : envoi bloqué ---------------------------------

  testWidgets('5.4 — un refus sans motif est bloqué localement ; avec motif, '
      'il part et l’écran suit', (WidgetTester tester) async {
    signIn();
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    await scrollTo(tester, find.text('Refuser'));
    await tester.tap(find.text('Refuser'));
    await tester.pumpAndSettle();

    // Confirmer sans motif : le contrôle local bloque, RIEN ne part (5.4).
    await tester.tap(find.widgetWithText(FilledButton, 'Refuser la mission'));
    await tester.pumpAndSettle();
    expect(
      find.text('Indiquez un motif d’au moins 3 caractères.'),
      findsOneWidget,
    );
    expect(backend.callsTo('POST', '/missions/$kMissionId/refuse'), 0);

    // Avec un motif, l'appel part — le motif dans le corps.
    await tester.enterText(
      find.widgetWithText(TextField, 'Motif (obligatoire)'),
      'Je suis déjà engagé sur un autre chantier ce jour-là.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Refuser la mission'));
    await tester.pumpAndSettle();

    expect(backend.callsTo('POST', '/missions/$kMissionId/refuse'), 1);
    expect(
      adapter.lastFor('/missions/$kMissionId/refuse').data,
      <String, Object?>{
        'reason': 'Je suis déjà engagé sur un autre chantier ce jour-là.',
      },
    );
    // Le verdict du service en snackbar, et le détail rechargé suit l'état.
    expect(find.text('Mission refusée'), findsOneWidget);
    expect(backend.missionStatus, 'cancelled');

    await drainSnackBars(tester);
  });

  // --- 5.5 — Coupure réseau juste après « Accepter » ---------------------------

  testWidgets('5.5 — réponse perdue : AUCUN rejeu, l’état réel est rechargé '
      'et affiché', (WidgetTester tester) async {
    backend.cutNetworkOnAccept = true;
    signIn();
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    await scrollTo(tester, find.text('Accepter'));
    await tester.tap(find.text('Accepter'));
    await tester.pumpAndSettle();

    // L'appel est parti UNE fois — la politique de rejeu de production a bien
    // épargné la transition (porte G4, FR-046).
    expect(backend.callsTo('POST', '/missions/$kMissionId/accept'), 1);
    expect(find.text(kTransitionOutcomeUnknownMessage), findsOneWidget);

    // L'état réel — accepté côté service — a été rechargé et affiché : le
    // détail montre « Confirmée », et plus aucun bouton « Accepter ».
    expect(
      backend.callsTo('GET', '/missions/$kMissionId'),
      greaterThanOrEqualTo(2),
      reason: 'le détail est relu auprès du service, pas présumé',
    );
    expect(find.text('Accepter'), findsNothing);
    // La liste garde sa position de défilement après rechargement : la puce de
    // statut vit tout en haut — y remonter avant de la chercher.
    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await tester.pumpAndSettle();
    expect(find.text('Confirmée'), findsOneWidget);

    await drainSnackBars(tester);
  });

  // --- 5.6 — « Occupé » : toujours réservable ----------------------------------

  testWidgets('5.6 — basculer sur « Occupé » envoie le champ SEUL et affiche '
      'son explication', (WidgetTester tester) async {
    signIn();
    await start(tester);

    expect(locationOf(container), Routes.providerDashboard);
    await tester.tap(find.text('Occupé'));
    await tester.pumpAndSettle();

    expect(backend.availabilityStatus, 'busy');
    expect(
      adapter.lastFor('/providers/me').data,
      <String, Object?>{'availabilityStatus': 'busy'},
      reason: 'le réglage d’exploitation part strictement seul',
    );
    // L'explication est là : « Occupé » reste réservable (FR-066).
    expect(
      find.text(
        'Votre fiche reste visible et réservable : seule la pastille change.',
      ),
      findsOneWidget,
    );
  });
}
