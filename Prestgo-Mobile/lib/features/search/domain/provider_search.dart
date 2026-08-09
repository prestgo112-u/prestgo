// Recherche de prestataires (T091, FR-022 à FR-026).
//
// Deux objets : ce qu'on demande, et ce qu'on reçoit.
//
// [ProviderSearchQuery] porte les combinaisons **refusées par le service** sous forme
// de prédicats ([isDistanceSortAvailable], [hasIncompleteSlot]). L'écran s'en sert
// pour rendre le tri « distance » indisponible et lier date et heure, plutôt que
// d'envoyer une requête qu'on sait devoir échouer (FR-024, scénarios 2.2 et 2.3).

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

/// Tri accepté par le service.
enum SearchSort {
  distance,
  rating,
  recent;

  String get wireValue => name;

  String get label => switch (this) {
    SearchSort.distance => 'Les plus proches',
    SearchSort.rating => 'Les mieux notés',
    SearchSort.recent => 'Les plus récents',
  };
}

/// Position retenue pour la recherche.
class SearchPosition {
  const SearchPosition({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is SearchPosition &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'SearchPosition($latitude, $longitude)';
}

/// Créneau souhaité — date **et** heure, indissociables.
///
/// Le type impose ce que le service exige : impossible de construire l'un sans
/// l'autre. C'est ce qui rend le scénario 2.3 structurellement impossible.
class SearchSlot {
  const SearchSlot({required this.date, required this.startTime});

  /// Jour d'intervention. Seule la partie date est transmise (`AAAA-MM-JJ`).
  final DateTime date;

  /// Heure de début, `HH:MM` — **jamais** convertie de fuseau (data-model §7).
  final String startTime;

  String get wireDate =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is SearchSlot && other.date == date && other.startTime == startTime;

  @override
  int get hashCode => Object.hash(date, startTime);
}

/// Filtres de `GET /providers/search`.
class ProviderSearchQuery {
  const ProviderSearchQuery({
    this.categoryId,
    this.serviceTypeId,
    this.position,
    this.radiusKm = PaginationLimits.defaultRadiusKm,
    this.zoneId,
    this.slot,
    this.minRating,
    this.query,
    this.sort,
  });

  final String? categoryId;
  final String? serviceTypeId;
  final SearchPosition? position;

  /// 1 à 50 km, 10 par défaut. Ignoré sans position.
  final double radiusKm;

  final String? zoneId;
  final SearchSlot? slot;
  final double? minRating;
  final String? query;

  /// `null` laisse le service décider : distance s'il connaît la position, note
  /// sinon.
  final SearchSort? sort;

  /// Le tri par distance exige une position : sans elle, le service répond 400.
  ///
  /// L'écran s'en sert pour désactiver l'option **avec son explication**, plutôt
  /// que de laisser l'utilisateur découvrir le refus (scénario 2.2).
  bool get isDistanceSortAvailable => position != null;

  /// Vrai si une position est nécessaire mais absente pour le tri demandé.
  bool get requestsUnavailableSort =>
      sort == SearchSort.distance && position == null;

  /// Vrai si la recherche porte au moins un filtre — pilote « Retirer les filtres ».
  bool get hasFilters =>
      categoryId != null ||
      serviceTypeId != null ||
      zoneId != null ||
      slot != null ||
      minRating != null ||
      (query?.trim().isNotEmpty ?? false);

  /// Vrai si le rayon peut encore être élargi (proposition sur résultat vide).
  bool get canWidenRadius =>
      position != null && radiusKm < PaginationLimits.maxRadiusKm;

  ProviderSearchQuery copyWith({
    String? categoryId,
    String? serviceTypeId,
    SearchPosition? position,
    double? radiusKm,
    String? zoneId,
    SearchSlot? slot,
    double? minRating,
    String? query,
    SearchSort? sort,
    bool clearCategory = false,
    bool clearServiceType = false,
    bool clearPosition = false,
    bool clearZone = false,
    bool clearSlot = false,
    bool clearMinRating = false,
    bool clearQuery = false,
    bool clearSort = false,
  }) => ProviderSearchQuery(
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    serviceTypeId: clearServiceType
        ? null
        : serviceTypeId ?? this.serviceTypeId,
    position: clearPosition ? null : position ?? this.position,
    radiusKm: radiusKm ?? this.radiusKm,
    zoneId: clearZone ? null : zoneId ?? this.zoneId,
    slot: clearSlot ? null : slot ?? this.slot,
    minRating: clearMinRating ? null : minRating ?? this.minRating,
    query: clearQuery ? null : query ?? this.query,
    sort: clearSort ? null : sort ?? this.sort,
  );

  /// Retire tous les filtres, en gardant la position : la proposition « Retirer
  /// les filtres » d'un résultat vide ne doit pas faire perdre la géolocalisation
  /// que l'utilisateur vient d'accorder.
  ProviderSearchQuery cleared() =>
      ProviderSearchQuery(position: position, radiusKm: radiusKm, sort: sort);

  /// Élargit le rayon d'un cran, sans dépasser le plafond du service.
  ProviderSearchQuery widened() => copyWith(
    radiusKm: (radiusKm * 2).clamp(
      PaginationLimits.minRadiusKm,
      PaginationLimits.maxRadiusKm,
    ),
  );

  /// Paramètres de requête, sans les valeurs absentes.
  ///
  /// `radiusKm` n'est transmis qu'avec une position : seul, il n'a pas de sens et
  /// encombrerait les journaux du service.
  Map<String, Object?> toQueryParameters({
    required int page,
    required int limit,
  }) {
    final SearchPosition? position = this.position;
    final SearchSlot? slot = this.slot;
    return <String, Object?>{
      'page': page,
      'limit': limit,
      'categoryId': ?categoryId,
      'serviceTypeId': ?serviceTypeId,
      if (position != null) ...<String, Object?>{
        'latitude': position.latitude,
        'longitude': position.longitude,
        'radiusKm': radiusKm,
      },
      'zoneId': ?zoneId,
      if (slot != null) ...<String, Object?>{
        'date': slot.wireDate,
        'startTime': slot.startTime,
      },
      'minRating': ?minRating,
      if (query?.trim().isNotEmpty ?? false) 'q': query!.trim(),
      // Le tri « distance » n'est jamais transmis sans position : ce serait un 400
      // certain (FR-024).
      if (sort != null && !requestsUnavailableSort) 'sort': sort!.wireValue,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ProviderSearchQuery &&
      other.categoryId == categoryId &&
      other.serviceTypeId == serviceTypeId &&
      other.position == position &&
      other.radiusKm == radiusKm &&
      other.zoneId == zoneId &&
      other.slot == slot &&
      other.minRating == minRating &&
      other.query == query &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    categoryId,
    serviceTypeId,
    position,
    radiusKm,
    zoneId,
    slot,
    minRating,
    query,
    sort,
  );
}

/// Une ligne de résultat.
class ProviderSearchResult {
  const ProviderSearchResult({
    required this.id,
    required this.publicName,
    required this.score,
    required this.reviewsCount,
    required this.availableNow,
    this.distanceKm,
    this.categories = const <String>[],
    this.startingPrice,
    this.avatarFileId,
  });

  factory ProviderSearchResult.fromJson(JsonMap json) => ProviderSearchResult(
    id: json['id'] as String? ?? '',
    publicName: json['publicName'] as String? ?? '',
    score: _asDouble(json['score']) ?? 0,
    reviewsCount: _asInt(json['reviewsCount']) ?? 0,
    distanceKm: _asDouble(json['distanceKm']),
    categories: switch (json['categories']) {
      final List<Object?> list => list.whereType<String>().toList(
        growable: false,
      ),
      _ => const <String>[],
    },
    startingPrice: _asInt(json['startingPrice']),
    avatarFileId: json['avatarFileId'] as String?,
    availableNow: json['availableNow'] as bool? ?? false,
  );

  final String id;
  final String publicName;
  final double score;
  final int reviewsCount;

  /// `null` quand aucune position n'a été fournie : la distance est alors
  /// **masquée**, jamais affichée à zéro (FR-026).
  final double? distanceKm;

  final List<String> categories;

  /// `null` quand le prestataire n'a aucune formule tarifée : masqué de même.
  final int? startingPrice;

  final String? avatarFileId;
  final bool availableNow;

  /// Vrai tant qu'aucun avis n'a été déposé.
  ///
  /// L'écran affiche alors « Nouveau » : une note de 0 ferait passer un
  /// prestataire neuf pour un mauvais prestataire.
  bool get isNew => reviewsCount == 0;

  @override
  bool operator ==(Object other) =>
      other is ProviderSearchResult && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ProviderSearchResult($id, $publicName)';
}

double? _asDouble(Object? value) => switch (value) {
  final double v => v,
  final num v => v.toDouble(),
  final String v => double.tryParse(v),
  _ => null,
};

int? _asInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};
