// T204 — Centre de notifications : filtre, marquage optimiste, routage, et
// l'absence délibérée de suppression.
//
// Ce que ces tests protègent :
//   • **le filtre est celui du service** — `unread=true` part explicitement,
//     jamais un filtrage local ;
//   • **le marquage unitaire est optimiste** — l'écran change avant la réponse,
//     l'idempotence du service rend l'écart sans risque ;
//   • **le tap route par la charge utile** — le même chemin qu'un push (FR-083) ;
//   • **aucune affordance de suppression** — la route n'existe pas (FR-081) ;
//   • **la pastille écoute la réception** — le signal du socle la rafraîchit
//     (T198, FR-082).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestgo_mobile/app/push_driver.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/push/notification_router.dart';
import 'package:prestgo_mobile/core/push/push_entry_points.dart';
import 'package:prestgo_mobile/core/push/push_service.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/notifications/presentation/badge_providers.dart';
import 'package:prestgo_mobile/features/notifications/presentation/notifications_screen.dart';

import '../support/fixtures.dart';
import '../support/recording_adapter.dart';
import '../support/screen_harness.dart';

/// Service simulé du centre de notifications.
AdapterScenario notificationsBackend() => (RequestOptions options, int index) {
  final String path = options.path;
  if (path == '/me/notifications') {
    return options.uri.queryParameters['unread'] == 'true'
        ? fixture('notifications/notifications', 'unreadOnly')
        : fixture('notifications/notifications', 'firstPage');
  }
  if (path == '/me/notifications/unread-count') {
    return fixture('notifications/unread_count', 'three');
  }
  if (path == '/me/notifications/read-all') {
    return fixture('notifications/mark_read', 'readAll');
  }
  if (path.endsWith('/read')) {
    return fixture('notifications/mark_read', 'one');
  }
  return (
    404,
    <String, Object?>{'success': false, 'message': 'Route non simulée : $path'},
  );
};

void main() {
  setUpAll(() => initializeDateFormatting(AppFormats.locale));

  Future<(ScreenHarness, List<String>)> pumpCenter(WidgetTester tester) async {
    final ScreenHarness harness = ScreenHarness(notificationsBackend());
    final List<String> opened = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          ...harness.overrides,
          // Routeur de notification enregistreur : le test vérifie la
          // destination sans monter go_router.
          notificationRouterProvider.overrideWithValue(
            NotificationRouter(
              resolvePath: destinationPathFor,
              navigate: opened.add,
              isReady: () => true,
            ),
          ),
        ],
        child: const MaterialApp(home: NotificationsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (harness, opened);
  }

  testWidgets(
    'la liste arrive entière, sans aucune affordance de suppression',
    (WidgetTester tester) async {
      final (ScreenHarness harness, _) = await pumpCenter(tester);

      expect(find.text('Mission acceptée'), findsOneWidget);
      expect(find.text('Nouvel avis'), findsOneWidget);
      // Un type inconnu s'affiche comme les autres — il route vers le centre.
      expect(find.text("Offre d'été"), findsOneWidget);

      expect(find.byType(Dismissible), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      await harness.dispose(tester);
    },
  );

  testWidgets('le filtre « non lues » interroge le service — jamais un tri '
      'local', (WidgetTester tester) async {
    final (ScreenHarness harness, _) = await pumpCenter(tester);

    await tester.tap(find.text('Non lues seulement'));
    await tester.pumpAndSettle();

    final RequestOptions filtered = harness.adapter.calls.lastWhere(
      (RequestOptions o) => o.path == '/me/notifications',
    );
    expect(filtered.uri.queryParameters['unread'], 'true');
    // La demande de report (lue) a disparu, les non-lues restent.
    expect(find.text('Demande de report'), findsNothing);
    expect(find.text('Mission acceptée'), findsOneWidget);

    await harness.dispose(tester);
  });

  testWidgets('le tap marque lu de façon optimiste ET route par la charge '
      'utile', (WidgetTester tester) async {
    final (ScreenHarness harness, List<String> opened) = await pumpCenter(
      tester,
    );

    await tester.tap(find.text('Mission acceptée'));
    await tester.pumpAndSettle();

    // Optimiste : la pastille de non-lu de la ligne a disparu sans relire la
    // liste (un seul GET au journal).
    expect(
      harness.adapter.countFor('/me/notifications'),
      1,
      reason: 'le marquage optimiste ne recharge pas la liste',
    );
    expect(harness.adapter.countFor('/me/notifications/n-1/read'), 1);

    // Et la destination est celle de la charge utile — comme un push (FR-083).
    expect(opened, <String>[
      Routes.missionDetailFor('b86332d9-14a0-4ec8-b5d0-d0158ae1824d'),
    ]);

    await harness.dispose(tester);
  });

  testWidgets('« Tout marquer lu » affiche le message du service tel quel', (
    WidgetTester tester,
  ) async {
    final (ScreenHarness harness, _) = await pumpCenter(tester);

    await tester.tap(find.byTooltip('Tout marquer lu'));
    await tester.pumpAndSettle();

    expect(harness.adapter.countFor('/me/notifications/read-all'), 1);
    expect(find.text('3 notification(s) marquée(s) lue(s)'), findsOneWidget);

    // La minuterie du snack doit s'éteindre avant la fin du test.
    await tester.pump(const Duration(seconds: 5));
    await harness.dispose(tester);
  });

  testWidgets('la pastille se rafraîchit à la réception d’une notification '
      '(T198)', (WidgetTester tester) async {
    final ScreenHarness harness = ScreenHarness(notificationsBackend());
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: harness.overrides,
        child: Consumer(
          builder: (BuildContext context, WidgetRef ref, Widget? child) {
            container = ProviderScope.containerOf(context);
            final int unread =
                ref.watch(notificationsUnreadCountProvider).value ?? 0;
            return Directionality(
              textDirection: TextDirection.ltr,
              child: Text('non lus : $unread'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('non lus : 3'), findsOneWidget);
    final int callsBefore = harness.adapter.countFor(
      '/me/notifications/unread-count',
    );

    // La réception d'un push au premier plan lève le signal du socle.
    container
        .read(receivedPushSignalProvider.notifier)
        .publish(const PushMessage(data: <String, Object?>{'type': 'mission'}));
    await tester.pumpAndSettle();

    expect(
      harness.adapter.countFor('/me/notifications/unread-count'),
      callsBefore + 1,
      reason: 'réception → relecture du compteur (FR-082)',
    );

    await harness.dispose(tester);
  });
}
