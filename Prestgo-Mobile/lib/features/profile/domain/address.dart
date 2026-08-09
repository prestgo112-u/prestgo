// Carnet d'adresses (T093, FR-019, FR-020).
//
// Une adresse **doit** porter une position : c'est elle qui permet de vérifier
// qu'elle tombe dans une zone d'intervention. Une adresse sans coordonnées rend la
// réservation impossible — le service la refuse, et l'application ne doit pas
// permettre d'en créer une.
//
// La suppression a deux issues, toutes deux des succès : retrait réel, ou archivage
// quand l'adresse documente une mission passée. Voir [AddressRemoval].

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

class Address {
  const Address({
    required this.id,
    required this.label,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.isDefault,
    required this.createdAt,
    this.commune,
    this.details,
  });

  factory Address.fromJson(JsonMap json) => Address(
    id: json['id'] as String? ?? '',
    label: json['label'] as String? ?? '',
    city: json['city'] as String? ?? '',
    commune: json['commune'] as String?,
    details: json['details'] as String?,
    latitude: _asDouble(json['latitude']) ?? 0,
    longitude: _asDouble(json['longitude']) ?? 0,
    isDefault: json['isDefault'] as bool? ?? false,
    createdAt:
        MissionDates.fromApiOrNull(json['createdAt'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final String id;
  final String label;
  final String city;
  final String? commune;
  final String? details;
  final double latitude;
  final double longitude;
  final bool isDefault;
  final DateTime createdAt;

  /// Adresse en une ligne — « Cocody, Abidjan » ou « Abidjan ».
  String get locality =>
      commune == null || commune!.isEmpty ? city : '$commune, $city';

  /// Ligne complète, détails compris.
  String get fullLine =>
      details == null || details!.isEmpty ? locality : '$details — $locality';

  /// Le service marque une adresse archivée en suffixant son libellé.
  ///
  /// C'est un détail d'implémentation qu'on ne peut pas ignorer : ces adresses
  /// n'ont pas à réapparaître dans le carnet après un rechargement.
  bool get isArchived => label.endsWith('(archivée)');

  @override
  bool operator ==(Object other) => other is Address && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Address($id, $label)';
}

/// Corps de création et de modification d'une adresse.
class AddressDraft {
  const AddressDraft({
    required this.label,
    required this.city,
    required this.latitude,
    required this.longitude,
    this.commune,
    this.details,
    this.isDefault,
  });

  final String label;
  final String city;
  final String? commune;
  final String? details;
  final double latitude;
  final double longitude;

  /// `null` laisse le service décider : la première adresse d'un carnet devient
  /// automatiquement l'adresse par défaut.
  final bool? isDefault;

  JsonMap toJson() => <String, Object?>{
    'label': label,
    'city': city,
    'commune': ?commune,
    'details': ?details,
    'latitude': latitude,
    'longitude': longitude,
    'isDefault': ?isDefault,
  };
}

/// Résultat d'une suppression — **deux formes de succès**.
class AddressRemoval {
  const AddressRemoval({
    required this.removed,
    required this.archived,
    this.reason,
  });

  factory AddressRemoval.fromJson(JsonMap json) => AddressRemoval(
    removed: json['removed'] as bool? ?? false,
    archived: json['archived'] as bool? ?? false,
    reason: json['reason'] as String?,
  );

  /// L'adresse a été réellement supprimée.
  final bool removed;

  /// L'adresse a été conservée parce qu'elle documente une mission passée.
  final bool archived;

  /// Motif de l'archivage, tel que le service le formule.
  final String? reason;

  /// Message à afficher — celui du service quand il en fournit un.
  String get message =>
      reason ??
      (removed ? 'Adresse supprimée.' : 'Adresse retirée de votre carnet.');
}

double? _asDouble(Object? value) => switch (value) {
  final double v => v,
  final num v => v.toDouble(),
  final String v => double.tryParse(v),
  _ => null,
};
