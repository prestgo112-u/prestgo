// Détail de mission (T124, data-model §5.2).
//
// Ce que ce modèle garantit aux écrans :
//   • **aucune coordonnée personnelle** de l'autre partie — le service n'en envoie
//     pas, le modèle n'en invente pas : la mise en relation passe par la messagerie ;
//   • `reschedules` ne contient que les demandes **en attente** — l'historique
//     complet vit sur `GET /missions/{id}/reschedules` ;
//   • `reviews` est réduit à `{ id, authorId, rating }` et ne sert qu'à savoir si
//     **moi** j'ai déjà noté ([hasReviewBy]) ;
//   • `quotedAmount` nul s'affiche « — », jamais « 0 XOF ».

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/features/missions/domain/cancellation.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';
import 'package:prestgo_mobile/features/missions/domain/reschedule_request.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';

/// Le client de la mission — identité minimale, sans contact.
class MissionParty {
  const MissionParty({required this.id, this.firstName, this.lastName});

  factory MissionParty.fromJson(JsonMap json) => MissionParty(
    id: json['id'] as String? ?? '',
    firstName: json['firstName'] as String?,
    lastName: json['lastName'] as String?,
  );

  final String id;
  final String? firstName;
  final String? lastName;

  String get displayName =>
      <String?>[firstName, lastName].whereType<String>().join(' ').trim();
}

/// Le prestataire de la mission — sa vitrine, sans contact.
class MissionProviderSummary {
  const MissionProviderSummary({
    required this.id,
    required this.publicName,
    required this.score,
    required this.reviewsCount,
    this.avatarFileId,
  });

  factory MissionProviderSummary.fromJson(JsonMap json) =>
      MissionProviderSummary(
        id: json['id'] as String? ?? '',
        publicName: json['publicName'] as String? ?? '',
        score: _asDouble(json['score']) ?? 0,
        reviewsCount: _asInt(json['reviewsCount']) ?? 0,
        avatarFileId: json['avatarFileId'] as String?,
      );

  final String id;
  final String publicName;
  final double score;
  final int reviewsCount;
  final String? avatarFileId;

  /// « Nouveau » plutôt que « 0 étoile » (même règle qu'en recherche).
  bool get isNew => reviewsCount == 0;
}

/// La formule réservée, avec de quoi rappeler la prestation d'origine.
class MissionPack {
  const MissionPack({
    required this.id,
    required this.title,
    required this.price,
    required this.durationMinutes,
    this.serviceTitle,
    this.serviceTypeName,
  });

  factory MissionPack.fromJson(JsonMap json) {
    final Object? service = json['providerService'];
    final JsonMap? serviceMap = service is Map<Object?, Object?>
        ? service.cast<String, Object?>()
        : null;
    final Object? serviceType = serviceMap?['serviceType'];
    return MissionPack(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      price: _asInt(json['price']) ?? 0,
      durationMinutes: _asInt(json['durationMinutes']) ?? 0,
      serviceTitle: serviceMap?['title'] as String?,
      serviceTypeName: serviceType is Map<Object?, Object?>
          ? serviceType['name'] as String?
          : null,
    );
  }

  final String id;
  final String title;
  final int price;
  final int durationMinutes;
  final String? serviceTitle;
  final String? serviceTypeName;
}

/// Option retenue à la réservation.
class MissionOption {
  const MissionOption({
    required this.id,
    required this.title,
    required this.price,
    required this.durationMinutes,
  });

  factory MissionOption.fromJson(JsonMap json) => MissionOption(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    price: _asInt(json['price']) ?? 0,
    durationMinutes: _asInt(json['durationMinutes']) ?? 0,
  );

  final String id;
  final String title;
  final int price;
  final int durationMinutes;
}

/// Fil de discussion de la mission — il existe **dès la création**.
class MissionThreadRef {
  const MissionThreadRef({required this.id, required this.status});

  factory MissionThreadRef.fromJson(JsonMap json) => MissionThreadRef(
    id: json['id'] as String? ?? '',
    status: json['status'] as String? ?? '',
  );

  final String id;
  final String status;

  bool get isOpen => status == 'open';
}

/// Avis réduit — sert uniquement à savoir qui a déjà noté.
class MissionReviewRef {
  const MissionReviewRef({
    required this.id,
    required this.authorId,
    required this.rating,
  });

  factory MissionReviewRef.fromJson(JsonMap json) => MissionReviewRef(
    id: json['id'] as String? ?? '',
    authorId: json['authorId'] as String? ?? '',
    rating: _asInt(json['rating']) ?? 0,
  );

  final String id;
  final String authorId;
  final int rating;
}

class MissionDetail {
  const MissionDetail({
    required this.id,
    required this.status,
    required this.rawStatus,
    required this.client,
    required this.provider,
    required this.pack,
    required this.options,
    required this.reschedules,
    required this.reviews,
    this.scheduledAt,
    this.instructions,
    this.quotedAmount,
    this.createdAt,
    this.address,
    this.thread,
    this.cancellation,
  });

  factory MissionDetail.fromJson(JsonMap json) {
    final String rawStatus = json['status'] as String? ?? '';
    return MissionDetail(
      id: json['id'] as String? ?? '',
      status: MissionStatus.parse(rawStatus),
      rawStatus: rawStatus,
      scheduledAt: MissionDates.fromApiOrNull(json['scheduledAt'] as String?),
      instructions: json['instructions'] as String?,
      quotedAmount: _asInt(json['quotedAmount']),
      createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
      client: MissionParty.fromJson(_object(json['client'])),
      provider: MissionProviderSummary.fromJson(_object(json['provider'])),
      pack: MissionPack.fromJson(_object(json['pack'])),
      options: _list(json['options'], MissionOption.fromJson),
      address: json['address'] is Map<Object?, Object?>
          ? Address.fromJson(_object(json['address']))
          : null,
      thread: json['thread'] is Map<Object?, Object?>
          ? MissionThreadRef.fromJson(_object(json['thread']))
          : null,
      cancellation: json['cancellation'] is Map<Object?, Object?>
          ? Cancellation.fromJson(_object(json['cancellation']))
          : null,
      reschedules: _list(json['reschedules'], RescheduleRequest.fromJson),
      reviews: _list(json['reviews'], MissionReviewRef.fromJson),
    );
  }

  final String id;
  final MissionStatus status;
  final String rawStatus;
  final DateTime? scheduledAt;
  final String? instructions;

  /// Montant figé — `null` sur les missions historiques : afficher « — ».
  final int? quotedAmount;

  final DateTime? createdAt;
  final MissionParty client;
  final MissionProviderSummary provider;
  final MissionPack pack;
  final List<MissionOption> options;

  /// Lieu d'intervention — utile sur place, mis en cache avec le détail.
  final Address? address;

  final MissionThreadRef? thread;
  final Cancellation? cancellation;

  /// Demandes **en attente** uniquement — jamais l'historique.
  final List<RescheduleRequest> reschedules;

  final List<MissionReviewRef> reviews;

  /// Libellé de statut — le brut si le statut est inconnu de cette version.
  String get statusLabel =>
      status == MissionStatus.unknown ? rawStatus : status.label;

  /// La demande de report en attente, s'il y en a une.
  ///
  /// Le service n'en admet qu'**une seule** à la fois : tant qu'elle existe,
  /// l'action « Proposer un report » est indisponible (scénario 3.3).
  RescheduleRequest? get pendingReschedule =>
      reschedules.where((RescheduleRequest r) => r.isPending).firstOrNull;

  /// Vrai si [userId] a déjà déposé un avis sur cette mission.
  bool hasReviewBy(String userId) =>
      reviews.any((MissionReviewRef r) => r.authorId == userId);

  /// Vrai si [userId] est le client de la mission.
  bool isClient(String userId) => userId.isNotEmpty && client.id == userId;

  @override
  bool operator ==(Object other) => other is MissionDetail && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MissionDetail($id, $rawStatus)';
}

JsonMap _object(Object? value) => value is Map<Object?, Object?>
    ? value.cast<String, Object?>()
    : <String, Object?>{};

List<T> _list<T>(Object? value, T Function(JsonMap json) fromJson) =>
    value is List
    ? value
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> e) => fromJson(e.cast<String, Object?>()))
          .toList(growable: false)
    : const <Never>[];

int? _asInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  _ => null,
};

double? _asDouble(Object? value) => switch (value) {
  final double v => v,
  final num v => v.toDouble(),
  _ => null,
};
