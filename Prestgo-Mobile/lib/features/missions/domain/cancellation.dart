// Annulation d'une mission (T124, data-model §5.2, FR-044, FR-045).
//
// Deux objets distincts : [Cancellation] est l'annulation **enregistrée**, portée
// par le détail de mission ; [CancellationResult] est la réponse immédiate de
// `POST /missions/{id}/cancel`, dont le `message` serveur est affiché tel quel.
//
// `late` est **calculé par le service, jamais bloquant** : une annulation à moins
// du préavis en vigueur est acceptée et marquée tardive. L'application avertit
// **avant** l'appel — c'est le rôle de [isLateCancellation], alimenté par le seuil
// de `GET /settings/public` — mais le verdict affiché après coup est celui du
// service.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';

/// Annulation enregistrée, telle que le détail de mission la porte.
class Cancellation {
  const Cancellation({
    required this.reason,
    required this.late,
    this.details,
    this.createdAt,
  });

  factory Cancellation.fromJson(JsonMap json) => Cancellation(
    reason: json['reason'] as String? ?? '',
    details: json['details'] as String?,
    late: json['late'] as bool? ?? false,
    createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
  );

  final String reason;
  final String? details;

  /// Annulation tardive — signalée explicitement à l'écran (FR-045).
  final bool late;

  final DateTime? createdAt;

  @override
  String toString() => 'Cancellation($reason, late: $late)';
}

/// Réponse de `POST /missions/{id}/cancel`.
class CancellationResult {
  const CancellationResult({
    required this.missionId,
    required this.previousStatus,
    required this.status,
    required this.late,
    required this.message,
  });

  factory CancellationResult.fromJson(
    JsonMap json, {
    required String message,
  }) => CancellationResult(
    missionId: json['missionId'] as String? ?? '',
    previousStatus: MissionStatus.parse(json['previousStatus'] as String?),
    status: MissionStatus.parse(json['status'] as String?),
    late: json['late'] as bool? ?? false,
    message: message,
  );

  final String missionId;
  final MissionStatus previousStatus;
  final MissionStatus status;

  /// Verdict du service — celui qui fait foi, quel que soit l'avertissement local.
  final bool late;

  /// Message serveur, affiché **tel quel** (« Mission annulée. L'annulation est
  /// enregistrée comme tardive. »).
  final String message;

  @override
  String toString() => 'CancellationResult($missionId, late: $late)';
}

/// Vrai si annuler **maintenant** serait enregistré comme tardif.
///
/// Sert à l'avertissement préalable (scénario 3.2) : [notice] vient de
/// `PublicSettings.cancellationNotice`, jamais d'une constante (porte G3). Le
/// message du service, après l'appel, reste l'autorité finale.
bool isLateCancellation({
  required DateTime? scheduledAt,
  required DateTime now,
  required Duration notice,
}) {
  if (scheduledAt == null) {
    return false;
  }
  return now.isAfter(scheduledAt.subtract(notice));
}
