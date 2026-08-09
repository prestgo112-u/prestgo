// Brouillon de réservation (FR-029, FR-033).
//
// Il porte tout ce que l'utilisateur compose, étape par étape, et **survit à un
// refus** : quand le service renvoie « adresse hors zone », on revient à l'étape
// adresse en conservant formule, options, date et instructions (FR-035). C'est la
// raison d'être de cet objet — sans lui, chaque correction repartirait de zéro.
//
// Son empreinte ([fingerprint]) pilote le cycle de vie de la clé d'idempotence :
// même contenu, même clé ; contenu modifié, clé neuve.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/idempotency.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_rules.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';

/// Étapes du parcours, dans l'ordre.
///
/// Sert aussi de cible de correction : un refus métier ramène à l'étape fautive.
enum BookingStep {
  pack,
  schedule,
  address,
  instructions,
  summary;

  String get title => switch (this) {
    BookingStep.pack => 'Formule et options',
    BookingStep.schedule => 'Date et heure',
    BookingStep.address => 'Lieu d’intervention',
    BookingStep.instructions => 'Instructions',
    BookingStep.summary => 'Récapitulatif',
  };
}

class BookingDraft {
  const BookingDraft({
    required this.provider,
    this.pack,
    this.optionIds = const <String>{},
    this.scheduledAt,
    this.address,
    this.instructions,
  });

  /// Fiche publique, chargée une fois : elle porte l'agenda, les absences et les
  /// zones dont les étapes suivantes ont besoin, sans nouvel appel.
  final ProviderPublicProfile provider;

  final ServicePack? pack;

  /// Identifiants d'options cochées. Un ensemble, pas une liste : le service refuse
  /// les doublons, et l'ordre de cochage n'a aucun sens.
  final Set<String> optionIds;

  /// Instant d'intervention, **en UTC** (voir `booking_rules.dart`).
  final DateTime? scheduledAt;

  final Address? address;
  final String? instructions;

  /// Options réellement sélectionnées, résolues sur la formule courante.
  ///
  /// Une option cochée puis rendue caduque par un changement de formule disparaît
  /// d'elle-même : le service la refuserait avec « Option inconnue pour cette
  /// formule ».
  List<PackOption> get selectedOptions {
    final ServicePack? pack = this.pack;
    if (pack == null) {
      return const <PackOption>[];
    }
    return <PackOption>[
      for (final PackOption option in pack.options)
        if (optionIds.contains(option.id)) option,
    ];
  }

  int get totalPrice => pack == null
      ? 0
      : BookingRules.totalPrice(pack: pack!, options: selectedOptions);

  int get totalDurationMinutes => pack == null
      ? 0
      : BookingRules.totalDurationMinutes(
          pack: pack!,
          options: selectedOptions,
        );

  /// Vrai quand toutes les étapes obligatoires sont renseignées.
  bool get isComplete => pack != null && scheduledAt != null && address != null;

  /// Première étape encore incomplète, ou [BookingStep.summary].
  BookingStep get nextStep {
    if (pack == null) {
      return BookingStep.pack;
    }
    if (scheduledAt == null) {
      return BookingStep.schedule;
    }
    if (address == null) {
      return BookingStep.address;
    }
    return BookingStep.summary;
  }

  /// Empreinte du contenu — pilote la clé d'idempotence.
  ///
  /// Deux compositions identiques donnent la même empreinte quel que soit l'ordre
  /// de cochage ; toute modification en produit une différente (scénario 2.10).
  String get fingerprint => bookingFingerprint(
    providerId: provider.id,
    packId: pack?.id ?? '',
    optionIds: optionIds,
    scheduledAt:
        scheduledAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    addressId: address?.id ?? '',
    instructions: instructions,
  );

  /// Corps de `POST /missions`.
  ///
  /// `scheduledAt` part en UTC — c'est le référentiel du service.
  JsonMap toRequestBody() {
    final ServicePack? pack = this.pack;
    final DateTime? scheduledAt = this.scheduledAt;
    final Address? address = this.address;
    if (pack == null || scheduledAt == null || address == null) {
      throw StateError('Brouillon incomplet : ${nextStep.title} manque');
    }
    final String? instructions = this.instructions?.trim();
    return <String, Object?>{
      'providerId': provider.id,
      'packId': pack.id,
      if (optionIds.isNotEmpty) 'optionIds': (optionIds.toList()..sort()),
      'scheduledAt': MissionDates.toApi(scheduledAt),
      'addressId': address.id,
      if (instructions != null && instructions.isNotEmpty)
        'instructions': instructions,
    };
  }

  BookingDraft copyWith({
    ServicePack? pack,
    Set<String>? optionIds,
    DateTime? scheduledAt,
    Address? address,
    String? instructions,
    bool clearSchedule = false,
    bool clearInstructions = false,
  }) => BookingDraft(
    provider: provider,
    pack: pack ?? this.pack,
    optionIds: optionIds ?? this.optionIds,
    scheduledAt: clearSchedule ? null : scheduledAt ?? this.scheduledAt,
    address: address ?? this.address,
    instructions: clearInstructions ? null : instructions ?? this.instructions,
  );

  /// Change de formule.
  ///
  /// Les options sont **remises à zéro** et la date effacée : elles appartenaient à
  /// l'ancienne formule, dont la durée n'est plus la même. Les conserver
  /// proposerait un créneau qui ne tient plus.
  BookingDraft withPack(ServicePack next) {
    if (pack?.id == next.id) {
      return this;
    }
    return BookingDraft(
      provider: provider,
      pack: next,
      address: address,
      instructions: instructions,
    );
  }

  /// Coche ou décoche une option, et efface la date : la durée totale a changé,
  /// le créneau retenu peut ne plus tenir dans le créneau du prestataire.
  BookingDraft toggleOption(String optionId) {
    final Set<String> next = <String>{...optionIds};
    if (!next.remove(optionId)) {
      next.add(optionId);
    }
    return BookingDraft(
      provider: provider,
      pack: pack,
      optionIds: next,
      address: address,
      instructions: instructions,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookingDraft &&
      other.provider.id == provider.id &&
      other.pack?.id == pack?.id &&
      other.optionIds.length == optionIds.length &&
      other.optionIds.containsAll(optionIds) &&
      other.scheduledAt == scheduledAt &&
      other.address?.id == address?.id &&
      other.instructions == instructions;

  @override
  int get hashCode => Object.hash(
    provider.id,
    pack?.id,
    Object.hashAllUnordered(optionIds),
    scheduledAt,
    address?.id,
    instructions,
  );

  @override
  String toString() =>
      'BookingDraft(${provider.id}, ${pack?.id}, ${optionIds.length} option(s), '
      '$scheduledAt)';
}
