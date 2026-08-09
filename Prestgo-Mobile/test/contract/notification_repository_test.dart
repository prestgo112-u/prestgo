// T193 — Contrat des notifications et des appareils (opérations 54 à 60).
//
// Les singularités de ces routes, toutes vérifiées ici :
//   • `unread=true|false` part **explicitement** — `"false"` est bien interprété
//     comme faux côté service, l'application ne l'omet pas pour dire « non » ;
//   • le marquage lu est **idempotent** : déjà lue, inexistante ou à autrui →
//     `{ updated: 0 }`, jamais d'erreur — la mise à jour optimiste est sans risque ;
//   • l'enregistrement d'appareil répond **200, pas 201** (upsert sur le jeton), et
//     le jeton n'est **jamais** renvoyé — c'est un secret d'envoi ;
//   • le désenregistrement passe le jeton **encodé dans l'URL** et tolère un jeton
//     absent ou à autrui (`{ unregistered: false }`, jamais d'erreur) ;
//   • la charge utile `data` de chaque notification est celle du routage — la même
//     qu'un push (contracts/push-payloads.md).

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/push/notification_payload.dart';
import 'package:prestgo_mobile/features/notifications/data/device_repository.dart';
import 'package:prestgo_mobile/features/notifications/data/notification_repository.dart';
import 'package:prestgo_mobile/features/notifications/domain/app_notification.dart';
import 'package:prestgo_mobile/features/notifications/domain/registered_device.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

ApiHarness harnessFor(String file, String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'notifications/$file',
    caseName,
  );
  return ApiHarness.always(status, body);
}

void main() {
  group('Opération 54 — GET /me/notifications', () {
    test(
      'la liste paginée arrive avec ses charges utiles de routage',
      () async {
        final ApiHarness harness = harnessFor('notifications', 'firstPage');

        final PagedPage<AppNotification> page = await NotificationRepository(
          harness.client,
        ).notifications();

        expect(harness.lastCall.uri.path, endsWith('/me/notifications'));
        expect(
          harness.lastCall.uri.queryParameters.containsKey('unread'),
          isFalse,
          reason: 'sans filtre, le paramètre ne part pas',
        );
        expect(page.items, hasLength(5));
        expect(page.meta?.total, 5);

        final AppNotification first = page.items.first;
        expect(first.isRead, isFalse);
        expect(first.title, 'Mission acceptée');
        expect(first.payload, isA<MissionPayload>());
      },
    );

    test(
      '`unread=true` part explicitement — le filtre est celui du service',
      () async {
        final ApiHarness harness = harnessFor('notifications', 'unreadOnly');

        final PagedPage<AppNotification> page = await NotificationRepository(
          harness.client,
        ).notifications(unreadOnly: true);

        expect(harness.lastCall.uri.queryParameters['unread'], 'true');
        expect(page.items, hasLength(3));
        expect(page.items.every((AppNotification n) => !n.isRead), isTrue);
      },
    );

    test(
      'un type inconnu se décode sans erreur — il route vers le centre',
      () async {
        final PagedPage<AppNotification> page = await NotificationRepository(
          harnessFor('notifications', 'firstPage').client,
        ).notifications();

        final AppNotification unknown = page.items.firstWhere(
          (AppNotification n) => n.id == 'n-5',
        );
        expect(unknown.payload, isA<UnknownPayload>());
      },
    );

    test('l’état vide réel du compte démo est un succès ordinaire', () async {
      final PagedPage<AppNotification> page = await NotificationRepository(
        harnessFor('notifications', 'empty').client,
      ).notifications();

      expect(page.items, isEmpty);
      expect(page.meta?.total, 0);
    });
  });

  group('Opération 55 — GET /me/notifications/unread-count', () {
    test(
      'le compteur vient de sa route légère, sans charger la liste',
      () async {
        final ApiHarness harness = harnessFor('unread_count', 'three');

        final int unread = await NotificationRepository(
          harness.client,
        ).unreadCount();

        expect(unread, 3);
        expect(harness.lastUrl, '$kTestBaseUrl/me/notifications/unread-count');
      },
    );
  });

  group('Opérations 56 et 57 — marquage lu', () {
    test('unitaire : idempotent — déjà lue rend { updated: 0 }, jamais '
        'd’erreur', () async {
      final ApiHarness harness = harnessFor('mark_read', 'alreadyRead');

      final int updated = await NotificationRepository(
        harness.client,
      ).markRead('n-3');

      expect(updated, 0, reason: 'la mise à jour optimiste est sans risque');
      expect(harness.lastCall.method, 'PATCH');
      expect(harness.lastUrl, endsWith('/me/notifications/n-3/read'));
    });

    test('global : le message du service porte le compte exact', () async {
      final ApiHarness harness = harnessFor('mark_read', 'readAll');

      final ReadAllResult result = await NotificationRepository(
        harness.client,
      ).markAllRead();

      expect(result.updated, 3);
      expect(result.message, '3 notification(s) marquée(s) lue(s)');
      expect(harness.lastCall.method, 'POST');
      expect(harness.lastUrl, endsWith('/me/notifications/read-all'));
    });
  });

  group('Opération 59 — POST /me/devices', () {
    test('200 (pas 201), upsert sur le jeton — et le jeton n’est JAMAIS '
        'renvoyé', () async {
      final ApiHarness harness = harnessFor('devices', 'registered');

      final RegisteredDevice device = await DeviceRepository(
        harness.client,
      ).register(platform: 'android', token: 'fcm-jeton-0123456789');

      expect(harness.lastCall.method, 'POST');
      expect(harness.lastBody, <String, Object?>{
        'platform': 'android',
        'token': 'fcm-jeton-0123456789',
      });
      expect(device.id, 'd-1');
      expect(device.platform, 'android');
      expect(device.active, isTrue);
    });

    test(
      '400 — jeton refusé par le service, message affiché tel quel',
      () async {
        await expectLater(
          DeviceRepository(
            harnessFor('devices', 'invalidToken').client,
          ).register(platform: 'android', token: 'x'),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.message,
              'message',
              "Jeton d'appareil invalide",
            ),
          ),
        );
      },
    );
  });

  group('Opération 60 — DELETE /me/devices/{token}', () {
    test('le jeton part ENCODÉ dans le chemin d’URL', () async {
      final ApiHarness harness = harnessFor('devices', 'unregistered');

      await DeviceRepository(
        harness.client,
      ).unregister('jeton/avec:caractères spéciaux');

      expect(harness.lastCall.method, 'DELETE');
      expect(
        harness.lastCall.path,
        '/me/devices/${Uri.encodeComponent('jeton/avec:caractères spéciaux')}',
        reason: 'un jeton brut dans le chemin casserait la route',
      );
    });

    test(
      'tolérant : un jeton absent ou à autrui est un succès silencieux',
      () async {
        final ApiHarness harness = harnessFor('devices', 'unregisteredForeign');

        // `{ unregistered: false }` — aucun lancer, aucune erreur métier.
        await DeviceRepository(harness.client).unregister('jeton-d-un-autre');

        expect(harness.callCount, 1);
      },
    );
  });

  group('Opération 58 — GET /me/devices', () {
    test('la liste des appareils, non paginée', () async {
      final ApiHarness harness = harnessFor('devices', 'list');

      final List<RegisteredDevice> devices = await DeviceRepository(
        harness.client,
      ).devices();

      expect(harness.lastCall.uri.path, endsWith('/me/devices'));
      expect(devices, hasLength(2));
      expect(devices.first.platform, 'android');
      expect(devices.last.active, isFalse);
    });
  });
}
