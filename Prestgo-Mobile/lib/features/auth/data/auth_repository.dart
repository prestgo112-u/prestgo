// Opérations 1 à 8 de contracts/api-consumption.md.
//
// Une méthode par ligne du tableau, et rien d'autre : aucun écran ne joint le service
// directement. Ce qui n'apparaît pas ici :
//   • `POST /auth/refresh` (opération 5) — il appartient au socle, `AuthInterceptor`
//     en est le seul appelant. L'exposer ici ouvrirait la porte à un second
//     renouvellement en parallèle du sien, exactement ce que l'invariant 1 interdit.
//
// ⚠️ Le préfixe `/api/v1` est déjà dans la base configurée : aucun chemin ne le
// répète.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/features/auth/data/dto/auth_requests.dart';
import 'package:prestgo_mobile/features/auth/data/dto/otp_dto.dart';

class AuthRepository {
  const AuthRepository(this._client);

  final ApiClient _client;

  // --- 1. Inscription -----------------------------------------------------------

  /// `POST /auth/register` — le compte naît `pending`.
  ///
  /// Il faudra vérifier un contact pour l'activer : c'est l'appelant qui enchaîne
  /// sur [sendOtp], le service n'envoie pas de code à l'inscription.
  Future<RegisteredAccount> register(RegisterRequest request) async {
    final ApiEnvelope<RegisteredAccount> envelope = await _client
        .post<RegisteredAccount>(
          '/auth/register',
          body: request.toJson(),
          parse: parseObject<RegisteredAccount>(RegisteredAccount.fromJson),
        );
    return envelope.requireData;
  }

  // --- 2. Envoi d'un code -------------------------------------------------------

  /// `POST /auth/otp/send`.
  ///
  /// Réponse identique que le destinataire soit connu ou non : ne rien en déduire.
  Future<OtpChallenge> sendOtp({
    required String target,
    required OtpPurpose purpose,
  }) async {
    final ApiEnvelope<OtpChallenge> envelope = await _client.post<OtpChallenge>(
      '/auth/otp/send',
      body: SendOtpRequest(target: target, purpose: purpose).toJson(),
      parse: parseObject<OtpChallenge>(OtpChallenge.fromJson),
    );
    return envelope.requireData;
  }

  // --- 3. Vérification d'un code ------------------------------------------------

  /// `POST /auth/otp/verify` avec un motif de **vérification**.
  ///
  /// Deux méthodes distinctes plutôt qu'une seule, parce que cette route change de
  /// forme de réponse selon le motif : ici `{ verified, activated }`, dans
  /// [signInWithCode] un couple de jetons. Un seul point d'entrée obligerait chaque
  /// appelant à démêler les deux — c'est le type qui s'en charge.
  Future<OtpVerification> verifyContact({
    required String target,
    required String code,
    required OtpPurpose purpose,
  }) async {
    assert(
      purpose != OtpPurpose.login,
      'Motif `login` : passer par signInWithCode, la réponse est un couple de '
      'jetons et non { verified, activated }',
    );
    final ApiEnvelope<OtpVerification> envelope = await _client
        .post<OtpVerification>(
          '/auth/otp/verify',
          body: VerifyOtpRequest(
            target: target,
            code: code,
            purpose: purpose,
          ).toJson(),
          parse: parseObject<OtpVerification>(OtpVerification.fromJson),
        );
    return envelope.requireData;
  }

  /// `POST /auth/otp/verify` avec `purpose: login` — connexion sans mot de passe.
  ///
  /// Seul chemin de connexion d'un compte inscrit par téléphone seul : `/auth/login`
  /// n'accepte qu'un email. Un 401 signifie ici « code bon, mais aucun compte actif
  /// ne correspond », pas « code faux ».
  Future<AuthTokens> signInWithCode({
    required String target,
    required String code,
  }) async {
    final ApiEnvelope<AuthTokens> envelope = await _client.post<AuthTokens>(
      '/auth/otp/verify',
      body: VerifyOtpRequest(
        target: target,
        code: code,
        purpose: OtpPurpose.login,
      ).toJson(),
      parse: parseObject<AuthTokens>(AuthTokens.fromJson),
    );
    return envelope.requireData;
  }

  // --- 4. Connexion -------------------------------------------------------------

  /// `POST /auth/login`.
  Future<AuthTokens> signIn(LoginRequest request) async {
    final ApiEnvelope<AuthTokens> envelope = await _client.post<AuthTokens>(
      '/auth/login',
      body: request.toJson(),
      parse: parseObject<AuthTokens>(AuthTokens.fromJson),
    );
    return envelope.requireData;
  }

  // --- 6. Déconnexion -----------------------------------------------------------

  /// `POST /auth/logout`.
  ///
  /// L'en-tête d'autorisation est ajouté par le socle ; le jeton de renouvellement
  /// part **en plus** dans le corps, pour fermer précisément cette session-là.
  ///
  /// Ne lève pas : la déconnexion locale ne doit jamais dépendre du réseau
  /// (scénario 1.9). L'appelant purge dans tous les cas.
  Future<void> signOut({String? refreshToken}) async {
    await _client.post<void>(
      '/auth/logout',
      body: LogoutRequest(refreshToken: refreshToken).toJson(),
      parse: parseNothing(),
    );
  }

  // --- 7 et 8. Mot de passe oublié ----------------------------------------------

  /// `POST /auth/forgot-password`.
  ///
  /// Message neutre systématique : l'écran enchaîne toujours vers la saisie du
  /// jeton, sans jamais laisser entendre que l'adresse a été reconnue.
  Future<PasswordResetRequestResult> requestPasswordReset(String email) async {
    final ApiEnvelope<PasswordResetRequestResult> envelope = await _client
        .post<PasswordResetRequestResult>(
          '/auth/forgot-password',
          body: ForgotPasswordRequest(email: email).toJson(),
          parse: parseObject<PasswordResetRequestResult>(
            PasswordResetRequestResult.fromJson,
          ),
        );
    return envelope.requireData;
  }

  /// `POST /auth/reset-password`.
  ///
  /// Succès : **toutes** les sessions du compte tombent, y compris celle-ci.
  /// L'appelant purge et revient à la connexion.
  Future<String> resetPassword({
    required String token,
    required String password,
  }) async {
    final ApiEnvelope<void> envelope = await _client.post<void>(
      '/auth/reset-password',
      body: ResetPasswordRequest(token: token, password: password).toJson(),
      parse: parseNothing(),
    );
    return envelope.message ?? 'Mot de passe mis à jour.';
  }
}

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>(
      (Ref ref) => AuthRepository(ref.watch(apiClientProvider)),
    );
