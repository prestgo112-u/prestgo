// Demande de report (T124, data-model §5.5, FR-047, FR-048).
//
// Règles portées par ce modèle plutôt que redécouvertes par chaque écran :
//   • **une seule demande en attente par mission** — l'écran grise l'action quand
//     le détail en porte une ;
//   • les actions Accepter/Refuser sont **masquées** sur ses propres demandes
//     ([canRespond]) : le 403 « votre propre demande » ne doit jamais être atteint ;
//   • le créneau est **revalidé au moment de l'acceptation** — l'échec « n'est plus
//     disponible » ouvre une contre-proposition, il ne clôt pas le parcours.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

/// Statut d'une demande de report.
enum RescheduleStatus {
  requested('requested', 'En attente de réponse'),
  accepted('accepted', 'Acceptée'),
  rejected('rejected', 'Refusée'),
  applied('applied', 'Appliquée'),
  unknown('', '');

  const RescheduleStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static RescheduleStatus parse(String? raw) {
    for (final RescheduleStatus status in RescheduleStatus.values) {
      if (status != RescheduleStatus.unknown && status.apiValue == raw) {
        return status;
      }
    }
    return RescheduleStatus.unknown;
  }
}

class RescheduleRequest {
  const RescheduleRequest({
    required this.id,
    required this.status,
    required this.createdBy,
    this.oldScheduledAt,
    this.newScheduledAt,
    this.reason,
    this.decidedBy,
    this.decidedAt,
    this.decisionReason,
    this.createdAt,
  });

  factory RescheduleRequest.fromJson(JsonMap json) => RescheduleRequest(
    id: json['id'] as String? ?? '',
    status: RescheduleStatus.parse(json['status'] as String?),
    createdBy: json['createdBy'] as String? ?? '',
    oldScheduledAt: MissionDates.fromApiOrNull(
      json['oldScheduledAt'] as String?,
    ),
    newScheduledAt: MissionDates.fromApiOrNull(
      json['newScheduledAt'] as String?,
    ),
    reason: json['reason'] as String?,
    decidedBy: json['decidedBy'] as String?,
    decidedAt: MissionDates.fromApiOrNull(json['decidedAt'] as String?),
    decisionReason: json['decisionReason'] as String?,
    createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
  );

  final String id;
  final RescheduleStatus status;

  /// Identifiant de l'auteur — comparé à `Me.id` pour masquer Accepter/Refuser.
  final String createdBy;

  final DateTime? oldScheduledAt;
  final DateTime? newScheduledAt;
  final String? reason;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String? decisionReason;
  final DateTime? createdAt;

  /// En attente de réponse.
  bool get isPending => status == RescheduleStatus.requested;

  /// Vrai si [userId] est l'auteur de la demande.
  bool isMine(String userId) => userId.isNotEmpty && createdBy == userId;

  /// Vrai si [userId] peut répondre : demande en attente **et** pas la sienne.
  ///
  /// C'est le seul prédicat que les écrans consultent pour afficher les boutons
  /// Accepter/Refuser (scénario 3.4).
  bool canRespond(String userId) => isPending && !isMine(userId);

  @override
  bool operator ==(Object other) =>
      other is RescheduleRequest && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'RescheduleRequest($id, ${status.apiValue})';
}

/// Réponse de `accept` / `reject` — la mission est déplacée sur `accepted`.
class RescheduleDecision {
  const RescheduleDecision({
    required this.id,
    required this.status,
    required this.message,
    this.scheduledAt,
  });

  factory RescheduleDecision.fromJson(
    JsonMap json, {
    required String message,
  }) => RescheduleDecision(
    id: json['id'] as String? ?? '',
    status: RescheduleStatus.parse(json['status'] as String?),
    scheduledAt: MissionDates.fromApiOrNull(json['scheduledAt'] as String?),
    message: message,
  );

  final String id;
  final RescheduleStatus status;

  /// Nouvelle date de la mission — renseignée sur une acceptation.
  final DateTime? scheduledAt;

  /// Message serveur, affiché tel quel.
  final String message;

  @override
  String toString() => 'RescheduleDecision($id, ${status.apiValue})';
}
