// T238 — Parcours US10 de bout en bout : scénarios 10.1 à 10.4 de quickstart.md.
//
// Le réseau dégradé : consultation servie par le cache AVEC bannière permanente
// et âge des données (10.1), écritures indisponibles avec explication et SANS
// mise en file (10.2), rafraîchissement automatique de l'écran courant au
// retour du réseau (10.3), contenu sensible JAMAIS restitué depuis le stockage
// local (10.4).
//
// Le portier réseau est substitué (le greffon de connectivité n'existe pas en
// test) ; le service simulé coupe ses réponses quand `networkDown` est vrai.
// Tout le reste — bannière, verrou d'écriture, cache Drift, rafraîchissement —
// est le code livré.
//
// Comme pour US1 à US9, les scénarios sont exposés par [runUs10Scenarios] et
// déroulés par deux points d'entrée : sur appareil (`integration_test/`) et
// sans appareil (`test/flows/`), ce dernier étant le seul que `flutter test`
// atteint — donc le seul que l'intégration continue exécute.

import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/app/router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/connectivity/offline_gate.dart';
import 'package:prestgo_mobile/core/files/file_image.dart' as files;
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_providers.dart';

import '../../test/support/fixtures.dart';
import '../../test/support/recording_adapter.dart';
import '../../test/support/screen_harness.dart';
import '../support/app_harness.dart';

const String kMissionId = 'a75221c8-03a0-4dc7-a4c0-c0047ad0713c';

/// Portier réseau piloté par le scénario — aucun greffon de plateforme.
class FakeOfflineGate extends OfflineGate {
  FakeOfflineGate();

  bool online = true;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  void goOffline() {
    online = false;
    _changes.add(false);
  }

  void goOnline() {
    online = true;
    _changes.add(true);
  }

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> onlineChanges() => _changes.stream;
}

/// Service simulé — coupé quand [networkDown] est vrai.
class OfflineBackend {
  bool networkDown = false;

  final DateTime scheduledAt = DateTime.now().add(const Duration(hours: 20));

  final List<String> journal = <String>[];

  int callsTo(String method, String path) =>
      journal.where((String entry) => entry == '$method $path').length;

  AdapterResponse handle(RequestOptions options, int index) {
    final String path = options.path;
    journal.add('${options.method} $path');

    if (networkDown) {
      throw const NetworkDown();
    }

    switch (path) {
      case '/me':
        return envelope(fixtureData('auth/me', 'client'));

      case '/me/missions':
        return (
          200,
          <String, Object?>{
            'success': true,
            'message': 'OK',
            'data': <Object?>[_listItem()],
            'meta': <String, Object?>{'page': 1, 'limit': 20, 'total': 1},
          },
        );

      case '/missions/$kMissionId':
        return envelope(_detail());

      case '/missions/$kMissionId/history':
        return fixture('missions/history', 'timeline');

      case '/missions/$kMissionId/reschedules':
        return envelope(<Object?>[]);

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

  JsonMap _listItem() => <String, Object?>{
    'id': kMissionId,
    'status': 'confirmed',
    'scheduledAt': MissionDates.toApi(scheduledAt),
    'quotedAmount': 25000,
    'durationMinutes': 90,
    'packTitle': 'Installation de chauffe-eau',
    'clientName': 'Awa Client',
    'providerId': '66cb6dd8-f882-4944-91ab-b5c052e01b3d',
    'providerName': 'Kofi Plomberie',
    'providerAvatarFileId': null,
    'city': 'Abidjan',
    'commune': 'Cocody',
    'createdAt': MissionDates.toApi(
      scheduledAt.subtract(const Duration(days: 1)),
    ),
  };

  JsonMap _detail() {
    final JsonMap detail =
        (jsonDecode(jsonEncode(fixtureData('missions/detail', 'confirmed')))
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    detail['id'] = kMissionId;
    detail['scheduledAt'] = MissionDates.toApi(scheduledAt);
    return detail;
  }
}

/// Déroule les scénarios 10.1 à 10.4.
void runUs10Scenarios() {
  late OfflineBackend backend;
  late FakeOfflineGate gate;
  late RecordingAdapter adapter;
  late LocalDatabase database;
  late InMemoryTokenStore tokenStore;
  late ProviderContainer container;

  setUp(() {
    backend = OfflineBackend();
    gate = FakeOfflineGate();
    adapter = RecordingAdapter(backend.handle);
    database = LocalDatabase.memory();
    tokenStore = InMemoryTokenStore()
      ..tokens = const AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
      );
    container = buildAppContainer(
      adapter: adapter,
      database: database,
      tokenStore: tokenStore,
      offlineGate: gate,
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  Future<void> start(WidgetTester tester, {String? at}) async {
    await tester.pumpWidget(FlowApp(container: container));
    await tester.pumpAndSettle();
    if (at != null) {
      container.read(goRouterProvider).go(at);
      await tester.pumpAndSettle();
    }
  }

  /// Draine les minuteries du rejeu réseau (1,5 s puis 3 s de politique G4) :
  /// `pumpAndSettle` seul tournerait tant qu'une reprise est programmée.
  Future<void> drainRetries(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 20));
    await tester.pump();
  }

  Future<void> cutNetwork(WidgetTester tester) async {
    backend.networkDown = true;
    gate.goOffline();
    await drainRetries(tester);
  }

  Future<void> restoreNetwork(WidgetTester tester) async {
    backend.networkDown = false;
    gate.goOnline();
    await drainRetries(tester);
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  // --- 10.1 — Consultation hors ligne : bannière + âge des données --------------

  testWidgets('10.1 — hors ligne, l’agenda et le détail restent consultables, '
      'coiffés de la bannière permanente et datés', (
    WidgetTester tester,
  ) async {
    await start(tester, at: Routes.missions);
    expect(find.text('Installation de chauffe-eau'), findsOneWidget);

    // Le détail est visité EN LIGNE : c'est lui qui alimente le cache.
    await tester.tap(find.text('Installation de chauffe-eau'));
    await tester.pumpAndSettle();
    container.read(goRouterProvider).go(Routes.missions);
    await tester.pumpAndSettle();

    await cutNetwork(tester);

    // La bannière est là, avec la date des dernières données reçues.
    expect(find.text('Hors ligne — consultation seule'), findsOneWidget);
    expect(find.textContaining('Données du'), findsOneWidget);

    // L'agenda relu passe par le cache — et il est DATÉ.
    container.invalidate(missionTabProvider);
    await drainRetries(tester);
    expect(find.text('Installation de chauffe-eau'), findsOneWidget);
    expect(find.textContaining('Mis à jour'), findsOneWidget);

    // Le détail relu aussi : adresse et instructions sur place.
    container.invalidate(missionDetailProvider(kMissionId));
    container.read(goRouterProvider).go(Routes.missionDetailFor(kMissionId));
    await drainRetries(tester);
    expect(find.text('Hors ligne — consultation seule'), findsOneWidget);
    expect(find.textContaining('Mis à jour'), findsOneWidget);
  });

  // --- 10.2 — Écriture hors ligne : indisponible, expliquée, JAMAIS en file -----

  testWidgets('10.2 — l’annulation hors ligne est indisponible avec son '
      'explication, et RIEN ne part au retour du réseau', (
    WidgetTester tester,
  ) async {
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    await cutNetwork(tester);
    await scrollTo(tester, find.text('Annuler la mission'));

    // Le bouton est fermé et le DIT.
    expect(
      find.text(
        'Action indisponible hors ligne. Reconnectez-vous au réseau pour '
        'continuer.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Annuler la mission'), warnIfMissed: false);
    await tester.pumpAndSettle();
    // Rien n'est parti : ni feuille d'annulation, ni requête.
    expect(backend.callsTo('POST', '/missions/$kMissionId/cancel'), 0);

    // Le réseau revient : RIEN n'a été mémorisé, rien ne part tout seul.
    await restoreNetwork(tester);
    expect(backend.callsTo('POST', '/missions/$kMissionId/cancel'), 0);
  });

  // --- 10.3 — Retour du réseau : l'écran courant se relit tout seul -------------

  testWidgets('10.3 — au retour du réseau, l’écran courant se rafraîchit '
      'automatiquement', (WidgetTester tester) async {
    await start(tester, at: Routes.missions);
    final int loadsBefore = backend.callsTo('GET', '/me/missions');
    expect(loadsBefore, greaterThan(0));

    await cutNetwork(tester);
    await restoreNetwork(tester);

    expect(
      backend.callsTo('GET', '/me/missions'),
      greaterThan(loadsBefore),
      reason: 'la transition hors ligne → en ligne relit l’onglet affiché',
    );
  });

  // --- 10.4 — Contenu sensible : jamais restitué depuis le stockage local -------

  testWidgets('10.4 — un contenu sensible ne passe JAMAIS par le moteur à '
      'cache disque', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: files.FileImage(
            fileId: 'doc-cni-1',
            visibility: FileVisibility.sensitive,
            baseUrl: kFlowBaseUrl,
            accessToken: 'jeton-valide',
          ),
        ),
      ),
    );
    await tester.pump();

    // Le moteur à cache disque n'est pas même instancié : le contenu vit en
    // mémoire d'écran, rouvert hors ligne il ne restitue RIEN (FR-098).
    expect(find.byType(CachedNetworkImage), findsNothing);
    expect(find.byType(Image), findsOneWidget);

    // Sans session, le contenu protégé ne part même pas en requête.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: files.FileImage(
            fileId: 'doc-cni-1',
            visibility: FileVisibility.sensitive,
            baseUrl: kFlowBaseUrl,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
  });
}
