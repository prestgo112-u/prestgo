// Fiche publique d'un prestataire (T092, FR-027).
//
// Un seul appel compose tout l'écran. Ce fichier décrit donc un objet volumineux —
// et c'est voulu : le découper en plusieurs lectures ferait apparaître la fiche par
// morceaux sur une connexion mobile.
//
// Deux règles de lecture reviennent partout :
//   • une valeur absente est **masquée**, jamais affichée à zéro (FR-026) ;
//   • les heures d'agenda sont des chaînes `HH:MM` et ne subissent **aucune**
//     conversion de fuseau ; les absences, elles, sont des instants UTC.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/features/search/domain/catalog.dart';

/// Option d'une formule.
class PackOption {
  const PackOption({
    required this.id,
    required this.title,
    required this.price,
    required this.durationMinutes,
  });

  factory PackOption.fromJson(JsonMap json) => PackOption(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    price: _asInt(json['price']) ?? 0,
    // Une option peut ne rien ajouter à la durée : « déplacement hors horaires »
    // coûte plus cher sans prendre plus de temps.
    durationMinutes: _asInt(json['durationMinutes']) ?? 0,
  );

  final String id;
  final String title;
  final int price;
  final int durationMinutes;

  @override
  bool operator ==(Object other) => other is PackOption && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PackOption($id, $title)';
}

/// Formule réservable.
class ServicePack {
  const ServicePack({
    required this.id,
    required this.title,
    required this.price,
    required this.durationMinutes,
    this.description,
    this.options = const <PackOption>[],
  });

  factory ServicePack.fromJson(JsonMap json) => ServicePack(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String?,
    price: _asInt(json['price']) ?? 0,
    durationMinutes: _asInt(json['durationMinutes']) ?? 0,
    options: _list(json['options'], PackOption.fromJson),
  );

  final String id;
  final String title;
  final String? description;
  final int price;
  final int durationMinutes;
  final List<PackOption> options;

  /// Option de cette formule portant [optionId], ou `null`.
  ///
  /// Le service refuse une option qui n'appartient pas à la formule : ce filtre
  /// est ce qui empêche l'écran d'en proposer une après un changement de formule.
  PackOption? optionById(String optionId) {
    for (final PackOption option in options) {
      if (option.id == optionId) {
        return option;
      }
    }
    return null;
  }

  @override
  bool operator ==(Object other) => other is ServicePack && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ServicePack($id, $title)';
}

/// Prestation proposée, avec ses formules.
class PublicService {
  const PublicService({
    required this.id,
    required this.title,
    this.description,
    this.serviceTypeName,
    this.categoryName,
    this.packs = const <ServicePack>[],
  });

  factory PublicService.fromJson(JsonMap json) {
    final Object? type = json['serviceType'];
    final JsonMap? serviceType = type is Map<Object?, Object?>
        ? type.cast<String, Object?>()
        : null;
    final Object? rawCategory = serviceType?['category'];
    final JsonMap? category = rawCategory is Map<Object?, Object?>
        ? rawCategory.cast<String, Object?>()
        : null;

    return PublicService(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      serviceTypeName: serviceType?['name'] as String?,
      categoryName: category?['name'] as String?,
      packs: _list(json['packs'], ServicePack.fromJson),
    );
  }

  final String id;
  final String title;
  final String? description;
  final String? serviceTypeName;
  final String? categoryName;
  final List<ServicePack> packs;
}

/// Créneau hebdomadaire.
///
/// ⚠️ `weekday` suit la convention du service : **0 = dimanche**, 6 = samedi.
/// `startTime` et `endTime` sont des chaînes `HH:MM`, jamais des instants.
class WeeklySlot {
  const WeeklySlot({
    required this.weekday,
    required this.startTime,
    required this.endTime,
  });

  factory WeeklySlot.fromJson(JsonMap json) => WeeklySlot(
    weekday: _asInt(json['weekday']) ?? 0,
    startTime: json['startTime'] as String? ?? '00:00',
    endTime: json['endTime'] as String? ?? '00:00',
  );

  final int weekday;
  final String startTime;
  final String endTime;

  ClockTime get start => ClockTime.parse(startTime);
  ClockTime get end => ClockTime.parse(endTime);

  int get durationMinutes => end.minutesOfDay - start.minutesOfDay;

  /// Vrai si une intervention de [durationMinutes] commençant à [startAt] tient
  /// **entièrement** dans ce créneau.
  ///
  /// C'est la règle exacte du service : commencer à 11 h 30 une intervention d'une
  /// heure sur un créneau qui ferme à 12 h ferait déborder le prestataire
  /// (FR-031, scénario 2.7).
  bool contains(ClockTime startAt, int durationMinutes) {
    if (startAt < start) {
      return false;
    }
    return startAt.minutesOfDay + durationMinutes <= end.minutesOfDay;
  }

  @override
  bool operator ==(Object other) =>
      other is WeeklySlot &&
      other.weekday == weekday &&
      other.startTime == startTime &&
      other.endTime == endTime;

  @override
  int get hashCode => Object.hash(weekday, startTime, endTime);

  @override
  String toString() =>
      'WeeklySlot(${Weekdays.label(weekday)} $startTime-$endTime)';
}

/// Absence annoncée — un intervalle d'instants, en UTC.
class Unavailability {
  const Unavailability({required this.startAt, required this.endAt});

  factory Unavailability.fromJson(JsonMap json) => Unavailability(
    startAt:
        MissionDates.fromApiOrNull(json['startAt'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    endAt:
        MissionDates.fromApiOrNull(json['endAt'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final DateTime startAt;
  final DateTime endAt;

  /// Vrai si l'intervalle `[from, to[` recoupe cette absence.
  bool overlaps(DateTime from, DateTime to) =>
      startAt.isBefore(to) && endAt.isAfter(from);

  @override
  String toString() => 'Unavailability($startAt → $endAt)';
}

/// Avis affiché sur la fiche.
class ProviderReview {
  const ProviderReview({
    required this.id,
    required this.rating,
    required this.createdAt,
    this.comment,
    this.authorFirstName,
  });

  factory ProviderReview.fromJson(JsonMap json) => ProviderReview(
    id: json['id'] as String? ?? '',
    rating: _asInt(json['rating']) ?? 0,
    comment: json['comment'] as String?,
    // Prénom seul, ou rien : identifier complètement l'auteur d'un avis sur une
    // page publique serait une fuite de donnée personnelle.
    authorFirstName: json['authorFirstName'] as String?,
    createdAt:
        MissionDates.fromApiOrNull(json['createdAt'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final String id;
  final int rating;
  final String? comment;
  final String? authorFirstName;
  final DateTime createdAt;

  String get authorLabel => authorFirstName ?? 'Client PRESTGO';
}

/// Réalisation du portfolio.
class PortfolioItem {
  const PortfolioItem({
    required this.id,
    this.title,
    this.description,
    this.fileId,
  });

  factory PortfolioItem.fromJson(JsonMap json) => PortfolioItem(
    id: json['id'] as String? ?? '',
    title: json['title'] as String?,
    description: json['description'] as String?,
    fileId: json['fileId'] as String?,
  );

  final String id;
  final String? title;
  final String? description;
  final String? fileId;
}

/// Fiche publique complète.
class ProviderPublicProfile {
  const ProviderPublicProfile({
    required this.id,
    required this.publicName,
    required this.score,
    required this.reviewsCount,
    required this.availableNow,
    required this.memberSince,
    this.bio,
    this.experienceYears,
    this.avatarFileId,
    this.startingPrice,
    this.categories = const <Category>[],
    this.services = const <PublicService>[],
    this.portfolio = const <PortfolioItem>[],
    this.availability = const <WeeklySlot>[],
    this.upcomingUnavailabilities = const <Unavailability>[],
    this.zones = const <Zone>[],
    this.ratingDistribution = const <int, int>{},
    this.latestReviews = const <ProviderReview>[],
  });

  factory ProviderPublicProfile.fromJson(JsonMap json) => ProviderPublicProfile(
    id: json['id'] as String? ?? '',
    publicName: json['publicName'] as String? ?? '',
    bio: json['bio'] as String?,
    experienceYears: _asInt(json['experienceYears']),
    avatarFileId: json['avatarFileId'] as String?,
    availableNow: json['availableNow'] as bool? ?? false,
    score: _asDouble(json['score']) ?? 0,
    reviewsCount: _asInt(json['reviewsCount']) ?? 0,
    startingPrice: _asInt(json['startingPrice']),
    memberSince:
        MissionDates.fromApiOrNull(json['memberSince'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    categories: _list(json['categories'], Category.fromJson),
    services: _list(json['services'], PublicService.fromJson),
    portfolio: _list(json['portfolio'], PortfolioItem.fromJson),
    availability: _list(json['availability'], WeeklySlot.fromJson),
    upcomingUnavailabilities: _list(
      json['upcomingUnavailabilities'],
      Unavailability.fromJson,
    ),
    zones: _list(json['zones'], Zone.fromJson),
    ratingDistribution: switch (json['ratingDistribution']) {
      final Map<Object?, Object?> map => <int, int>{
        for (final MapEntry<Object?, Object?> entry in map.entries)
          if (int.tryParse('${entry.key}') case final int rating)
            rating: _asInt(entry.value) ?? 0,
      },
      _ => const <int, int>{},
    },
    latestReviews: _list(json['latestReviews'], ProviderReview.fromJson),
  );

  final String id;
  final String publicName;
  final String? bio;
  final int? experienceYears;
  final String? avatarFileId;
  final bool availableNow;
  final double score;
  final int reviewsCount;

  /// Prix de la formule la moins chère, ou `null` si le prestataire n'en a aucune.
  final int? startingPrice;

  final DateTime memberSince;
  final List<Category> categories;
  final List<PublicService> services;
  final List<PortfolioItem> portfolio;
  final List<WeeklySlot> availability;
  final List<Unavailability> upcomingUnavailabilities;
  final List<Zone> zones;

  /// Nombre d'avis par note, de 1 à 5.
  final Map<int, int> ratingDistribution;

  /// Les cinq derniers avis. La liste complète est paginée à part (T103).
  final List<ProviderReview> latestReviews;

  bool get isNew => reviewsCount == 0;

  /// Toutes les formules, toutes prestations confondues.
  List<ServicePack> get packs => <ServicePack>[
    for (final PublicService service in services) ...service.packs,
  ];

  /// Vrai si la fiche propose au moins une formule : sans elle, aucun bouton de
  /// réservation ne doit être affiché.
  bool get isBookable => packs.isNotEmpty;

  /// Formule portant [packId], toutes prestations confondues.
  ServicePack? packById(String packId) {
    for (final ServicePack pack in packs) {
      if (pack.id == packId) {
        return pack;
      }
    }
    return null;
  }

  /// Créneaux hebdomadaires d'un jour donné (0 = dimanche), triés.
  List<WeeklySlot> slotsForWeekday(int weekday) => <WeeklySlot>[
    for (final WeeklySlot slot in availability)
      if (slot.weekday == weekday) slot,
  ]..sort((WeeklySlot a, WeeklySlot b) => a.start.compareTo(b.start));

  /// Vrai si une intervention `[startAt, startAt + durationMinutes[` recoupe une
  /// absence annoncée.
  bool isAbsentDuring(DateTime startAt, int durationMinutes) {
    final DateTime endAt = startAt.add(Duration(minutes: durationMinutes));
    return upcomingUnavailabilities.any(
      (Unavailability absence) => absence.overlaps(startAt, endAt),
    );
  }

  @override
  String toString() => 'ProviderPublicProfile($id, $publicName)';
}

List<T> _list<T>(Object? raw, T Function(JsonMap json) fromJson) =>
    switch (raw) {
      final List<Object?> list =>
        list
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> e) => fromJson(e.cast<String, Object?>()),
            )
            .toList(growable: false),
      _ => const <Never>[],
    };

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
