// T194 — Routage par charge utile : 4 types + type inconnu → centre (FR-083).
//
// La même fonction sert le tap sur une notification interne ET sur un push : les
// deux transportent la même charge utile (contracts/push-payloads.md §1). Deux
// invariants supplémentaires :
//   • **tolérance** — un type inconnu, absent, ou une charge mutilée retombe sur le
//     centre de notifications, jamais sur une erreur ;
//   • **destination différée** — sans session prête (application tuée ouverte par
//     une notification), la destination attend l'aiguillage et part UNE seule fois.
//
// Un push arrive avec des valeurs **chaînes** (transport FCM) : l'analyse ne
// présume jamais des types JSON.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/app/push_driver.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/push/notification_payload.dart';
import 'package:prestgo_mobile/core/push/notification_router.dart';

const String kMissionId = 'b86332d9-14a0-4ec8-b5d0-d0158ae1824d';
const String kThreadId = 'e6499753-89c6-4a9f-bdc9-b3ff4508be47';

String routeFor(Map<String, Object?> data) =>
    destinationPathFor(NotificationPayload.parse(data));

void main() {
  group('Les quatre types du contrat', () {
    test('mission → détail de la mission', () {
      expect(
        routeFor(<String, Object?>{'type': 'mission', 'missionId': kMissionId}),
        Routes.missionDetailFor(kMissionId),
      );
    });

    test('chat → conversation, mission porteuse jointe', () {
      expect(
        routeFor(<String, Object?>{
          'type': 'chat',
          'missionId': kMissionId,
          'threadId': kThreadId,
        }),
        Routes.conversationFor(kThreadId, missionId: kMissionId),
      );
    });

    test('reschedule → détail de la mission, onglet report', () {
      expect(
        routeFor(<String, Object?>{
          'type': 'reschedule',
          'missionId': kMissionId,
          'rescheduleId': 'r-77',
        }),
        '${Routes.missionDetailFor(kMissionId)}?tab=reschedule',
      );
    });

    test('review → détail de la mission, onglet avis', () {
      expect(
        routeFor(<String, Object?>{
          'type': 'review',
          'missionId': kMissionId,
          'reviewId': 'rev-12',
        }),
        '${Routes.missionDetailFor(kMissionId)}?tab=review',
      );
    });
  });

  group('Tolérance — tout ce qui n’est pas sûr va au centre', () {
    test('type inconnu → centre de notifications, aucun échec', () {
      expect(
        routeFor(<String, Object?>{'type': 'promo'}),
        Routes.notifications,
      );
    });

    test('type absent → centre de notifications', () {
      expect(
        routeFor(<String, Object?>{'missionId': kMissionId}),
        Routes.notifications,
      );
    });

    test('charge mutilée — type connu sans identifiant → centre', () {
      expect(
        routeFor(<String, Object?>{'type': 'mission'}),
        Routes.notifications,
      );
      expect(routeFor(<String, Object?>{'type': 'chat'}), Routes.notifications);
      expect(routeFor(const <String, Object?>{}), Routes.notifications);
    });

    test('charge nulle → centre', () {
      expect(
        destinationPathFor(NotificationPayload.parse(null)),
        Routes.notifications,
      );
    });
  });

  group('Destination différée — session absente', () {
    test('sans session, la destination attend ; elle part au premier '
        'aiguillage, une seule fois', () {
      final List<String> navigations = <String>[];
      bool ready = false;
      final NotificationRouter router = NotificationRouter(
        resolvePath: destinationPathFor,
        navigate: navigations.add,
        isReady: () => ready,
      );

      router.open(<String, Object?>{
        'type': 'mission',
        'missionId': kMissionId,
      });
      expect(navigations, isEmpty, reason: 'le routeur n’est pas encore prêt');

      ready = true;
      router.flushPending();
      expect(navigations, <String>[Routes.missionDetailFor(kMissionId)]);

      // Un second aiguillage ne rejoue rien : la destination est consommée.
      router.flushPending();
      expect(navigations, hasLength(1));
    });

    test('session déjà prête : navigation immédiate', () {
      final List<String> navigations = <String>[];
      final NotificationRouter router = NotificationRouter(
        resolvePath: destinationPathFor,
        navigate: navigations.add,
        isReady: () => true,
      );

      router.open(<String, Object?>{'type': 'chat', 'threadId': kThreadId});

      expect(navigations, <String>[Routes.conversationFor(kThreadId)]);
    });

    test('une nouvelle notification remplace la destination en attente', () {
      final List<String> navigations = <String>[];
      bool ready = false;
      final NotificationRouter router = NotificationRouter(
        resolvePath: destinationPathFor,
        navigate: navigations.add,
        isReady: () => ready,
      );

      router.open(<String, Object?>{'type': 'mission', 'missionId': 'm-1'});
      router.open(<String, Object?>{'type': 'mission', 'missionId': 'm-2'});

      ready = true;
      router.flushPending();
      expect(navigations, <String>[
        Routes.missionDetailFor('m-2'),
      ], reason: 'seule la dernière intention de l’utilisateur compte');
    });
  });

  group('Un push transporte des chaînes', () {
    test('les valeurs FCM arrivent en Map<String, String> — même résultat', () {
      expect(
        routeFor(<String, Object?>{
          'type': 'chat',
          'missionId': kMissionId,
          'threadId': kThreadId,
        }),
        routeFor(<String, String>{
          'type': 'chat',
          'missionId': kMissionId,
          'threadId': kThreadId,
        }),
      );
    });
  });
}
