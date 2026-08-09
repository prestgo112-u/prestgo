// Avis déposé par le client (data-model §6).
//
// La modération commande le rendu, pas l'existence : un avis `reported`
// **reste visible** ; `hidden` et `rejected` affichent une mention de retrait
// à la place du contenu. Ni modification ni suppression ne sont possibles —
// l'écran « Mes avis » n'offre aucune action d'édition.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

enum ReviewStatus {
  published,
  reported,
  hidden,
  rejected;

  static ReviewStatus parse(String? raw) => switch (raw) {
    'reported' => ReviewStatus.reported,
    'hidden' => ReviewStatus.hidden,
    'rejected' => ReviewStatus.rejected,
    // Un statut inconnu s'affiche : masquer un avis publié serait pire que
    // montrer un avis douteux — la modération a ses propres statuts pour ça.
    _ => ReviewStatus.published,
  };
}

/// Mission porteuse, réduite à ce que la liste « Mes avis » affiche.
class ReviewMissionRef {
  const ReviewMissionRef({
    required this.id,
    this.scheduledAt,
    this.providerName,
  });

  factory ReviewMissionRef.fromJson(JsonMap json) => ReviewMissionRef(
    id: json['id'] as String? ?? '',
    scheduledAt: MissionDates.fromApiOrNull(json['scheduledAt'] as String?),
    providerName: switch (json['provider']) {
      final Map<Object?, Object?> provider => provider['publicName'] as String?,
      _ => null,
    },
  );

  final String id;
  final DateTime? scheduledAt;
  final String? providerName;
}

class Review {
  const Review({
    required this.id,
    required this.rating,
    required this.status,
    this.comment,
    this.createdAt,
    this.mission,
  });

  factory Review.fromJson(JsonMap json) => Review(
    id: json['id'] as String? ?? '',
    rating: switch (json['rating']) {
      final num v => v.toInt(),
      _ => 0,
    },
    comment: json['comment'] as String?,
    status: ReviewStatus.parse(json['status'] as String?),
    createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
    mission: switch (json['mission']) {
      final Map<Object?, Object?> mission => ReviewMissionRef.fromJson(
        mission.cast<String, Object?>(),
      ),
      _ => null,
    },
  );

  final String id;

  /// Entier de 1 à 5.
  final int rating;

  /// ≤ 1000 caractères, facultatif.
  final String? comment;

  final ReviewStatus status;
  final DateTime? createdAt;
  final ReviewMissionRef? mission;

  /// Vrai si le contenu est remplacé par une mention de retrait.
  bool get isWithdrawn =>
      status == ReviewStatus.hidden || status == ReviewStatus.rejected;

  @override
  bool operator ==(Object other) => other is Review && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Review($id, $rating★, ${status.name})';
}
