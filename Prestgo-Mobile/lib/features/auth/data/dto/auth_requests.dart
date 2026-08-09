// Corps de requête des opérations 1 à 8 (contracts/api-consumption.md).
//
// Écrits à la main comme le reste de la couche réseau (R9). Ils ne portent aucune
// validation : les contrôles de saisie sont dans `core/validation/validators.dart`,
// appliqués par les écrans avant l'envoi, et c'est le service qui arbitre (porte G1).
//
// ⚠️ Le service applique `whitelist: true` sur son `ValidationPipe` : tout champ non
// déclaré côté service est **silencieusement retiré**. Un champ facultatif absent est
// donc toujours préférable à un champ à `null`, d'où les `if (… != null)` ci-dessous.

import 'package:prestgo_mobile/core/api/api_envelope.dart';

/// `POST /auth/register` — au moins un des deux contacts est requis.
class RegisterRequest {
  const RegisterRequest({
    required this.password,
    this.email,
    this.phone,
    this.firstName,
    this.lastName,
  });

  final String password;
  final String? email;
  final String? phone;
  final String? firstName;
  final String? lastName;

  /// Vrai si la requête porte au moins un contact — le service répond sinon
  /// « Un email ou un numéro de téléphone est obligatoire ».
  bool get hasContact =>
      (email?.isNotEmpty ?? false) || (phone?.isNotEmpty ?? false);

  JsonMap toJson() => <String, Object?>{
    'password': password,
    'email': ?email,
    'phone': ?phone,
    'firstName': ?firstName,
    'lastName': ?lastName,
  };
}

/// Compte tel que `POST /auth/register` le renvoie — jamais complet, jamais actif.
class RegisteredAccount {
  const RegisteredAccount({
    required this.id,
    required this.status,
    this.email,
    this.phone,
  });

  factory RegisteredAccount.fromJson(JsonMap json) => RegisteredAccount(
    id: json['id'] as String? ?? '',
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    status: json['status'] as String? ?? 'pending',
  );

  final String id;
  final String? email;
  final String? phone;

  /// `pending` à la création : le compte ne pourra pas se connecter avant
  /// vérification (scénario 1.2).
  final String status;

  /// Destinataire du code de vérification : celui des deux contacts qui a été
  /// fourni. Le téléphone prime, comme côté service.
  String? get verificationTarget => phone ?? email;

  bool get isPending => status == 'pending';
}

/// `POST /auth/login`.
class LoginRequest {
  const LoginRequest({required this.email, required this.password});

  final String email;
  final String password;

  JsonMap toJson() => <String, Object?>{'email': email, 'password': password};
}

/// `POST /auth/forgot-password`.
class ForgotPasswordRequest {
  const ForgotPasswordRequest({required this.email});

  final String email;

  JsonMap toJson() => <String, Object?>{'email': email};
}

/// Accusé de la demande de réinitialisation.
///
/// Le message est **identique** que le compte existe ou non : l'écran ne doit rien
/// en déduire, et enchaîne systématiquement sur la saisie du jeton (FR-010).
class PasswordResetRequestResult {
  const PasswordResetRequestResult({required this.message, this.devToken});

  factory PasswordResetRequestResult.fromJson(JsonMap json) =>
      PasswordResetRequestResult(
        message: json['message'] as String? ?? '',
        devToken: json['devToken'] as String?,
      );

  final String message;

  /// Renseigné **uniquement** en environnement de développement
  /// (`AUTH_EXPOSE_DEV_CODES=true`) : sans transport email, c'est le seul moyen de
  /// dérouler le scénario 1.7. Ne jamais l'afficher en production — il n'y est
  /// d'ailleurs jamais présent.
  final String? devToken;
}

/// `POST /auth/reset-password`.
class ResetPasswordRequest {
  const ResetPasswordRequest({required this.token, required this.password});

  final String token;
  final String password;

  JsonMap toJson() => <String, Object?>{'token': token, 'password': password};
}

/// `POST /auth/logout` — le jeton de renouvellement ferme **la** bonne session.
///
/// Sans lui, le service se rabat sur la session portée par le jeton d'accès : la
/// déconnexion reste effective, mais peut viser une autre session que celle voulue.
class LogoutRequest {
  const LogoutRequest({this.refreshToken});

  final String? refreshToken;

  JsonMap toJson() => <String, Object?>{'refreshToken': ?refreshToken};
}
