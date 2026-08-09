// Validateurs de saisie — confort de saisie, jamais décision (porte G1).
//
// Chaque plafond vient de `app_constants.dart` : aucun écran ne redéclare une
// borne. Ces contrôles évitent un aller-retour réseau inutile ; en cas de
// désaccord, **le message du service prime** (FR-090, SC-013).
//
// Convention Flutter : `null` signifie « valide », une chaîne est le message
// affiché sous le champ.

import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

abstract final class Validators {
  // --- Identité et authentification ---------------------------------------------

  static String? email(String? value, {bool required = true}) {
    final String input = value?.trim() ?? '';
    if (input.isEmpty) {
      return required ? 'Renseignez votre adresse email.' : null;
    }
    if (!AuthLimits.emailPattern.hasMatch(input)) {
      return 'Adresse email invalide.';
    }
    return null;
  }

  static String? phone(String? value, {bool required = true}) {
    final String input = value?.trim() ?? '';
    if (input.isEmpty) {
      return required ? 'Renseignez votre numéro de téléphone.' : null;
    }
    if (!AuthLimits.phonePattern.hasMatch(input)) {
      return 'Numéro de téléphone invalide.';
    }
    return null;
  }

  /// Mot de passe : 8 à 128 caractères, au moins une lettre **et** un chiffre.
  static String? password(String? value) {
    final String input = value ?? '';
    if (input.isEmpty) {
      return 'Renseignez un mot de passe.';
    }
    if (input.length < AuthLimits.passwordMinLength) {
      return 'Au moins ${AuthLimits.passwordMinLength} caractères.';
    }
    if (input.length > AuthLimits.passwordMaxLength) {
      return 'Au plus ${AuthLimits.passwordMaxLength} caractères.';
    }
    final bool hasLetter = input.contains(RegExp('[A-Za-zÀ-ÿ]'));
    final bool hasDigit = input.contains(RegExp('[0-9]'));
    if (!hasLetter || !hasDigit) {
      return 'Le mot de passe doit contenir au moins une lettre et un chiffre.';
    }
    return null;
  }

  /// Confirmation de mot de passe — contrôle **local** : le service ne reçoit
  /// jamais ce second champ.
  static String? passwordConfirmation(String? value, String password) {
    if (value == null || value.isEmpty) {
      return 'Confirmez votre mot de passe.';
    }
    if (value != password) {
      return 'Les deux mots de passe ne correspondent pas.';
    }
    return null;
  }

  /// Code de vérification : exactement 6 chiffres.
  static String? verificationCode(String? value) {
    final String input = value?.trim() ?? '';
    if (input.length != AuthLimits.verificationCodeLength) {
      return 'Le code comporte ${AuthLimits.verificationCodeLength} chiffres.';
    }
    if (!RegExp(r'^\d+$').hasMatch(input)) {
      return 'Le code ne contient que des chiffres.';
    }
    return null;
  }

  /// Jeton de réinitialisation, saisi ou collé (aucun lien profond, écart n°3).
  static String? passwordResetToken(String? value) {
    final String input = value?.trim() ?? '';
    if (input.isEmpty) {
      return 'Collez le jeton reçu par email.';
    }
    if (input.length < AuthLimits.passwordResetTokenMinLength) {
      return 'Ce jeton semble incomplet.';
    }
    return null;
  }

  // --- Longueurs génériques -----------------------------------------------------

  /// Champ texte obligatoire, borné.
  static String? text(
    String? value, {
    required String label,
    int minLength = 1,
    required int maxLength,
    bool required = true,
  }) {
    final String input = value?.trim() ?? '';
    if (input.isEmpty) {
      return required ? '$label est obligatoire.' : null;
    }
    if (input.length < minLength) {
      return '$label : au moins $minLength caractères.';
    }
    if (input.length > maxLength) {
      return '$label : au plus $maxLength caractères.';
    }
    return null;
  }

  /// Motif de refus, d'annulation ou de signalement : 3 à 500 caractères.
  static String? reason(String? value) => text(
    value,
    label: 'Le motif',
    minLength: ContentLimits.reasonMinLength,
    maxLength: ContentLimits.reasonMaxLength,
  );

  /// Instructions de réservation — facultatives, 500 caractères au plus.
  static String? bookingInstructions(String? value) => text(
    value,
    label: 'Les instructions',
    maxLength: ContentLimits.bookingInstructionsMaxLength,
    required: false,
  );

  /// Corps d'un message : 1 à 4000 caractères.
  /// La borne basse du service est 1 caractère — c'est aussi le défaut de [text].
  static String? messageBody(String? value) => text(
    value,
    label: 'Le message',
    maxLength: ContentLimits.messageMaxLength,
  );

  /// Commentaire d'avis — facultatif, 1000 caractères au plus.
  static String? reviewComment(String? value) => text(
    value,
    label: 'Le commentaire',
    maxLength: ContentLimits.reviewCommentMaxLength,
    required: false,
  );

  // --- Nombres ------------------------------------------------------------------

  static String? integerInRange(
    Object? value, {
    required String label,
    required int min,
    required int max,
    bool required = true,
  }) {
    final int? parsed = switch (value) {
      final int v => v,
      final num v => v.toInt(),
      final String v => int.tryParse(v.trim()),
      _ => null,
    };
    if (parsed == null) {
      if (!required) {
        return null;
      }
      return '$label est obligatoire.';
    }
    if (parsed < min || parsed > max) {
      return '$label doit être compris entre $min et $max.';
    }
    return null;
  }

  static String? price(Object? value, {String label = 'Le prix'}) {
    final num? parsed = switch (value) {
      final num v => v,
      final String v => num.tryParse(v.trim().replaceAll(',', '.')),
      _ => null,
    };
    if (parsed == null) {
      return '$label est obligatoire.';
    }
    if (parsed < 0) {
      return '$label ne peut pas être négatif.';
    }
    return null;
  }

  /// Note d'avis : entier de 1 à 5.
  static String? rating(int? value) {
    if (value == null) {
      return 'Choisissez une note.';
    }
    if (value < 1 || value > 5) {
      return 'La note va de 1 à 5.';
    }
    return null;
  }

  // --- Agenda -------------------------------------------------------------------

  /// Heure `HH:MM`. Aucune conversion de fuseau n'est appliquée.
  static String? clockTime(String? value) {
    final String input = value?.trim() ?? '';
    if (input.isEmpty) {
      return 'Renseignez une heure.';
    }
    if (ClockTime.tryParse(input) == null) {
      return 'Heure attendue au format HH:MM.';
    }
    return null;
  }

  /// Créneau hebdomadaire : fin strictement après le début.
  static String? weeklySlot({
    required int weekday,
    required String startTime,
    required String endTime,
  }) {
    if (!Weekdays.isValid(weekday)) {
      return 'Jour invalide.';
    }
    final ClockTime? start = ClockTime.tryParse(startTime);
    final ClockTime? end = ClockTime.tryParse(endTime);
    if (start == null || end == null) {
      return 'Heures attendues au format HH:MM.';
    }
    if (end <= start) {
      return 'L’heure de fin doit suivre l’heure de début.';
    }
    return null;
  }

  /// Absence exceptionnelle : fin strictement après le début.
  static String? unavailability({
    required DateTime startAt,
    required DateTime endAt,
  }) {
    if (!endAt.isAfter(startAt)) {
      return 'La fin doit suivre le début.';
    }
    return null;
  }

  // --- Adresses -----------------------------------------------------------------

  /// Coordonnées : une adresse sans position ne peut pas servir de lieu
  /// d'intervention (FR-019).
  static String? coordinates({double? latitude, double? longitude}) {
    if (latitude == null || longitude == null) {
      return 'Placez l’adresse sur la carte.';
    }
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return 'Coordonnées invalides.';
    }
    return null;
  }

  // --- Fichiers -----------------------------------------------------------------

  /// Contrôle **avant l'envoi** du type et de la taille (R7).
  ///
  /// Le service rejette un dépassement après avoir reçu le fichier entier : le
  /// filtrer localement épargne un envoi long et faillible sur connexion mobile.
  static String? file({
    required String mimeType,
    required int sizeBytes,
    Set<String> acceptedMimeTypes = FileLimits.acceptedMimeTypes,
    int maxSizeBytes = FileLimits.maxSizeBytes,
  }) {
    if (!acceptedMimeTypes.contains(mimeType)) {
      return 'Format de fichier non accepté.';
    }
    if (sizeBytes > maxSizeBytes) {
      final int megabytes = maxSizeBytes ~/ (1024 * 1024);
      return 'Fichier trop volumineux (maximum $megabytes Mo).';
    }
    return null;
  }

  // --- Plafonds de collection ---------------------------------------------------

  /// Vrai quand un ajout doit être rendu **indisponible**, avec motif affiché,
  /// plutôt que refusé après saisie.
  static bool isAtCapacity(int currentCount, int maximum) =>
      currentCount >= maximum;

  static String capacityMessage(String what, int maximum) =>
      'Vous avez atteint la limite de $maximum $what.';
}
