// Les six réglages lus auprès du service au démarrage (porte G3).
//
// Voir contracts/settings-and-limits.md §1. Les valeurs de repli ne servent **que**
// si l'appel échoue ; elles ne sont jamais la source de vérité une fois la route
// jointe. Aucun écran ne recopie ces valeurs dans une constante.

import 'package:prestgo_mobile/core/api/api_envelope.dart';

class PublicSettings {
  const PublicSettings({
    required this.missionMinLeadTimeMinutes,
    required this.missionCancellationNoticeHours,
    required this.missionStartWindowMinutes,
    required this.missionPendingExpiryHours,
    required this.missionAutoCloseDays,
    required this.reviewsWindowDays,
    required this.isFallback,
  });

  /// Lit la réponse du service ; toute clé absente retombe sur son repli.
  factory PublicSettings.fromJson(JsonMap json) => PublicSettings(
    missionMinLeadTimeMinutes:
        _asInt(json['missionMinLeadTimeMinutes']) ??
        fallback.missionMinLeadTimeMinutes,
    missionCancellationNoticeHours:
        _asInt(json['missionCancellationNoticeHours']) ??
        fallback.missionCancellationNoticeHours,
    missionStartWindowMinutes:
        _asInt(json['missionStartWindowMinutes']) ??
        fallback.missionStartWindowMinutes,
    missionPendingExpiryHours:
        _asInt(json['missionPendingExpiryHours']) ??
        fallback.missionPendingExpiryHours,
    missionAutoCloseDays:
        _asInt(json['missionAutoCloseDays']) ?? fallback.missionAutoCloseDays,
    reviewsWindowDays:
        _asInt(json['reviewsWindowDays']) ?? fallback.reviewsWindowDays,
    isFallback: false,
  );

  /// Valeurs employées tant que le service n'a pas répondu.
  static const PublicSettings fallback = PublicSettings(
    missionMinLeadTimeMinutes: 60,
    missionCancellationNoticeHours: 6,
    missionStartWindowMinutes: 120,
    missionPendingExpiryHours: 24,
    missionAutoCloseDays: 7,
    reviewsWindowDays: 14,
    isFallback: true,
  );

  /// Délai minimum entre maintenant et le début d'une intervention (FR-032).
  final int missionMinLeadTimeMinutes;

  /// En deçà, une annulation est signalée comme tardive (FR-045).
  final int missionCancellationNoticeHours;

  /// Fenêtre d'activation du bouton « Démarrer » (FR-042).
  final int missionStartWindowMinutes;

  /// Délai avant expiration d'une demande en attente (FR-043).
  final int missionPendingExpiryHours;

  /// Délai de clôture automatique d'une mission terminée.
  final int missionAutoCloseDays;

  /// Fenêtre de dépôt d'un avis après la fin de la mission (FR-070).
  final int reviewsWindowDays;

  /// Vrai tant que ces valeurs viennent du repli et non du service.
  ///
  /// Permet à un écran de savoir qu'il affiche une estimation — le message d'erreur
  /// du service, interpolé avec la valeur réellement en vigueur, prime toujours.
  final bool isFallback;

  Duration get minLeadTime => Duration(minutes: missionMinLeadTimeMinutes);
  Duration get cancellationNotice =>
      Duration(hours: missionCancellationNoticeHours);
  Duration get startWindow => Duration(minutes: missionStartWindowMinutes);
  Duration get pendingExpiry => Duration(hours: missionPendingExpiryHours);
  Duration get autoCloseDelay => Duration(days: missionAutoCloseDays);
  Duration get reviewsWindow => Duration(days: reviewsWindowDays);

  @override
  bool operator ==(Object other) =>
      other is PublicSettings &&
      other.missionMinLeadTimeMinutes == missionMinLeadTimeMinutes &&
      other.missionCancellationNoticeHours == missionCancellationNoticeHours &&
      other.missionStartWindowMinutes == missionStartWindowMinutes &&
      other.missionPendingExpiryHours == missionPendingExpiryHours &&
      other.missionAutoCloseDays == missionAutoCloseDays &&
      other.reviewsWindowDays == reviewsWindowDays &&
      other.isFallback == isFallback;

  @override
  int get hashCode => Object.hash(
    missionMinLeadTimeMinutes,
    missionCancellationNoticeHours,
    missionStartWindowMinutes,
    missionPendingExpiryHours,
    missionAutoCloseDays,
    reviewsWindowDays,
    isFallback,
  );

  @override
  String toString() =>
      'PublicSettings(lead: $missionMinLeadTimeMinutes min, '
      'notice: $missionCancellationNoticeHours h, '
      'start: $missionStartWindowMinutes min, '
      'expiry: $missionPendingExpiryHours h, '
      'autoClose: $missionAutoCloseDays j, '
      'reviews: $reviewsWindowDays j, repli: $isFallback)';
}

int? _asInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};
