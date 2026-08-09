// Ligne de « Mes missions » (T124, data-model §5.1).
//
// ⚠️ `quotedAmount` peut être `null` — missions antérieures au montant figé :
// afficher « — », jamais « 0 XOF ». Le tri est celui du service (décroissant côté
// client, croissant côté prestataire) et n'est **jamais** recalculé (FR-038).

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';

class MissionListItem {
  const MissionListItem({
    required this.id,
    required this.status,
    required this.rawStatus,
    required this.durationMinutes,
    required this.packTitle,
    required this.clientName,
    required this.providerId,
    required this.providerName,
    required this.city,
    this.scheduledAt,
    this.quotedAmount,
    this.providerAvatarFileId,
    this.commune,
    this.createdAt,
  });

  factory MissionListItem.fromJson(JsonMap json) {
    final String rawStatus = json['status'] as String? ?? '';
    return MissionListItem(
      id: json['id'] as String? ?? '',
      status: MissionStatus.parse(rawStatus),
      rawStatus: rawStatus,
      scheduledAt: MissionDates.fromApiOrNull(json['scheduledAt'] as String?),
      quotedAmount: _asInt(json['quotedAmount']),
      durationMinutes: _asInt(json['durationMinutes']) ?? 0,
      packTitle: json['packTitle'] as String? ?? '',
      clientName: json['clientName'] as String? ?? '',
      providerId: json['providerId'] as String? ?? '',
      providerName: json['providerName'] as String? ?? '',
      providerAvatarFileId: json['providerAvatarFileId'] as String?,
      city: json['city'] as String? ?? '',
      commune: json['commune'] as String?,
      createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
    );
  }

  final String id;
  final MissionStatus status;

  /// Statut tel que reçu — affiché tel quel quand [status] est inconnu.
  final String rawStatus;

  final DateTime? scheduledAt;

  /// Montant figé par le service, ou `null` sur les missions historiques.
  final int? quotedAmount;

  final int durationMinutes;
  final String packTitle;
  final String clientName;
  final String providerId;
  final String providerName;
  final String? providerAvatarFileId;
  final String city;
  final String? commune;
  final DateTime? createdAt;

  /// Libellé de statut — le brut si le statut est inconnu de cette version.
  String get statusLabel =>
      status == MissionStatus.unknown ? rawStatus : status.label;

  /// « Cocody, Abidjan » ou « Abidjan ».
  String get locality =>
      commune == null || commune!.isEmpty ? city : '$commune, $city';

  @override
  bool operator ==(Object other) => other is MissionListItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'MissionListItem($id, $rawStatus)';
}

int? _asInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  _ => null,
};
