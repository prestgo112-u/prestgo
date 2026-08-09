// Notification interne (T195, data-model §8).
//
// `data` est la charge utile de routage — la même qu'un push : le tap sur une
// ligne du centre passe par la même fonction d'ouverture que le tap sur une
// notification poussée (FR-083).
//
// Règles du service : marquage lu idempotent (mise à jour optimiste sans
// risque), **aucune suppression**, l'auteur d'une action n'est jamais notifié de
// sa propre action.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/push/notification_payload.dart';

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.createdAt,
    this.readAt,
  });

  factory AppNotification.fromJson(JsonMap json) => AppNotification(
    id: json['id'] as String? ?? '',
    type: json['type'] as String? ?? '',
    title: json['title'] as String? ?? '',
    body: json['body'] as String? ?? '',
    data: json['data'] is Map<Object?, Object?>
        ? (json['data']! as Map<Object?, Object?>).cast<String, Object?>()
        : const <String, Object?>{},
    readAt: MissionDates.fromApiOrNull(json['readAt'] as String?),
    createdAt:
        MissionDates.fromApiOrNull(json['createdAt'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final String id;

  /// Code d'évènement du service (`mission.accepted`, `chat.message`…) — jamais
  /// interprété pour router : c'est le rôle de [payload].
  final String type;

  final String title;
  final String body;

  /// Charge utile de routage, telle que reçue.
  final JsonMap data;

  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  /// Destination typée — tolérante, un type inconnu route vers le centre.
  NotificationPayload get payload => NotificationPayload.parse(data);

  /// Copie marquée lue — la mise à jour optimiste de l'écran (idempotence du
  /// service oblige, elle est sans risque).
  AppNotification asRead(DateTime at) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    data: data,
    readAt: readAt ?? at,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) => other is AppNotification && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'AppNotification($id, $type, lu: $isRead)';
}
