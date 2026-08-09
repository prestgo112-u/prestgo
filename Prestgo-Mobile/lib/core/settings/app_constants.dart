// Plafonds de saisie et constantes applicatives — source **unique**.
//
// Voir contracts/settings-and-limits.md §2. Aucun de ces plafonds n'est redéclaré
// dans un écran : ils sont appliqués **avant l'envoi** (FR-090, SC-013).
//
// ⚠️ À ne pas confondre avec les six réglages de `PublicSettings`, lus auprès du
// service au démarrage (porte G3) : ce fichier ne contient que des valeurs vérifiées
// dans le code du service et non exposées par une route.

/// Constantes d'authentification.
abstract final class AuthLimits {
  /// Durée de vie du jeton d'accès (informative : le service fait foi).
  static const Duration accessTokenLifetime = Duration(minutes: 15);

  /// Durée de vie du jeton de renouvellement.
  static const Duration refreshTokenLifetime = Duration(days: 7);

  /// Longueur exacte du code de vérification.
  static const int verificationCodeLength = 6;

  /// Repli de durée de vie d'un code — la valeur `expiresInMinutes` reçue prime.
  static const Duration verificationCodeFallbackLifetime = Duration(
    minutes: 10,
  );

  /// Tentatives maximales sur un même code avant invalidation.
  static const int verificationMaxAttempts = 5;

  /// Délai minimal entre deux renvois de code.
  static const Duration verificationResendCooldown = Duration(minutes: 1);

  /// Durée de vie du jeton de réinitialisation de mot de passe.
  static const Duration passwordResetTokenLifetime = Duration(minutes: 30);

  static const int passwordMinLength = 8;
  static const int passwordMaxLength = 128;

  /// Longueur minimale du jeton de réinitialisation (64 caractères en pratique).
  static const int passwordResetTokenMinLength = 10;

  /// Format de téléphone accepté par le service.
  static final RegExp phonePattern = RegExp(r'^\+?[0-9\s-]{8,20}$');

  /// Contrôle de forme volontairement permissif : le service arbitre.
  static final RegExp emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
}

/// Plafonds de contenu.
abstract final class ContentLimits {
  static const int addressesPerAccount = 10;
  static const int zonesPerProvider = 15;
  static const int portfolioItems = 20;
  static const int weeklySlots = 50;
  static const int optionsPerBooking = 10;
  static const int attachmentsPerMessage = 3;

  static const int messageMinLength = 1;
  static const int messageMaxLength = 4000;

  static const int bookingInstructionsMaxLength = 500;
  static const int reviewCommentMaxLength = 1000;

  static const int reasonMinLength = 3;
  static const int reasonMaxLength = 500;

  /// Détails facultatifs d'une annulation de mission.
  static const int cancellationDetailsMaxLength = 1000;

  static const int providerBioMaxLength = 2000;
  static const int publicNameMinLength = 2;
  static const int publicNameMaxLength = 120;

  static const int serviceTitleMinLength = 3;
  static const int serviceTitleMaxLength = 150;
  static const int serviceDescriptionMaxLength = 1000;

  static const int packTitleMinLength = 2;
  static const int packTitleMaxLength = 150;
  static const int packDescriptionMaxLength = 2000;

  static const int packDurationMinMinutes = 5;
  static const int packDurationMaxMinutes = 1440;
  static const int optionDurationMinMinutes = 0;
  static const int optionDurationMaxMinutes = 1440;

  static const int experienceYearsMin = 0;
  static const int experienceYearsMax = 70;

  static const int addressLabelMaxLength = 50;
  static const int addressCityMaxLength = 80;
  static const int addressCommuneMaxLength = 80;
  static const int addressDetailsMaxLength = 255;

  static const int unavailabilityReasonMaxLength = 300;
  static const int portfolioTitleMaxLength = 120;
  static const int portfolioDescriptionMaxLength = 1000;

  static const int searchQueryMaxLength = 120;
}

/// Plafonds et types de fichier.
abstract final class FileLimits {
  /// Plafond du service : un dépassement est refusé **après** l'envoi complet, donc
  /// le filtrage est local et préalable (R7).
  static const int maxSizeBytes = 10 * 1024 * 1024;

  /// Cible de compression avant envoi.
  static const int compressionTargetBytes = 2 * 1024 * 1024;
  static const int compressionMaxDimension = 2000;

  static const Set<String> acceptedMimeTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
    'application/pdf',
    'text/plain',
    'text/csv',
  };

  /// Avatar, portfolio et réalisations : images uniquement (le service refuse le
  /// reste).
  static const Set<String> imageOnlyMimeTypes = <String>{
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  /// Nom du champ multipart attendu par `POST /files/upload`.
  static const String multipartFieldName = 'file';
}

/// Pagination et recherche.
abstract final class PaginationLimits {
  static const int defaultPageSize = 20;
  static const int maxPageSize = 100;

  /// Plafond spécifique à `GET /providers/search`.
  static const int maxSearchPageSize = 50;

  static const int firstPage = 1;

  static const double defaultRadiusKm = 10;
  static const double minRadiusKm = 1;
  static const double maxRadiusKm = 50;

  static const double minRating = 0;
  static const double maxRating = 5;
}

/// Idempotence et débits du service.
abstract final class RateLimits {
  static const Duration idempotencyKeyLifetime = Duration(minutes: 10);

  static const int bookingsPerHour = 10;
  static const int deviceRegistrationsPerDay = 30;
  static const int reviewReportsPerDay = 20;

  static const int loginsPerMinute = 10;

  /// Inscription, envoi de code, mot de passe oublié.
  static const int sensitiveAuthCallsPerMinute = 5;

  /// Renouvellement, vérification de code, changement de mot de passe.
  static const int refreshCallsPerMinute = 30;
}

/// Devise, semaine, formats.
abstract final class AppFormats {
  /// Devise unique — non portée par l'API (décision produit).
  static const String currencyCode = 'XOF';

  /// Locale des formats (montants, dates).
  static const String locale = 'fr_CI';

  /// Locale des libellés.
  static const String languageCode = 'fr';

  /// Le franc CFA n'a pas de sous-unité.
  static const int currencyDecimalDigits = 0;

  /// 0 = dimanche, 6 = samedi — convention du service pour l'agenda hebdomadaire.
  static const int firstWeekday = 0;
  static const int lastWeekday = 6;

  /// Les heures d'agenda sont des chaînes `HH:MM`, **jamais** converties de fuseau.
  static final RegExp timeOfDayPattern = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
}

/// Délais réseau.
abstract final class NetworkTimeouts {
  static const Duration connect = Duration(seconds: 10);
  static const Duration send = Duration(seconds: 30);
  static const Duration receive = Duration(seconds: 30);

  /// Envoi de fichier : le corps peut être volumineux malgré la compression.
  static const Duration upload = Duration(minutes: 2);
}
