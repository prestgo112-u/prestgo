// T220 — Contrat des avis (opérations 45 à 47).
//
// Les pièges de ces routes :
//   • le **409 du dépôt est un succès** : « déjà noté » = objectif atteint, le
//     dépôt rend `null` et aucun écran n'affiche d'erreur (FR-071) ;
//   • le 400 « fenêtre écoulée » et le 403 « prestataire » portent leur
//     message — l'écran les affiche tels quels, mais ne doit jamais les
//     provoquer (l'éligibilité locale les évite, T221) ;
//   • le doublon de signalement (409) devient la mention « déjà signalé »
//     (scénario 9.4) — jamais une erreur brute.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/features/reviews/data/review_repository.dart';
import 'package:prestgo_mobile/features/reviews/domain/review.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const String kMissionId = 'a75221c8-03a0-4dc7-a4c0-c0047ad0713c';
const String kReviewId = '8b7c6d5e-4f3a-4b2c-8d1e-0f9a8b7c6d5e';

ApiHarness harnessFor(String file, String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'reviews/$file',
    caseName,
  );
  return ApiHarness.always(status, body);
}

ReviewRepository repositoryOn(ApiHarness harness) =>
    ReviewRepository(harness.client);

void main() {
  group('Opération 45 — POST /missions/{id}/review', () {
    test(
      '201 — l’avis créé, la note et le commentaire dans le corps',
      () async {
        final ApiHarness harness = harnessFor('submit', 'created');

        final Review? review = await repositoryOn(harness).submitReview(
          kMissionId,
          rating: 5,
          comment: 'Travail impeccable, ponctuel et soigneux.',
        );

        expect(harness.lastCall.method, 'POST');
        expect(harness.lastCall.path, '/missions/$kMissionId/review');
        expect(harness.lastBody['rating'], 5);
        expect(
          harness.lastBody['comment'],
          'Travail impeccable, ponctuel et soigneux.',
        );
        expect(review?.status, ReviewStatus.published);
        expect(review?.mission?.providerName, 'Kofi Plomberie');
      },
    );

    test('409 — déjà noté : TRAITÉ COMME UN SUCCÈS, aucun jet', () async {
      final Review? review = await repositoryOn(
        harnessFor('submit', 'duplicate'),
      ).submitReview(kMissionId, rating: 4);

      expect(review, isNull);
    });

    test('400 — fenêtre écoulée : le message du service, tel quel', () async {
      await expectLater(
        repositoryOn(
          harnessFor('submit', 'windowClosed'),
        ).submitReview(kMissionId, rating: 4),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            'La fenêtre de dépôt d’avis est écoulée pour cette mission',
          ),
        ),
      );
    });

    test('403 — le prestataire ne note pas', () async {
      await expectLater(
        repositoryOn(
          harnessFor('submit', 'forbiddenProvider'),
        ).submitReview(kMissionId, rating: 5),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.isForbidden, 'isForbidden', isTrue)
              .having(
                (ApiException e) => e.message,
                'message',
                'Seul le client de la mission peut déposer un avis',
              ),
        ),
      );
    });

    test('gardes locales : note hors bornes et commentaire trop long ne '
        'partent jamais', () async {
      final ApiHarness harness = harnessFor('submit', 'created');
      final ReviewRepository repository = repositoryOn(harness);

      await expectLater(
        repository.submitReview(kMissionId, rating: 0),
        throwsArgumentError,
      );
      await expectLater(
        repository.submitReview(kMissionId, rating: 6),
        throwsArgumentError,
      );
      await expectLater(
        repository.submitReview(kMissionId, rating: 5, comment: 'a' * 1001),
        throwsArgumentError,
      );
      expect(harness.callCount, 0);
    });
  });

  group('Opération 46 — GET /me/reviews', () {
    test('paginé — les quatre états de modération arrivent typés', () async {
      final ApiHarness harness = harnessFor('my_reviews', 'firstPage');

      final PagedPage<Review> page = await repositoryOn(
        harness,
      ).myReviews(page: 1, limit: 20);

      expect(harness.lastCall.path, '/me/reviews');
      expect(page.meta?.total, 3);
      expect(page.items, hasLength(3));
      expect(page.items[0].status, ReviewStatus.published);
      expect(page.items[1].status, ReviewStatus.reported);
      expect(page.items[2].status, ReviewStatus.hidden);
      // Un avis signalé RESTE visible ; un avis retiré est une mention.
      expect(page.items[1].isWithdrawn, isFalse);
      expect(page.items[2].isWithdrawn, isTrue);
    });
  });

  group('Opération 47 — POST /reviews/{id}/report', () {
    test('signalement transmis, le motif dans le corps', () async {
      final ApiHarness harness = harnessFor('report', 'reported');

      final ReportResult result = await repositoryOn(
        harness,
      ).reportReview(kReviewId, reason: 'Propos injurieux envers le client.');

      expect(harness.lastCall.path, '/reviews/$kReviewId/report');
      expect(harness.lastBody['reason'], 'Propos injurieux envers le client.');
      expect(result.outcome, ReportOutcome.reported);
      expect(result.message, 'Signalement transmis à la modération');
    });

    test(
      '409 — doublon : la mention « déjà signalé », pas un jet (9.4)',
      () async {
        final ReportResult result = await repositoryOn(
          harnessFor('report', 'alreadyReported'),
        ).reportReview(kReviewId, reason: 'Propos injurieux.');

        expect(result.alreadyReported, isTrue);
        expect(result.message, 'Vous avez déjà signalé cet avis');
      },
    );

    test('403 — son propre avis : le message du service remonte', () async {
      await expectLater(
        repositoryOn(
          harnessFor('report', 'ownReview'),
        ).reportReview(kReviewId, reason: 'Je regrette mon avis.'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.isForbidden,
            'isForbidden',
            isTrue,
          ),
        ),
      );
    });

    test('garde locale : motif trop court, rien ne part', () async {
      final ApiHarness harness = harnessFor('report', 'reported');

      await expectLater(
        repositoryOn(harness).reportReview(kReviewId, reason: 'ab'),
        throwsArgumentError,
      );
      expect(harness.callCount, 0);
    });
  });
}
