// Historique d'une mission (T124, data-model §5.6, FR-039, FR-070).
//
// `GET /missions/{id}/history` renvoie deux listes : les changements de statut —
// la frise — et les reports passés. L'entrée `newStatus == completed` sert aussi à
// dater la fenêtre de dépôt d'avis (US9) : c'est [completedAt].

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';

/// Un changement de statut — une étape de la frise.
class MissionHistoryEntry {
  const MissionHistoryEntry({
    required this.id,
    required this.newStatus,
    required this.rawNewStatus,
    this.oldStatus,
    this.reason,
    this.createdAt,
  });

  factory MissionHistoryEntry.fromJson(JsonMap json) {
    final String rawNewStatus = json['newStatus'] as String? ?? '';
    final String? rawOldStatus = json['oldStatus'] as String?;
    return MissionHistoryEntry(
      id: json['id'] as String? ?? '',
      newStatus: MissionStatus.parse(rawNewStatus),
      rawNewStatus: rawNewStatus,
      oldStatus: rawOldStatus == null
          ? null
          : MissionStatus.parse(rawOldStatus),
      reason: json['reason'] as String?,
      createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
    );
  }

  final String id;
  final MissionStatus newStatus;
  final String rawNewStatus;

  /// `null` sur la première entrée — la création de la réservation.
  final MissionStatus? oldStatus;

  final String? reason;
  final DateTime? createdAt;

  String get label =>
      newStatus == MissionStatus.unknown ? rawNewStatus : newStatus.label;
}

/// Trace d'un report dans l'historique — plus légère qu'une demande complète.
class RescheduleTrace {
  const RescheduleTrace({
    required this.id,
    this.oldScheduledAt,
    this.newScheduledAt,
    this.reason,
    this.createdAt,
  });

  factory RescheduleTrace.fromJson(JsonMap json) => RescheduleTrace(
    id: json['id'] as String? ?? '',
    oldScheduledAt: MissionDates.fromApiOrNull(
      json['oldScheduledAt'] as String?,
    ),
    newScheduledAt: MissionDates.fromApiOrNull(
      json['newScheduledAt'] as String?,
    ),
    reason: json['reason'] as String?,
    createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
  );

  final String id;
  final DateTime? oldScheduledAt;
  final DateTime? newScheduledAt;
  final String? reason;
  final DateTime? createdAt;
}

class MissionHistory {
  const MissionHistory({
    required this.statusHistory,
    required this.reschedules,
  });

  factory MissionHistory.fromJson(JsonMap json) => MissionHistory(
    statusHistory: _list(json['statusHistory'], MissionHistoryEntry.fromJson),
    reschedules: _list(json['reschedules'], RescheduleTrace.fromJson),
  );

  /// Changements de statut, dans l'ordre du service.
  final List<MissionHistoryEntry> statusHistory;

  /// Reports passés — la frise les intercale par date.
  final List<RescheduleTrace> reschedules;

  /// Date d'entrée en `completed`, ou `null` si la mission n'y est jamais passée.
  ///
  /// C'est elle qui ouvre la fenêtre de dépôt d'avis (`reviewsWindowDays`).
  DateTime? get completedAt => statusHistory
      .where((MissionHistoryEntry e) => e.newStatus == MissionStatus.completed)
      .map((MissionHistoryEntry e) => e.createdAt)
      .whereType<DateTime>()
      .lastOrNull;

  bool get isEmpty => statusHistory.isEmpty && reschedules.isEmpty;
}

List<T> _list<T>(Object? value, T Function(JsonMap json) fromJson) =>
    value is List
    ? value
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> e) => fromJson(e.cast<String, Object?>()))
          .toList(growable: false)
    : const <Never>[];
