// Absence exceptionnelle (data-model §4.5).
//
// Contrairement à l'agenda hebdomadaire, les bornes sont de vraies dates —
// échangées en ISO/UTC comme toutes les dates d'intervention. Les deux contrôles
// locaux (fin après début, pas de chevauchement avec une absence existante)
// reproduisent les 400 du service pour épargner un aller-retour.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

class Unavailability {
  const Unavailability({
    required this.id,
    required this.startAt,
    required this.endAt,
    this.reason,
  });

  factory Unavailability.fromJson(JsonMap json) => Unavailability(
    id: json['id'] as String? ?? '',
    startAt:
        MissionDates.fromApiOrNull(json['startAt'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    endAt:
        MissionDates.fromApiOrNull(json['endAt'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    reason: json['reason'] as String?,
  );

  final String id;
  final DateTime startAt;
  final DateTime endAt;

  /// Facultatif, ≤ 300 caractères.
  final String? reason;

  bool get isOrdered => endAt.isAfter(startAt);

  /// Deux absences se chevauchent si elles partagent un instant.
  bool overlaps(Unavailability other) =>
      startAt.isBefore(other.endAt) && other.startAt.isBefore(endAt);

  @override
  bool operator ==(Object other) => other is Unavailability && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Unavailability($id, $startAt → $endAt)';
}
