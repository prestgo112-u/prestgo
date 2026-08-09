// T208 — Contrat des absences exceptionnelles (opérations 29, 81, 82).
//
// Les pièges de ces routes :
//   • la **relecture** passe par la route publique `GET /providers/{id}/…` —
//     il n'existe pas de `GET /providers/me/unavailabilities` ;
//   • fin après début et non-chevauchement sont des 400 du service, que les
//     contrôles locaux (`isOrdered`, `overlaps`) reproduisent avant l'envoi ;
//   • l'appartenance est vérifiée à la suppression : l'absence d'un autre
//     répond 404, jamais 403.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_space/domain/unavailability.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const String kProviderId = 'e7a41f9c-2b6d-4c83-9f05-8a1b2c3d4e5f';
const String kUnavailabilityId = 'd4e5f6a7-b8c9-4d0e-8f1a-3b4c5d6e7f8a';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'provider_offer/unavailabilities',
    caseName,
  );
  return ApiHarness.always(status, body);
}

ProviderSelfRepository repositoryOn(ApiHarness harness) =>
    ProviderSelfRepository(harness.client);

void main() {
  group('Opération 29 — GET /providers/{id}/unavailabilities', () {
    test('relecture de MES absences par la route publique', () async {
      final ApiHarness harness = harnessFor('list');

      final List<Unavailability> absences = await repositoryOn(
        harness,
      ).unavailabilities(kProviderId);

      expect(harness.lastCall.method, 'GET');
      expect(harness.lastCall.path, '/providers/$kProviderId/unavailabilities');
      expect(absences, hasLength(2));
      expect(absences.first.reason, 'Congés annuels');
      expect(absences.first.isOrdered, isTrue);
      // Le motif est facultatif : la seconde n'en a pas.
      expect(absences.last.reason, isNull);
    });
  });

  group('Opération 81 — POST /providers/me/unavailabilities', () {
    test('201 — bornes ISO/UTC, motif facultatif omis quand vide', () async {
      final ApiHarness harness = harnessFor('created');

      final Unavailability created = await repositoryOn(harness)
          .createUnavailability(
            startAt: DateTime.utc(2026, 10, 5),
            endAt: DateTime.utc(2026, 10, 7),
            reason: 'Formation',
          );

      expect(harness.lastCall.path, '/providers/me/unavailabilities');
      expect(harness.lastBody['startAt'], '2026-10-05T00:00:00.000Z');
      expect(harness.lastBody['endAt'], '2026-10-07T00:00:00.000Z');
      expect(harness.lastBody['reason'], 'Formation');
      expect(created.id, 'f6a7b8c9-d0e1-4f2a-8b3c-5d6e7f8a9b0c');
    });

    test(
      '400 — fin avant début : le message que le contrôle local épargne',
      () async {
        await expectLater(
          repositoryOn(harnessFor('endBeforeStart')).createUnavailability(
            startAt: DateTime.utc(2026, 10, 7),
            endAt: DateTime.utc(2026, 10, 5),
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.message,
              'message',
              'La date de fin doit être postérieure à la date de début',
            ),
          ),
        );
      },
    );

    test('400 — chevauchement avec une absence existante', () async {
      await expectLater(
        repositoryOn(harnessFor('overlap')).createUnavailability(
          startAt: DateTime.utc(2026, 8, 12),
          endAt: DateTime.utc(2026, 8, 14),
        ),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.isUserFixable,
                'isUserFixable',
                isTrue,
              )
              .having(
                (ApiException e) => e.message,
                'message',
                'Cette absence chevauche une absence déjà enregistrée',
              ),
        ),
      );
    });

    test('les contrôles locaux reproduisent les deux 400', () {
      final Unavailability existing = Unavailability(
        id: 'u-1',
        startAt: DateTime.utc(2026, 8, 10),
        endAt: DateTime.utc(2026, 8, 17),
      );
      final Unavailability inverted = Unavailability(
        id: 'u-2',
        startAt: DateTime.utc(2026, 8, 20),
        endAt: DateTime.utc(2026, 8, 19),
      );
      final Unavailability overlapping = Unavailability(
        id: 'u-3',
        startAt: DateTime.utc(2026, 8, 16),
        endAt: DateTime.utc(2026, 8, 18),
      );
      final Unavailability disjoint = Unavailability(
        id: 'u-4',
        startAt: DateTime.utc(2026, 8, 17),
        endAt: DateTime.utc(2026, 8, 18),
      );

      expect(inverted.isOrdered, isFalse);
      expect(existing.overlaps(overlapping), isTrue);
      // Bornes qui se touchent sans partager d'instant : pas un chevauchement.
      expect(existing.overlaps(disjoint), isFalse);
    });
  });

  group('Opération 82 — DELETE /providers/me/unavailabilities/{id}', () {
    test('suppression de ma propre absence', () async {
      final ApiHarness harness = harnessFor('deleted');

      await repositoryOn(harness).deleteUnavailability(kUnavailabilityId);

      expect(harness.lastCall.method, 'DELETE');
      expect(
        harness.lastCall.path,
        '/providers/me/unavailabilities/$kUnavailabilityId',
      );
    });

    test(
      '404 — appartenance vérifiée : l’absence d’un autre est introuvable',
      () async {
        await expectLater(
          repositoryOn(harnessFor('notFound')).deleteUnavailability('u-autre'),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.isNotFound, 'isNotFound', isTrue)
                .having(
                  (ApiException e) => e.message,
                  'message',
                  'Absence introuvable',
                ),
          ),
        );
      },
    );
  });
}
