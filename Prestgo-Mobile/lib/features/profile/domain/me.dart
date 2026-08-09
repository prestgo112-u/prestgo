// Le compte connecté, tel que `GET /me` le décrit (data-model §1.2).
//
// `UserStatus` et `ProviderValidationStatus` ne sont pas redéclarés ici : ils vivent
// dans `core/session/routing_profile.dart` parce que la session et le routeur s'en
// servent aussi, et qu'une seconde définition finirait par diverger. Ce fichier les
// réexporte pour qu'un écran de profil n'ait qu'un import à faire.
//
// Champ à ne jamais utiliser pour décider quoi que ce soit : `roles`. Il porte les
// rôles d'**administration**, vide pour les comptes ordinaires ; l'aiguillage se fait
// sur `status`, `hasProviderProfile` et `providerValidationStatus` (FR-013).

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/session/routing_profile.dart';

export 'package:prestgo_mobile/core/session/routing_profile.dart'
    show ProviderValidationStatus, RoutingProfile, UserStatus;

/// Canal par lequel un contact reste à vérifier.
///
/// ⚠️ Le service nomme le canal téléphone `sms`, alors que le motif OTP
/// correspondant est `phone_verification` : c'est [otpPurpose] qui fait le pont.
enum VerificationChannel {
  email,
  sms;

  static VerificationChannel? parse(String? raw) => switch (raw) {
    'email' => VerificationChannel.email,
    'sms' => VerificationChannel.sms,
    _ => null,
  };

  /// Motif à passer à `/auth/otp/send` et `/auth/otp/verify`.
  String get otpPurpose => switch (this) {
    VerificationChannel.email => 'email_verification',
    VerificationChannel.sms => 'phone_verification',
  };

  String get label => switch (this) {
    VerificationChannel.email => 'adresse email',
    VerificationChannel.sms => 'numéro de téléphone',
  };
}

/// Vérification déclenchée par une modification de contact (`PATCH /me`).
class PendingVerification {
  const PendingVerification({required this.channel, required this.target});

  static PendingVerification? fromJson(JsonMap json) {
    final VerificationChannel? channel = VerificationChannel.parse(
      json['channel'] as String?,
    );
    final String? target = json['target'] as String?;
    if (channel == null || target == null || target.isEmpty) {
      return null;
    }
    return PendingVerification(channel: channel, target: target);
  }

  final VerificationChannel channel;

  /// Destinataire du code — le **nouveau** contact, pas l'ancien.
  final String target;

  JsonMap toJson() => <String, Object?>{
    'channel': channel.name,
    'target': target,
  };

  @override
  bool operator ==(Object other) =>
      other is PendingVerification &&
      other.channel == channel &&
      other.target == target;

  @override
  int get hashCode => Object.hash(channel, target);

  @override
  String toString() => 'PendingVerification(${channel.name}, $target)';
}

/// Profil du compte connecté.
class Me {
  const Me({
    required this.id,
    required this.status,
    required this.emailVerified,
    required this.phoneVerified,
    required this.hasClientProfile,
    required this.hasProviderProfile,
    required this.createdAt,
    this.firstName,
    this.lastName,
    this.email,
    this.phone,
    this.roles = const <String>[],
    this.providerId,
    this.providerValidationStatus,
    this.pendingVerifications = const <PendingVerification>[],
  });

  /// Décode `data` de `GET /me` **et** de `PATCH /me` — la seconde ajoute
  /// `pendingVerifications` au même objet, sans rien changer d'autre.
  factory Me.fromJson(JsonMap json) => Me(
    id: json['id'] as String? ?? '',
    firstName: _text(json['firstName']),
    lastName: _text(json['lastName']),
    email: _text(json['email']),
    phone: _text(json['phone']),
    status: UserStatus.parse(json['status'] as String?),
    emailVerified: json['emailVerified'] as bool? ?? false,
    phoneVerified: json['phoneVerified'] as bool? ?? false,
    roles: switch (json['roles']) {
      final List<Object?> list => list.whereType<String>().toList(
        growable: false,
      ),
      _ => const <String>[],
    },
    hasClientProfile: json['hasClientProfile'] as bool? ?? false,
    hasProviderProfile: json['hasProviderProfile'] as bool? ?? false,
    providerId: _text(json['providerId']),
    providerValidationStatus: ProviderValidationStatus.parse(
      json['providerValidationStatus'] as String?,
    ),
    createdAt:
        MissionDates.fromApiOrNull(json['createdAt'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    pendingVerifications: switch (json['pendingVerifications']) {
      final List<Object?> list =>
        list
            .whereType<Map<Object?, Object?>>()
            .map(
              (Map<Object?, Object?> e) =>
                  PendingVerification.fromJson(e.cast<String, Object?>()),
            )
            .nonNulls
            .toList(growable: false),
      _ => const <PendingVerification>[],
    },
  );

  final String id;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phone;
  final UserStatus status;

  /// Pilote la pastille « non vérifié » de l'écran de profil (FR-016).
  final bool emailVerified;
  final bool phoneVerified;

  /// Rôles d'administration. Affiché nulle part, **jamais** lu par l'aiguillage.
  final List<String> roles;

  /// Faux sur des comptes historiques pourtant clients : à ne pas utiliser pour
  /// autoriser l'espace client (FR-015).
  final bool hasClientProfile;

  final bool hasProviderProfile;
  final String? providerId;
  final ProviderValidationStatus? providerValidationStatus;

  /// Ancienneté du compte, affichée sur le profil.
  final DateTime createdAt;

  /// Non vide seulement en réponse à `PATCH /me` : l'écran enchaîne alors sur la
  /// vérification du premier contact de la liste (FR-017).
  final List<PendingVerification> pendingVerifications;

  /// Projection retenue par le gardien du routeur.
  RoutingProfile get routing => RoutingProfile(
    userStatus: status,
    hasProviderProfile: hasProviderProfile,
    providerValidationStatus: providerValidationStatus,
  );

  /// Nom affichable, ou le contact à défaut — un compte peut n'avoir ni l'un ni
  /// l'autre juste après l'inscription.
  String get displayName {
    final String full = <String?>[
      firstName,
      lastName,
    ].whereType<String>().join(' ').trim();
    if (full.isNotEmpty) {
      return full;
    }
    return email ?? phone ?? 'Mon compte';
  }

  /// Contacts restant à vérifier — la liste des pastilles de l'écran de profil.
  List<VerificationChannel> get unverifiedChannels => <VerificationChannel>[
    if (email != null && !emailVerified) VerificationChannel.email,
    if (phone != null && !phoneVerified) VerificationChannel.sms,
  ];

  /// Sérialisation destinée au **cache** (T080), pas au service.
  ///
  /// `pendingVerifications` en est absent volontairement : c'est le résultat
  /// éphémère d'une modification, il n'a aucun sens au redémarrage suivant.
  JsonMap toJson() => <String, Object?>{
    'id': id,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'phone': phone,
    'status': status.name,
    'emailVerified': emailVerified,
    'phoneVerified': phoneVerified,
    'roles': roles,
    'hasClientProfile': hasClientProfile,
    'hasProviderProfile': hasProviderProfile,
    'providerId': providerId,
    'providerValidationStatus': providerValidationStatus?.wireValue,
    'createdAt': MissionDates.toApi(createdAt),
  };

  @override
  bool operator ==(Object other) =>
      other is Me &&
      other.id == id &&
      other.firstName == firstName &&
      other.lastName == lastName &&
      other.email == email &&
      other.phone == phone &&
      other.status == status &&
      other.emailVerified == emailVerified &&
      other.phoneVerified == phoneVerified &&
      other.hasClientProfile == hasClientProfile &&
      other.hasProviderProfile == hasProviderProfile &&
      other.providerId == providerId &&
      other.providerValidationStatus == providerValidationStatus &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
    id,
    firstName,
    lastName,
    email,
    phone,
    status,
    emailVerified,
    phoneVerified,
    hasClientProfile,
    hasProviderProfile,
    providerId,
    providerValidationStatus,
    createdAt,
  );

  @override
  String toString() =>
      'Me($id, ${status.name}, prestataire: $hasProviderProfile)';
}

/// `null` plutôt qu'une chaîne vide : le service renvoie `null` pour un contact
/// absent, et un `''` traverserait les contrôles de présence sans être un contact.
String? _text(Object? value) {
  if (value is! String) {
    return null;
  }
  final String trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
