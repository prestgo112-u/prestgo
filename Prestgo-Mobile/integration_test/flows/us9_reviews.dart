// T229 — Parcours US9 de bout en bout : scénarios 9.1 à 9.4 de quickstart.md.
//
// La boucle de confiance : le client d'une mission terminée voit « Laisser un
// avis » avec le temps restant (9.1), le prestataire de la MÊME mission ne
// voit aucune action de notation (9.2), le dépôt retire l'action et l'avis
// devient consultable dans « Mes avis » (9.3), le signalement d'un avis déjà
// signalé devient la mention « déjà signalé » (9.4).
//
// Le service simulé date l'entrée en `completed` d'avant-hier : la fenêtre de
// 14 jours (réglage de repli) est ouverte, il reste 12 jours — le libellé du
// temps restant est donc DÉTERMINISTE.
//
// Comme pour US1 à US8, les scénarios sont exposés par [runUs9Scenarios] et
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

import '../../test/support/fixtures.dart';
import '../../test/support/recording_adapter.dart';
import '../../test/support/screen_harness.dart';
import '../support/app_harness.dart';

/// Les identifiants des captures : le client et le prestataire de la mission.
const String kMissionId = 'a75221c8-03a0-4dc7-a4c0-c0047ad0713c';
const String kClientId = 'c4f8a2e1-9d3b-4e5a-8f6c-1a2b3c4d5e6f';
const String kProviderId = '66cb6dd8-f882-4944-91ab-b5c052e01b3d';
const String kReviewAId = 'r-aaaa1111-2222-4333-8444-555566667777';
const String kReviewBId = 'r-bbbb1111-2222-4333-8444-555566667777';

/// Service simulé de la boucle d'avis.
class ReviewsBackend {
  ReviewsBackend({required this.actAsProvider});

  /// Vrai pour le scénario 9.2 : `/me` répond le compte PRESTATAIRE de la
  /// mission — même mission, autre lecteur.
  final bool actAsProvider;

  /// L'avis du client, une fois déposé (9.3).
  bool myReviewSubmitted = false;

  /// Signalements reçus, par avis — le premier de `r-A` passe, le second est
  /// un 409 ; `r-B` a « déjà été signalé depuis un autre appareil ».
  final Map<String, int> reports = <String, int>{kReviewBId: 1};

  // Il y a « 2 jours moins 1 heure » : le reliquat (12 jours et 1 heure)
  // arrondit franchement à 12 jours — un « now - 2 jours » exact tomberait à
  // 11 j 23 h 59 min le temps que le test s'exécute.
  final DateTime completedAt = DateTime.now().subtract(
    const Duration(days: 1, hours: 23),
  );

  final List<String> journal = <String>[];

  int callsTo(String method, String path) =>
      journal.where((String entry) => entry == '$method $path').length;

  AdapterResponse handle(RequestOptions options, int index) {
    final String path = options.path;
    journal.add('${options.method} $path');

    switch (path) {
      case '/me':
        if (actAsProvider) {
          final JsonMap me = JsonMap.of(
            fixtureData('auth/me', 'providerApproved'),
          );
          me['providerId'] = kProviderId;
          return envelope(me);
        }
        return envelope(fixtureData('auth/me', 'client'));

      case '/missions/$kMissionId':
        return envelope(_detail());

      case '/missions/$kMissionId/history':
        return envelope(<String, Object?>{
          'statusHistory': <Object?>[
            <String, Object?>{
              'id': 'h-1',
              'oldStatus': 'in_progress',
              'newStatus': 'completed',
              'reason': 'Intervention terminée',
              'createdAt': MissionDates.toApi(completedAt),
            },
          ],
          'reschedules': <Object?>[],
        });

      case '/missions/$kMissionId/review':
        myReviewSubmitted = true;
        return fixture('reviews/submit', 'created');

      case '/me/reviews':
        return (
          200,
          <String, Object?>{
            'success': true,
            'message': 'OK',
            'data': <Object?>[
              if (myReviewSubmitted) fixtureData('reviews/submit', 'created'),
            ],
            'meta': <String, Object?>{
              'page': 1,
              'limit': 20,
              'total': myReviewSubmitted ? 1 : 0,
            },
          },
        );

      case '/providers/$kProviderId/reviews':
        return (
          200,
          <String, Object?>{
            'success': true,
            'message': 'OK',
            'data': <Object?>[
              <String, Object?>{
                'id': kReviewAId,
                'rating': 4,
                'comment': 'Bon travail dans l’ensemble.',
                'authorFirstName': 'Awa',
                'createdAt': '2026-07-20T10:00:00.000Z',
              },
              <String, Object?>{
                'id': kReviewBId,
                'rating': 1,
                'comment': 'Propos déplacés dans le commentaire.',
                'authorFirstName': 'Mariam',
                'createdAt': '2026-07-21T11:00:00.000Z',
              },
            ],
            'meta': <String, Object?>{'page': 1, 'limit': 20, 'total': 2},
          },
        );

      // Dashboard prestataire (atterrissage du scénario 9.2).
      case '/providers/me':
        return envelope(_overview());
      case '/providers/me/missions':
        return (
          200,
          <String, Object?>{
            'success': true,
            'message': 'OK',
            'data': <Object?>[],
            'meta': <String, Object?>{'page': 1, 'limit': 20, 'total': 0},
          },
        );
      case '/me/notifications/unread-count':
        return envelope(<String, Object?>{'unread': 0});

      default:
        if (RegExp(r'^/reviews/[^/]+/report$').hasMatch(path)) {
          final String reviewId = path.split('/')[2];
          final int already = reports[reviewId] ?? 0;
          reports[reviewId] = already + 1;
          if (already > 0) {
            return fixture('reviews/report', 'alreadyReported');
          }
          return fixture('reviews/report', 'reported');
        }
        return (
          404,
          <String, Object?>{
            'success': false,
            'message': 'Route non simulée : ${options.method} $path',
          },
        );
    }
  }

  /// Le détail des captures, ramené à `completed` — avec MON avis une fois
  /// déposé (`reviews` ne sert qu'à ça).
  JsonMap _detail() {
    final JsonMap detail =
        (jsonDecode(jsonEncode(fixtureData('missions/detail', 'confirmed')))
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    detail['id'] = kMissionId;
    detail['status'] = 'completed';
    detail['reviews'] = <Object?>[
      if (myReviewSubmitted)
        <String, Object?>{'id': 'rev-1', 'authorId': kClientId, 'rating': 5},
    ];
    return detail;
  }

  JsonMap _overview() => <String, Object?>{
    'id': kProviderId,
    'publicName': 'Kofi Plomberie',
    'validationStatus': 'approved',
    'availabilityStatus': 'available',
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
}

/// Déroule les scénarios 9.1 à 9.4.
void runUs9Scenarios() {
  late ReviewsBackend backend;
  late RecordingAdapter adapter;
  late LocalDatabase database;
  late InMemoryTokenStore tokenStore;
  late ProviderContainer container;

  Future<void> mount({bool actAsProvider = false}) async {
    backend = ReviewsBackend(actAsProvider: actAsProvider);
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
    );
  }

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

  // --- 9.1 — Mission terminée, côté client --------------------------------------

  testWidgets('9.1 — « Laisser un avis » s’affiche avec le temps restant, '
      'calculé depuis l’historique et le réglage', (WidgetTester tester) async {
    await mount();
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    await scrollTo(tester, find.text('Laisser un avis'));
    expect(find.text('Laisser un avis'), findsOneWidget);
    // Terminée avant-hier + fenêtre de 14 jours (réglage) = 12 jours restants.
    expect(
      find.text('Il vous reste 12 jours pour noter cette mission.'),
      findsOneWidget,
    );
  });

  // --- 9.2 — Même mission, côté prestataire -------------------------------------

  testWidgets('9.2 — le prestataire de la même mission ne voit AUCUNE action '
      'de notation', (WidgetTester tester) async {
    await mount(actAsProvider: true);
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    expect(find.text('Laisser un avis'), findsNothing);
    expect(find.textContaining('pour noter cette mission'), findsNothing);
    // L'historique n'est même pas interrogé pour dater une fenêtre inutile.
    expect(backend.callsTo('POST', '/missions/$kMissionId/review'), 0);
  });

  // --- 9.3 — Déposer, rouvrir : action retirée, avis consultable ----------------

  testWidgets('9.3 — après le dépôt, l’action est retirée du détail et '
      'l’avis est consultable dans « Mes avis »', (WidgetTester tester) async {
    await mount();
    await start(tester, at: Routes.missionDetailFor(kMissionId));

    await scrollTo(tester, find.text('Laisser un avis'));
    await tester.tap(find.text('Laisser un avis'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('5 étoiles'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Commentaire (facultatif)'),
      'Travail impeccable, ponctuel et soigneux.',
    );
    await tester.tap(find.text('Publier mon avis'));
    await tester.pumpAndSettle();

    expect(backend.callsTo('POST', '/missions/$kMissionId/review'), 1);
    expect(find.text('Merci pour votre avis !'), findsOneWidget);
    await drainSnackBars(tester);
    await tester.pumpAndSettle();

    // Le détail rechargé : l'action a disparu, la mention renvoie aux avis.
    await scrollTo(tester, find.text('Vous avez déjà noté cette mission.'));
    expect(find.text('Laisser un avis'), findsNothing);

    await tester.tap(find.text('Voir mes avis'));
    await tester.pumpAndSettle();
    expect(
      find.text('Travail impeccable, ponctuel et soigneux.'),
      findsOneWidget,
    );
  });

  // --- 9.4 — Signaler deux fois le même avis ------------------------------------

  testWidgets('9.4 — le doublon de signalement devient la mention « Déjà '
      'signalé », côté session comme côté service', (
    WidgetTester tester,
  ) async {
    await mount();
    await start(tester, at: Routes.providerReviewsFor(kProviderId));

    expect(find.text('Bon travail dans l’ensemble.'), findsOneWidget);

    // Premier signalement de r-A : transmis, l'action devient la mention.
    await tester.tap(find.text('Signaler').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Motif (obligatoire)'),
      'Commentaire déplacé.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Signaler'));
    await tester.pumpAndSettle();

    expect(find.text('Signalement transmis à la modération'), findsOneWidget);
    expect(find.text('Déjà signalé'), findsOneWidget);
    await drainSnackBars(tester);

    // r-B a déjà été signalé (depuis un autre appareil) : le 409 du service
    // devient la MÊME mention — jamais une erreur brute.
    await tester.tap(find.text('Signaler'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Motif (obligatoire)'),
      'Propos injurieux.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Signaler'));
    await tester.pumpAndSettle();

    expect(find.text('Vous avez déjà signalé cet avis'), findsOneWidget);
    expect(find.text('Déjà signalé'), findsNWidgets(2));
    expect(find.text('Signaler'), findsNothing);
    await drainSnackBars(tester);
  });
}
