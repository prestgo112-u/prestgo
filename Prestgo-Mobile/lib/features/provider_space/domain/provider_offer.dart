// L'offre du prestataire côté gestion (data-model §4.2, §4.3).
//
// À ne pas confondre avec les modèles de la fiche **publique**
// (`features/search/domain/provider_profile.dart`) : ici tout est visible, y
// compris ce qui est désactivé — `active: false` est un état de gestion, pas une
// disparition. Il n'existe d'ailleurs **aucune suppression** : un service ou une
// formule se désactive, jamais ne s'efface.
//
// La création (`POST`) répond la forme brute Prisma, sans `serviceType` ni `packs`
// imbriqués ; la liste (`GET`) imbrique tout. Le même `fromJson` lit les deux : les
// champs absents retombent sur leurs valeurs vides.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

/// Option d'une formule.
///
/// `durationMinutes` vaut 0 par défaut : une option peut n'ajouter que du prix.
class PackOption {
  const PackOption({
    required this.id,
    required this.title,
    required this.price,
    this.durationMinutes = 0,
    this.active = true,
  });

  factory PackOption.fromJson(JsonMap json) => PackOption(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    price: switch (json['price']) {
      final num v => v,
      _ => 0,
    },
    durationMinutes: switch (json['durationMinutes']) {
      final num v => v.toInt(),
      _ => 0,
    },
    active: json['active'] as bool? ?? true,
  );

  final String id;
  final String title;
  final num price;
  final int durationMinutes;
  final bool active;

  @override
  bool operator ==(Object other) => other is PackOption && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PackOption($id, $title, $price)';
}

/// Formule tarifaire d'un service.
class ServicePack {
  const ServicePack({
    required this.id,
    required this.title,
    required this.price,
    required this.durationMinutes,
    this.providerServiceId,
    this.description,
    this.active = true,
    this.options = const <PackOption>[],
  });

  factory ServicePack.fromJson(JsonMap json) => ServicePack(
    id: json['id'] as String? ?? '',
    providerServiceId: json['providerServiceId'] as String?,
    title: json['title'] as String? ?? '',
    description: json['description'] as String?,
    price: switch (json['price']) {
      final num v => v,
      _ => 0,
    },
    durationMinutes: switch (json['durationMinutes']) {
      final num v => v.toInt(),
      _ => 0,
    },
    active: json['active'] as bool? ?? true,
    options: switch (json['options']) {
      final List<Object?> list =>
        list
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> e) =>
                  PackOption.fromJson(e.cast<String, Object?>()),
            )
            .toList(growable: false),
      _ => const <PackOption>[],
    },
  );

  final String id;

  /// Présent sur la forme brute de création ; absent de la liste imbriquée, où le
  /// service porteur est le parent.
  final String? providerServiceId;

  final String title;
  final String? description;
  final num price;
  final int durationMinutes;
  final bool active;
  final List<PackOption> options;

  @override
  bool operator ==(Object other) => other is ServicePack && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'ServicePack($id, $title, $price, ${durationMinutes}min)';
}

/// Type de service tel que la liste des services le rattache.
class OfferServiceType {
  const OfferServiceType({
    required this.id,
    required this.name,
    this.categoryName,
  });

  factory OfferServiceType.fromJson(JsonMap json) => OfferServiceType(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    categoryName: switch (json['category']) {
      final Map<Object?, Object?> category => category['name'] as String?,
      _ => null,
    },
  );

  final String id;
  final String name;
  final String? categoryName;

  /// « Réparation de fuite — Plomberie ».
  String get label => categoryName == null ? name : '$name — $categoryName';

  @override
  bool operator ==(Object other) => other is OfferServiceType && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'OfferServiceType($id, $name)';
}

/// Service déclaré par le prestataire.
class ProviderService {
  const ProviderService({
    required this.id,
    required this.title,
    this.serviceTypeId,
    this.description,
    this.active = true,
    this.createdAt,
    this.serviceType,
    this.packs = const <ServicePack>[],
  });

  factory ProviderService.fromJson(JsonMap json) => ProviderService(
    id: json['id'] as String? ?? '',
    serviceTypeId: json['serviceTypeId'] as String?,
    title: json['title'] as String? ?? '',
    description: json['description'] as String?,
    active: json['active'] as bool? ?? true,
    createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
    serviceType: switch (json['serviceType']) {
      final Map<Object?, Object?> type => OfferServiceType.fromJson(
        type.cast<String, Object?>(),
      ),
      _ => null,
    },
    packs: switch (json['packs']) {
      final List<Object?> list =>
        list
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> e) =>
                  ServicePack.fromJson(e.cast<String, Object?>()),
            )
            .toList(growable: false),
      _ => const <ServicePack>[],
    },
  );

  final String id;
  final String? serviceTypeId;
  final String title;
  final String? description;
  final bool active;
  final DateTime? createdAt;

  /// Absent de la forme brute de création — la liste seule l'imbrique.
  final OfferServiceType? serviceType;

  final List<ServicePack> packs;

  /// Ce que la case `services` de la checklist exige : un service actif **avec**
  /// une formule active. Purement informatif — la case elle-même vient du service.
  bool get hasActivePack =>
      active && packs.any((ServicePack pack) => pack.active);

  @override
  bool operator ==(Object other) => other is ProviderService && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ProviderService($id, $title, packs: ${packs.length})';
}
