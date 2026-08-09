// Exception **unique** exposée aux dépôts et aux écrans.
//
// Porte G2 : aucun écran, aucun dépôt ne teste un code HTTP — seuls les prédicats
// ci-dessous sont utilisés. La conversion d'une erreur réseau ou d'une réponse du
// service en `ApiException` a lieu dans un seul endroit : `EnvelopeInterceptor`.

import 'package:prestgo_mobile/core/api/api_envelope.dart';

/// Messages de repli, employés quand le service n'en fournit aucun d'affichable.
///
/// Voir contracts/api-envelope.md §4.
abstract final class ApiFallbackMessages {
  static const String network = 'Connexion impossible. Vérifiez votre réseau.';
  static const String server = 'Le service est momentanément indisponible.';
  static const String rateLimited =
      'Trop de tentatives. Patientez un instant avant de réessayer.';
  static const String unknown = 'Une erreur est survenue. Réessayez.';
  static const String cancelled = 'Requête interrompue.';

  /// `Invalid credentials` est volontairement ambigu côté service : il ne dit pas
  /// si c'est l'email ou le mot de passe. Le message affiché l'est aussi.
  static const String invalidCredentials = 'Email ou mot de passe incorrect.';

  /// `Account is not active` : l'écran propose deux issues (vérifier / support).
  static const String accountNotActive =
      'Ce compte n’est pas encore utilisable.';
}

/// Messages techniques du service qui ne doivent **jamais** être affichés tels
/// quels, associés à leur formulation destinée à l'utilisateur.
///
/// Tous les autres messages métier sont affichés tels quels — y compris ceux qui
/// contiennent un nombre interpolé, que l'application serait incapable de
/// reconstruire fidèlement (FR-088).
const Map<String, String> _messageOverrides = <String, String>{
  'Invalid credentials': ApiFallbackMessages.invalidCredentials,
  'Account is not active': ApiFallbackMessages.accountNotActive,
  'Bearer token required': ApiFallbackMessages.unknown,
  'Invalid access token': ApiFallbackMessages.unknown,
};

/// Nature d'un échec, indépendante du code HTTP.
enum ApiFailureKind {
  /// Aucune réponse : coupure, DNS, délai dépassé.
  network,

  /// Requête annulée par l'application (changement d'écran).
  cancelled,

  /// Le service a répondu.
  response,
}

/// Erreur applicative unique.
class ApiException implements Exception {
  const ApiException({
    required this.message,
    required this.kind,
    this.statusCode,
    this.errors = const <ApiErrorDetail>[],
    this.correlationId,
    this.rawMessage,
  });

  /// Échec sans réponse du service.
  const ApiException.network({this.correlationId})
    : message = ApiFallbackMessages.network,
      kind = ApiFailureKind.network,
      statusCode = null,
      errors = const <ApiErrorDetail>[],
      rawMessage = null;

  /// Requête abandonnée par l'application.
  const ApiException.cancelled()
    : message = ApiFallbackMessages.cancelled,
      kind = ApiFailureKind.cancelled,
      statusCode = null,
      errors = const <ApiErrorDetail>[],
      correlationId = null,
      rawMessage = null;

  /// Construit l'exception à partir d'une réponse du service.
  ///
  /// [body] est le corps décodé ; il respecte l'enveloppe même sur les erreurs non
  /// prévues (le filtre d'exception du service est global). Un corps illisible —
  /// page d'erreur d'un intermédiaire, réponse tronquée — retombe sur le message de
  /// repli correspondant au code.
  factory ApiException.fromResponse({required int statusCode, Object? body}) {
    JsonMap? json;
    if (body is Map<Object?, Object?>) {
      json = body.cast<String, Object?>();
    }

    final ApiEnvelope<void> envelope = json == null
        ? const ApiEnvelope<void>(success: false)
        : ApiEnvelope<void>.fromJson(json, parseNothing());

    return ApiException(
      statusCode: statusCode,
      kind: ApiFailureKind.response,
      message: _displayMessage(statusCode, envelope.message),
      rawMessage: envelope.message,
      errors: envelope.errors,
      correlationId: envelope.meta?.correlationId,
    );
  }

  /// Message destiné à l'utilisateur, déjà assaini.
  final String message;

  final ApiFailureKind kind;

  /// `null` lorsque le service n'a pas répondu.
  final int? statusCode;

  final List<ApiErrorDetail> errors;

  /// Identifiant de corrélation, joint au rapport d'incident (SC-010).
  final String? correlationId;

  /// Message brut du service, conservé pour le rapport d'incident et les tests.
  ///
  /// Ne jamais l'afficher : [message] est la version assainie.
  final String? rawMessage;

  // --- Prédicats — seule façon autorisée de discriminer une erreur ---------------

  /// Aucune réponse reçue.
  bool get isNetwork => kind == ApiFailureKind.network;

  /// Requête annulée par l'application.
  bool get isCancelled => kind == ApiFailureKind.cancelled;

  /// L'utilisateur peut corriger sa saisie et réessayer (400, 409, 422).
  bool get isUserFixable =>
      statusCode == 400 || statusCode == 409 || statusCode == 422;

  /// Session absente ou expirée — traitée par l'intercepteur, pas par les écrans.
  bool get isAuth => statusCode == 401;

  bool get isForbidden => statusCode == 403;

  bool get isNotFound => statusCode == 404;

  /// Débit dépassé : message d'attente et désactivation temporaire, **jamais** de
  /// rejeu (porte G4).
  bool get isRateLimited => statusCode == 429;

  bool get isServer {
    final int? code = statusCode;
    return code != null && code >= 500;
  }

  /// Échec susceptible de disparaître à l'identique : coupure réseau ou passerelle
  /// en défaut. Seule catégorie que la politique de rejeu accepte de réessayer.
  bool get isTransient =>
      isNetwork || statusCode == 502 || statusCode == 503 || statusCode == 504;

  /// Conflit métier — doublon, requête identique en cours.
  bool get isConflict => statusCode == 409;

  /// Vrai si le compte n'est pas encore utilisable (message ambigu volontaire).
  bool get isAccountNotActive => rawMessage == 'Account is not active';

  /// Vrai si le compte n'a pas de profil prestataire : l'écran renvoie alors au
  /// parcours de création de profil.
  bool get hasNoProviderProfile =>
      isForbidden && rawMessage == "Ce compte n'a pas de profil prestataire";

  // --- Accès aux erreurs de champ -----------------------------------------------

  /// Message de validation associé à [field], ou `null`.
  ///
  /// Accepte le chemin complet (`slots.1.startTime`) tel que le service l'émet.
  String? messageForField(String field) {
    for (final ApiErrorDetail error in errors) {
      if (error.field == field) {
        return error.message;
      }
    }
    return null;
  }

  /// Toutes les erreurs portant un `field`, indexées par champ.
  ///
  /// Les erreurs sans `field` (conflits métier) en sont absentes : elles relèvent
  /// de la bannière de formulaire, alimentée par [message].
  Map<String, String> get fieldMessages => <String, String>{
    for (final ApiErrorDetail error in errors)
      if (error.field case final String field) field: error.message,
  };

  /// Vrai si au moins une erreur désigne un champ.
  bool get hasFieldErrors =>
      errors.any((ApiErrorDetail error) => error.field != null);

  @override
  String toString() =>
      'ApiException($statusCode, ${kind.name}, "$message"'
      '${correlationId == null ? '' : ', cid: $correlationId'})';
}

/// Assainit le message du service selon le §4 du contrat.
String _displayMessage(int statusCode, String? serviceMessage) {
  if (serviceMessage != null) {
    final String? override = _messageOverrides[serviceMessage];
    if (override != null) {
      return override;
    }
    if (serviceMessage.trim().isNotEmpty && statusCode != 429) {
      return serviceMessage;
    }
  }

  if (statusCode == 429) {
    return ApiFallbackMessages.rateLimited;
  }
  if (statusCode >= 500) {
    return ApiFallbackMessages.server;
  }
  return ApiFallbackMessages.unknown;
}
