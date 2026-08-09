// Codes à usage unique — opérations 2 et 3.
//
// ⚠️ Le piège de ces deux routes : `POST /auth/otp/verify` renvoie **deux formes de
// `data` incompatibles** selon le motif.
//   • `phone_verification` / `email_verification` → `{ verified, activated }`
//   • `login`                                     → un couple de jetons
//
// Le dépôt expose donc deux méthodes distinctes plutôt qu'une seule au retour
// polymorphe : le type interdit alors de confondre les deux parcours.

import 'package:prestgo_mobile/core/api/api_envelope.dart';

/// Motifs acceptés par le service (`OTP_PURPOSES`).
enum OtpPurpose {
  phoneVerification,
  emailVerification,
  login;

  String get wireValue => switch (this) {
    OtpPurpose.phoneVerification => 'phone_verification',
    OtpPurpose.emailVerification => 'email_verification',
    OtpPurpose.login => 'login',
  };

  /// Déduit le motif de la forme du destinataire.
  ///
  /// Employé quand l'écran ne sait que le contact — l'inscription, par exemple, où
  /// le canal est celui qui a été renseigné.
  static OtpPurpose forTarget(String target) => target.contains('@')
      ? OtpPurpose.emailVerification
      : OtpPurpose.phoneVerification;
}

/// `POST /auth/otp/send`.
class SendOtpRequest {
  const SendOtpRequest({required this.target, required this.purpose});

  /// Numéro de téléphone ou adresse email.
  final String target;
  final OtpPurpose purpose;

  JsonMap toJson() => <String, Object?>{
    'target': target,
    'purpose': purpose.wireValue,
  };
}

/// Accusé d'envoi d'un code.
///
/// La réponse est identique que le destinataire corresponde à un compte connu ou
/// non : l'écran ne doit rien en déduire.
class OtpChallenge {
  const OtpChallenge({
    required this.message,
    required this.expiresInMinutes,
    this.devCode,
  });

  factory OtpChallenge.fromJson(JsonMap json) => OtpChallenge(
    message: json['message'] as String? ?? '',
    expiresInMinutes: switch (json['expiresInMinutes']) {
      final int value => value,
      final num value => value.toInt(),
      _ => null,
    },
    devCode: json['devCode'] as String?,
  );

  final String message;

  /// Durée de vie annoncée par le service — c'est **elle** qui pilote le compte à
  /// rebours, jamais une constante locale (porte G3). `null` si le service ne l'a
  /// pas renvoyée : l'écran retombe alors sur
  /// `AuthLimits.verificationCodeFallbackLifetime`.
  final int? expiresInMinutes;

  /// Renseigné en développement seulement (`AUTH_EXPOSE_DEV_CODES=true`).
  final String? devCode;

  Duration? get expiresIn =>
      expiresInMinutes == null ? null : Duration(minutes: expiresInMinutes!);
}

/// `POST /auth/otp/verify`.
class VerifyOtpRequest {
  const VerifyOtpRequest({
    required this.target,
    required this.code,
    required this.purpose,
  });

  final String target;

  /// Exactement six chiffres.
  final String code;
  final OtpPurpose purpose;

  JsonMap toJson() => <String, Object?>{
    'target': target,
    'code': code,
    'purpose': purpose.wireValue,
  };
}

/// Résultat d'une vérification de contact — **jamais** celui d'une connexion.
class OtpVerification {
  const OtpVerification({required this.verified, required this.activated});

  factory OtpVerification.fromJson(JsonMap json) => OtpVerification(
    verified: json['verified'] as bool? ?? false,
    activated: json['activated'] as bool? ?? false,
  );

  /// Le code était bon.
  final bool verified;

  /// Le compte est passé de `pending` à `active` : c'est l'activation après
  /// inscription (scénario 1.3). Faux quand on vérifie un contact d'un compte déjà
  /// actif (scénario 1.10) — l'écran suivant n'est alors pas le même.
  final bool activated;
}
