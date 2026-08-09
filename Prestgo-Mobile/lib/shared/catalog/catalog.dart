// Catalogue et zones (T090, data-model §2).
//
// Ces entités sont quasi statiques : elles alimentent les filtres de recherche et
// changent au rythme de l'administration, pas de l'usage. C'est ce qui justifie leur
// cache de 24 heures et leur absence de pagination.
//
// Aucune n'est jamais construite depuis l'application : elles sont lues, affichées,
// et leurs identifiants renvoyés tels quels au service.
//
// Elles vivent dans `lib/shared/` et non dans `features/search/` : l'onboarding
// prestataire (sélecteur de service P3, zones à cocher P5) lit le même catalogue,
// et la porte G5 interdit à la surface prestataire d'importer la surface client.
// `features/search/domain/catalog.dart` les réexporte pour ses propres écrans.

import 'package:prestgo_mobile/core/api/api_envelope.dart';

/// Type de service — le second niveau du filtre.
class ServiceType {
  const ServiceType({required this.id, required this.name, this.description});

  factory ServiceType.fromJson(JsonMap json) => ServiceType(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
  );

  final String id;
  final String name;
  final String? description;

  @override
  bool operator ==(Object other) => other is ServiceType && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ServiceType($id, $name)';
}

/// Catégorie et ses types de service actifs.
class Category {
  const Category({
    required this.id,
    required this.name,
    this.description,
    this.serviceTypes = const <ServiceType>[],
  });

  factory Category.fromJson(JsonMap json) => Category(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    serviceTypes: switch (json['serviceTypes']) {
      final List<Object?> list =>
        list
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> e) =>
                  ServiceType.fromJson(e.cast<String, Object?>()),
            )
            .toList(growable: false),
      _ => const <ServiceType>[],
    },
  );

  final String id;
  final String name;
  final String? description;

  /// Peut être vide : une catégorie sans type actif ne propose pas de second
  /// niveau de filtre, mais reste sélectionnable.
  final List<ServiceType> serviceTypes;

  @override
  bool operator ==(Object other) => other is Category && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Category($id, $name)';
}

/// Zone d'intervention.
///
/// `latitude`, `longitude` et `radiusKm` sont **facultatifs** côté service : une
/// zone sans centre existe en base. Elle ne peut alors ni être triée par distance ni
/// couvrir une adresse — d'où [hasPosition], testé avant tout calcul.
class Zone {
  const Zone({
    required this.id,
    required this.name,
    this.cityName,
    this.latitude,
    this.longitude,
    this.radiusKm,
    this.distanceKm,
  });

  factory Zone.fromJson(JsonMap json) => Zone(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    cityName: switch (json['city']) {
      final Map<Object?, Object?> city => city['name'] as String?,
      _ => null,
    },
    latitude: _asDouble(json['latitude']),
    longitude: _asDouble(json['longitude']),
    radiusKm: _asDouble(json['radiusKm']),
    distanceKm: _asDouble(json['distanceKm']),
  );

  final String id;
  final String name;
  final String? cityName;
  final double? latitude;
  final double? longitude;
  final double? radiusKm;

  /// Renseigné par `GET /zones/nearby` seulement.
  final double? distanceKm;

  bool get hasPosition => latitude != null && longitude != null;

  /// Libellé affichable — « Cocody, Abidjan ».
  String get label => cityName == null ? name : '$name, $cityName';

  @override
  bool operator ==(Object other) => other is Zone && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Zone($id, $name)';
}

double? _asDouble(Object? value) => switch (value) {
  final double v => v,
  final num v => v.toDouble(),
  final String v => double.tryParse(v),
  _ => null,
};
