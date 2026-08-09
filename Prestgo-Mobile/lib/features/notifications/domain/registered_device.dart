// Appareil enregistré pour les notifications poussées (opérations 58 et 59).
//
// ⚠️ Le jeton d'appareil n'apparaît **jamais** ici : le service ne le renvoie
// pas — c'est un secret d'envoi. Il ne vit que dans le stockage sécurisé.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

class RegisteredDevice {
  const RegisteredDevice({
    required this.id,
    required this.platform,
    required this.active,
    this.lastSeenAt,
  });

  factory RegisteredDevice.fromJson(JsonMap json) => RegisteredDevice(
    id: json['id'] as String? ?? '',
    platform: json['platform'] as String? ?? '',
    active: json['active'] as bool? ?? false,
    lastSeenAt: MissionDates.fromApiOrNull(json['lastSeenAt'] as String?),
  );

  final String id;

  /// `android`, `ios` ou `web`.
  final String platform;

  /// Faux pour un jeton refusé par le fournisseur d'envoi ou inactif.
  final bool active;

  final DateTime? lastSeenAt;

  @override
  String toString() => 'RegisteredDevice($id, $platform, actif: $active)';
}
