// Conditions d'affichage du bouton « Laisser un avis » (data-model §6, T221).
//
// Quatre conditions, toutes calculables localement : mission `completed` ou
// `closed`, je suis le client, aucun avis de moi, et la fenêtre de dépôt en
// vigueur n'est pas écoulée. La fenêtre court depuis la date d'entrée en
// `completed` — lue dans l'HISTORIQUE de la mission, pas dans `scheduledAt` —
// et dure `reviewsWindowDays`, le réglage du service (porte G3).
//
// Le service reste l'autorité : si l'historique est muet sur l'entrée en
// `completed`, le bouton s'affiche et c'est le 400 « fenêtre écoulée » qui
// tranchera — cacher l'action sur un doute priverait un client dans son bon
// droit.

import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';

/// Verdict local — [remaining] vaut `null` quand la fenêtre n'a pas pu être
/// datée (historique muet) : le temps restant ne s'affiche pas, l'action si.
class ReviewEligibility {
  const ReviewEligibility({required this.canSubmit, this.remaining});

  static const ReviewEligibility none = ReviewEligibility(canSubmit: false);

  final bool canSubmit;
  final Duration? remaining;
}

ReviewEligibility reviewEligibilityFor({
  required MissionStatus status,
  required bool isClient,
  required bool alreadyReviewed,
  required DateTime? completedAt,
  required Duration window,
  required DateTime now,
}) {
  final bool ratableStatus =
      status == MissionStatus.completed || status == MissionStatus.closed;
  if (!ratableStatus || !isClient || alreadyReviewed) {
    return ReviewEligibility.none;
  }
  if (completedAt == null) {
    return const ReviewEligibility(canSubmit: true);
  }
  final Duration remaining = completedAt.add(window).difference(now);
  return remaining > Duration.zero
      ? ReviewEligibility(canSubmit: true, remaining: remaining)
      : ReviewEligibility.none;
}

/// « Il vous reste 3 jours », « Il vous reste 5 heures », « Dernières heures ».
String remainingWindowLabel(Duration remaining) {
  if (remaining.inDays >= 2) {
    return 'Il vous reste ${remaining.inDays} jours pour noter cette mission.';
  }
  if (remaining.inDays == 1) {
    return 'Il vous reste 1 jour pour noter cette mission.';
  }
  if (remaining.inHours >= 1) {
    return 'Il vous reste ${remaining.inHours} heure(s) pour noter cette '
        'mission.';
  }
  return 'Dernières minutes pour noter cette mission.';
}
