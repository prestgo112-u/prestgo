// Appareils de notification — opérations 58 à 60 (T196).
//
// Implémente le contrat `DeviceRegistrar` du socle : `core/push/` orchestre le
// cycle de vie du jeton sans connaître ce dépôt (le socle n'importe aucune
// fonctionnalité) — l'assemblage se fait dans `lib/app/push_driver.dart`.
//
// Deux pièges du service, neutralisés ici :
//   • l'enregistrement répond **200, pas 201** (upsert sur le jeton) et ne
//     renvoie **jamais** le jeton — c'est un secret d'envoi ;
//   • au désenregistrement, le jeton passe **dans le chemin d'URL** : il part
//     encodé, et `{ unregistered: false }` (jeton absent ou à autrui) est un
//     succès silencieux — jamais d'erreur métier.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/push/push_service.dart';
import 'package:prestgo_mobile/features/notifications/domain/registered_device.dart';

class DeviceRepository implements DeviceRegistrar {
  const DeviceRepository(this._client);

  final ApiClient _client;

  /// `GET /me/devices` — opération 58, non paginée. Réglages « appareils ».
  Future<List<RegisteredDevice>> devices() async {
    final ApiEnvelope<List<RegisteredDevice>> envelope = await _client
        .get<List<RegisteredDevice>>(
          '/me/devices',
          parse: parseList<RegisteredDevice>(RegisteredDevice.fromJson),
        );
    return envelope.data ?? const <RegisteredDevice>[];
  }

  /// `POST /me/devices` — opération 59, idempotente (30/jour).
  @override
  Future<RegisteredDevice> register({
    required String platform,
    required String token,
  }) async {
    final ApiEnvelope<RegisteredDevice> envelope = await _client
        .post<RegisteredDevice>(
          '/me/devices',
          body: <String, Object?>{'platform': platform, 'token': token},
          parse: parseObject<RegisteredDevice>(RegisteredDevice.fromJson),
        );
    return envelope.requireData;
  }

  /// `DELETE /me/devices/{token}` — opération 60, tolérante.
  @override
  Future<void> unregister(String token) async {
    // `{ unregistered: true|false }` : les deux sont des succès — un jeton
    // absent ou réaffecté à un autre compte n'a plus rien à désenregistrer.
    await _client.delete<void>(
      '/me/devices/${Uri.encodeComponent(token)}',
      parse: parseNothing(),
    );
  }
}

final Provider<DeviceRepository> deviceRepositoryProvider =
    Provider<DeviceRepository>(
      (Ref ref) => DeviceRepository(ref.watch(apiClientProvider)),
    );
