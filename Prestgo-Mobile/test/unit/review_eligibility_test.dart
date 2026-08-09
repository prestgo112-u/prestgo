// T221 — Conditions d'affichage du bouton « Laisser un avis » (data-model §6).
//
// Quatre conditions locales : statut `completed` ou `closed`, être le client,
// aucun avis de moi, fenêtre non écoulée — datée par l'entrée en `completed`
// de l'HISTORIQUE et dimensionnée par le réglage `reviewsWindowDays`.
// Historique muet → l'action s'affiche sans temps restant : le service reste
// l'autorité, cacher sur un doute priverait un client dans son bon droit.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_history.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';
import 'package:prestgo_mobile/features/reviews/domain/review_eligibility.dart';

import '../support/fixtures.dart';

final DateTime kNow = DateTime.utc(2026, 8, 1, 12);
const Duration kWindow = Duration(days: 14);

ReviewEligibility eligibility({
  MissionStatus status = MissionStatus.completed,
  bool isClient = true,
  bool alreadyReviewed = false,
  DateTime? completedAt,
  Duration window = kWindow,
}) => reviewEligibilityFor(
  status: status,
  isClient: isClient,
  alreadyReviewed: alreadyReviewed,
  completedAt: completedAt ?? kNow.subtract(const Duration(days: 2)),
  window: window,
  now: kNow,
);

void main() {
  group('Les quatre conditions', () {
    test('toutes réunies : action affichée, temps restant calculé', () {
      final ReviewEligibility verdict = eligibility();

      expect(verdict.canSubmit, isTrue);
      expect(verdict.remaining, const Duration(days: 12));
    });

    test('une mission clôturée se note encore', () {
      expect(eligibility(status: MissionStatus.closed).canSubmit, isTrue);
    });

    test('statut non terminal : rien', () {
      expect(eligibility(status: MissionStatus.confirmed).canSubmit, isFalse);
      expect(eligibility(status: MissionStatus.inProgress).canSubmit, isFalse);
      expect(eligibility(status: MissionStatus.cancelled).canSubmit, isFalse);
    });

    test('pas le client : rien — le prestataire ne note pas (9.2)', () {
      expect(eligibility(isClient: false).canSubmit, isFalse);
    });

    test('avis déjà déposé : action retirée (9.3)', () {
      expect(eligibility(alreadyReviewed: true).canSubmit, isFalse);
    });
  });

  group('La fenêtre', () {
    test('écoulée : action retirée', () {
      final ReviewEligibility verdict = eligibility(
        completedAt: kNow.subtract(const Duration(days: 15)),
      );
      expect(verdict.canSubmit, isFalse);
    });

    test('expire à l’instant même : retirée aussi', () {
      final ReviewEligibility verdict = eligibility(
        completedAt: kNow.subtract(kWindow),
      );
      expect(verdict.canSubmit, isFalse);
    });

    test('la durée vient du RÉGLAGE, pas d’une constante : à 3 jours, une '
        'mission de 5 jours n’est plus notable', () {
      final ReviewEligibility verdict = eligibility(
        completedAt: kNow.subtract(const Duration(days: 5)),
        window: const Duration(days: 3),
      );
      expect(verdict.canSubmit, isFalse);
    });

    test('historique muet : l’action s’affiche, sans temps restant — le '
        'service tranchera', () {
      final ReviewEligibility verdict = reviewEligibilityFor(
        status: MissionStatus.completed,
        isClient: true,
        alreadyReviewed: false,
        completedAt: null,
        window: kWindow,
        now: kNow,
      );
      expect(verdict.canSubmit, isTrue);
      expect(verdict.remaining, isNull);
    });
  });

  group('La date vient de l’HISTORIQUE', () {
    test(
      'completedAt est l’entrée `completed` de la frise, pas scheduledAt',
      () {
        final MissionHistory history = MissionHistory.fromJson(
          JsonMap.of(fixtureData('missions/history', 'completedTimeline')),
        );

        // La capture porte une entrée `completed` datée : c'est ELLE qui ouvre
        // la fenêtre.
        final DateTime? completedAt = history.completedAt;
        expect(completedAt, isNotNull);

        final ReviewEligibility verdict = reviewEligibilityFor(
          status: MissionStatus.completed,
          isClient: true,
          alreadyReviewed: false,
          completedAt: completedAt,
          window: kWindow,
          now: completedAt!.add(const Duration(days: 1)),
        );
        expect(verdict.canSubmit, isTrue);
        expect(verdict.remaining, const Duration(days: 13));
      },
    );
  });

  group('Libellé du temps restant', () {
    test('jours, jour, heures, minutes', () {
      expect(
        remainingWindowLabel(const Duration(days: 12)),
        'Il vous reste 12 jours pour noter cette mission.',
      );
      expect(
        remainingWindowLabel(const Duration(days: 1, hours: 3)),
        'Il vous reste 1 jour pour noter cette mission.',
      );
      expect(
        remainingWindowLabel(const Duration(hours: 5)),
        'Il vous reste 5 heure(s) pour noter cette mission.',
      );
      expect(
        remainingWindowLabel(const Duration(minutes: 40)),
        'Dernières minutes pour noter cette mission.',
      );
    });
  });
}
