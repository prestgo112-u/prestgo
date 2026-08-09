// Le dossier prestataire, tel que `GET /providers/me` le décrit (data-model §4.1).
//
// Deux champs commandent tout l'écran et ne sont JAMAIS recalculés localement
// (porte G1) :
//   • `checklist` — cinq booléens calculés par le service ; chaque ligne fausse
//     ouvre l'étape correspondante du hub P8 ;
//   • `canSubmit` — pilote le bouton « Soumettre ». Il ne se déduit PAS de la
//     checklist : le compte démo approuvé a les cinq cases pertinentes et
//     `canSubmit: false`, parce qu'il n'y a rien à re-soumettre.
//
// `ProviderValidationStatus` vient du socle (`core/session/routing_profile.dart`) :
// le routeur s'en sert pour l'aiguillage, le redéclarer ici finirait par diverger.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/session/routing_profile.dart';

export 'package:prestgo_mobile/core/session/routing_profile.dart'
    show ProviderValidationStatus;

/// Interrupteur d'exploitation — sans rapport avec la décision de validation.
enum AvailabilityStatus {
  /// Visible en recherche, pastille « disponible ».
  available,

  /// **Toujours visible et réservable** ; seule la pastille change.
  busy,

  /// Disparaît de la recherche et refuse toute réservation.
  unavailable;

  static AvailabilityStatus parse(String? raw) => switch (raw) {
    'available' => AvailabilityStatus.available,
    'busy' => AvailabilityStatus.busy,
    'unavailable' => AvailabilityStatus.unavailable,
    _ => AvailabilityStatus.available,
  };

  String get wireValue => name;

  String get label => switch (this) {
    AvailabilityStatus.available => 'Disponible',
    AvailabilityStatus.busy => 'Occupé',
    AvailabilityStatus.unavailable => 'Indisponible',
  };

  /// Ce que la valeur change concrètement — affiché sous l'interrupteur, parce que
  /// la différence entre « Occupé » et « Indisponible » ne se devine pas.
  String get explanation => switch (this) {
    AvailabilityStatus.available =>
      'Votre fiche est visible et les clients peuvent réserver.',
    AvailabilityStatus.busy =>
      'Votre fiche reste visible et réservable : seule la pastille change.',
    AvailabilityStatus.unavailable =>
      'Votre fiche disparaît de la recherche et toute réservation est refusée.',
  };
}

/// Les cinq lignes du hub de complétude, dans l'ordre du parcours P2 → P7.
///
/// `key` est la clé émise par le service — dans la checklist comme dans
/// `errors[].field` d'une soumission refusée. [requirementLabel] reprend le
/// libellé d'erreur **officiel** (provider-checklist.ts) : c'est lui qui explique
/// les deux pièges du calcul — la présentation exigée alors qu'elle est
/// facultative à la création, la formule exigée alors que le service est déclaré.
enum ChecklistStep {
  profile(
    key: 'profile',
    title: 'Profil public',
    requirementLabel: 'Complétez votre nom public et votre présentation',
  ),
  services(
    key: 'services',
    title: 'Prestations',
    requirementLabel:
        'Déclarez au moins un service avec une formule tarifaire active',
  ),
  zones(
    key: 'zones',
    title: 'Zones d’intervention',
    requirementLabel: 'Choisissez au moins une zone d’intervention',
  ),
  availabilities(
    key: 'availabilities',
    title: 'Disponibilités',
    requirementLabel: 'Renseignez vos disponibilités hebdomadaires',
  ),
  documents(
    key: 'documents',
    title: 'Justificatifs',
    requirementLabel: 'Fournissez tous les justificatifs obligatoires',
  );

  const ChecklistStep({
    required this.key,
    required this.title,
    required this.requirementLabel,
  });

  final String key;
  final String title;
  final String requirementLabel;

  static ChecklistStep? parse(String? raw) => switch (raw) {
    'profile' => ChecklistStep.profile,
    'services' => ChecklistStep.services,
    'zones' => ChecklistStep.zones,
    'availabilities' => ChecklistStep.availabilities,
    'documents' => ChecklistStep.documents,
    _ => null,
  };

  /// Lignes désignées par un refus de soumission (`errors[].field`).
  ///
  /// L'écran passe en rouge **exactement** celles-là (scénario 4.7) : un champ
  /// inconnu est ignoré plutôt que deviné.
  static Set<ChecklistStep> fromSubmitError(ApiException error) =>
      <ChecklistStep>{
        for (final ApiErrorDetail detail in error.errors)
          if (parse(detail.field) case final ChecklistStep step) step,
      };
}

/// Les cinq booléens **calculés par le service** — jamais recalculés (porte G1).
class ProviderChecklist {
  const ProviderChecklist({
    required this.profile,
    required this.services,
    required this.zones,
    required this.availabilities,
    required this.documents,
  });

  factory ProviderChecklist.fromJson(JsonMap json) => ProviderChecklist(
    profile: json['profile'] as bool? ?? false,
    services: json['services'] as bool? ?? false,
    zones: json['zones'] as bool? ?? false,
    availabilities: json['availabilities'] as bool? ?? false,
    documents: json['documents'] as bool? ?? false,
  );

  /// Tout faux par défaut : c'est l'état d'un dossier qui vient de naître, et le
  /// repli le plus sûr si le service omettait la checklist.
  const ProviderChecklist.empty()
    : profile = false,
      services = false,
      zones = false,
      availabilities = false,
      documents = false;

  final bool profile;
  final bool services;
  final bool zones;
  final bool availabilities;
  final bool documents;

  bool operator [](ChecklistStep step) => switch (step) {
    ChecklistStep.profile => profile,
    ChecklistStep.services => services,
    ChecklistStep.zones => zones,
    ChecklistStep.availabilities => availabilities,
    ChecklistStep.documents => documents,
  };

  /// Purement informatif — le bouton « Soumettre » lit `canSubmit`, jamais ceci.
  bool get isComplete =>
      profile && services && zones && availabilities && documents;

  @override
  bool operator ==(Object other) =>
      other is ProviderChecklist &&
      other.profile == profile &&
      other.services == services &&
      other.zones == zones &&
      other.availabilities == availabilities &&
      other.documents == documents;

  @override
  int get hashCode =>
      Object.hash(profile, services, zones, availabilities, documents);

  @override
  String toString() =>
      'ProviderChecklist(profile: $profile, services: $services, '
      'zones: $zones, availabilities: $availabilities, documents: $documents)';
}

/// Vue « mon dossier » — le DTO unique de `POST`, `GET` et `PATCH /providers/me`
/// comme de `POST /providers/me/submit`.
class ProviderProfile {
  const ProviderProfile({
    required this.id,
    required this.publicName,
    required this.availabilityStatus,
    required this.checklist,
    required this.canSubmit,
    required this.resubmissionBlocked,
    this.bio,
    this.experienceYears,
    this.validationStatus,
    this.score = 0,
    this.reviewsCount = 0,
    this.requiredDocumentTypes = const <String>[],
    this.rejectionReason,
    this.submittedAt,
    this.avatarFileId,
    this.createdAt,
  });

  factory ProviderProfile.fromJson(JsonMap json) => ProviderProfile(
    id: json['id'] as String? ?? '',
    publicName: json['publicName'] as String? ?? '',
    bio: _text(json['bio']),
    experienceYears: switch (json['experienceYears']) {
      final int v => v,
      final num v => v.toInt(),
      _ => null,
    },
    validationStatus: ProviderValidationStatus.parse(
      json['validationStatus'] as String?,
    ),
    availabilityStatus: AvailabilityStatus.parse(
      json['availabilityStatus'] as String?,
    ),
    score: switch (json['score']) {
      final num v => v.toDouble(),
      _ => 0,
    },
    reviewsCount: switch (json['reviewsCount']) {
      final num v => v.toInt(),
      _ => 0,
    },
    checklist: switch (json['checklist']) {
      final Map<Object?, Object?> map => ProviderChecklist.fromJson(
        map.cast<String, Object?>(),
      ),
      _ => const ProviderChecklist.empty(),
    },
    requiredDocumentTypes: switch (json['requiredDocumentTypes']) {
      final List<Object?> list => list.whereType<String>().toList(
        growable: false,
      ),
      _ => const <String>[],
    },
    rejectionReason: _text(json['rejectionReason']),
    resubmissionBlocked: json['resubmissionBlocked'] as bool? ?? false,
    submittedAt: MissionDates.fromApiOrNull(json['submittedAt'] as String?),
    canSubmit: json['canSubmit'] as bool? ?? false,
    avatarFileId: _text(json['avatarFileId']),
    createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
  );

  /// Le `providerId`.
  final String id;

  final String publicName;

  /// Facultative à la création, **exigée par la checklist** — le libellé de la
  /// ligne « profil » doit le dire (piège n°1 de P8).
  final String? bio;

  final int? experienceYears;

  final ProviderValidationStatus? validationStatus;
  final AvailabilityStatus availabilityStatus;

  /// Lecture seule — affichés, jamais calculés.
  final double score;
  final int reviewsCount;

  final ProviderChecklist checklist;

  /// Source **unique** de l'écran des justificatifs : rien n'est codé en dur, le
  /// back-office peut exiger un second type demain (FR-057).
  final List<String> requiredDocumentTypes;

  /// Affiché en tête des écrans de correction (`changes_requested`, `rejected`).
  final String? rejectionReason;

  /// Masque définitivement la re-soumission — contact support seul.
  final bool resubmissionBlocked;

  final DateTime? submittedAt;

  /// Pilote le bouton « Soumettre » (**S**) — la checklist ne le remplace pas.
  final bool canSubmit;

  final String? avatarFileId;
  final DateTime? createdAt;

  /// Verrou de `pending_review` : identité en lecture seule, l'interrupteur de
  /// disponibilité **seul** reste actif (FR-062, scénario 4.8).
  bool get identityLocked =>
      validationStatus == ProviderValidationStatus.pendingReview;

  @override
  String toString() =>
      'ProviderProfile($id, ${validationStatus?.name}, '
      'canSubmit: $canSubmit)';
}

/// `null` plutôt qu'une chaîne vide — même règle que sur `Me` : un `''` passerait
/// les contrôles de présence sans rien porter.
String? _text(Object? value) {
  if (value is! String) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
