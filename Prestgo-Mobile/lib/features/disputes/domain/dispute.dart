// Litige (T134, data-model §11, FR-100).
//
// La forme exacte de `data` n'est **pas contractualisée** côté service (aucun DTO
// Swagger sur ces routes) : le modèle est volontairement minimaliste et tolérant —
// chaque champ absent a un défaut sûr — et sera ajusté contre le service réel.
// Les commentaires internes des agents ne sont jamais renvoyés.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

/// Message versé au dossier du litige.
class DisputeMessage {
  const DisputeMessage({required this.message, this.senderId, this.createdAt});

  factory DisputeMessage.fromJson(JsonMap json) => DisputeMessage(
    message: json['message'] as String? ?? '',
    senderId: json['senderId'] as String?,
    createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
  );

  final String message;

  /// `null` : message du service ou d'un agent.
  final String? senderId;

  final DateTime? createdAt;
}

class Dispute {
  const Dispute({
    required this.id,
    required this.missionId,
    required this.reason,
    required this.status,
    required this.messages,
    this.createdAt,
  });

  factory Dispute.fromJson(JsonMap json) => Dispute(
    id: json['id'] as String? ?? '',
    missionId: json['missionId'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
    status: json['status'] as String? ?? '',
    messages: json['messages'] is List
        ? (json['messages'] as List<Object?>)
              .whereType<Map<Object?, Object?>>()
              .map(
                (Map<Object?, Object?> e) =>
                    DisputeMessage.fromJson(e.cast<String, Object?>()),
              )
              .toList(growable: false)
        : const <DisputeMessage>[],
    createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
  );

  final String id;
  final String missionId;
  final String reason;

  /// Affiché tel quel — la nomenclature des états n'est pas contractualisée.
  final String status;

  final List<DisputeMessage> messages;
  final DateTime? createdAt;

  @override
  String toString() => 'Dispute($id, $status)';
}
