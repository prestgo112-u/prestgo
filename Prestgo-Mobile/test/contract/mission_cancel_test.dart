// T122 — Contrat de l'annulation (opération 40).
//
// Le piège de cette route : `late` est **calculé, jamais bloquant**. Une annulation
// à moins du préavis en vigueur est acceptée et marquée tardive — bloquer
// pousserait le client à ne pas prévenir du tout. L'avertissement se fait donc
// **avant** l'appel (seuil lu auprès du service, porte G3), et le message serveur,
// affiché après coup, reste l'autorité (scénario 3.2).

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/settings/public_settings.dart';
import 'package:prestgo_mobile/features/missions/data/mission_repository.dart';
import 'package:prestgo_mobile/features/missions/domain/cancellation.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

late LocalDatabase database;
late CacheDao cache;

const String kMissionId = 'b86332d9-14a0-4ec8-b5d0-d0158ae1824d';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'missions/cancel',
    caseName,
  );
  return ApiHarness.always(status, body);
}

MissionRepository repositoryOn(ApiHarness harness) =>
    MissionRepository(harness.client, cache);

void main() {
  setUp(() {
    database = LocalDatabase.memory();
    cache = CacheDao(database);
  });

  tearDown(() => database.close());

  group('Opération 40 — POST /missions/{id}/cancel', () {
    test('200 — annulation dans les temps : `late` faux', () async {
      final ApiHarness harness = harnessFor('cancelled');

      final CancellationResult result = await repositoryOn(harness).cancel(
        'a75221c8-03a0-4dc7-a4c0-c0047ad0713c',
        reason: 'Empêchement de dernière minute',
      );

      expect(harness.lastCall.method, 'POST');
      expect(harness.lastUrl, endsWith('/cancel'));
      expect(result.late, isFalse);
      expect(result.status, MissionStatus.cancelled);
      expect(result.previousStatus, MissionStatus.pendingProvider);
      expect(result.message, 'Mission annulée');
    });

    test(
      '200 — annulation tardive : ACCEPTÉE, marquée, message tel quel',
      () async {
        final CancellationResult result = await repositoryOn(
          harnessFor('cancelledLate'),
        ).cancel(kMissionId, reason: 'Empêchement de dernière minute');

        expect(result.late, isTrue);
        expect(result.previousStatus, MissionStatus.confirmed);
        expect(
          result.message,
          "Mission annulée. L'annulation est enregistrée comme tardive.",
          reason:
              'le verdict du service est affiché tel quel, jamais reformulé',
        );
      },
    );

    test(
      'le motif part dans le corps ; les détails seulement s’ils existent',
      () async {
        final ApiHarness withDetails = harnessFor('cancelledLate');
        await repositoryOn(withDetails).cancel(
          kMissionId,
          reason: 'Empêchement de dernière minute',
          details: 'Je serai absent toute la journée.',
        );
        expect(
          withDetails.lastBody['reason'],
          'Empêchement de dernière minute',
        );
        expect(
          withDetails.lastBody['details'],
          'Je serai absent toute la journée.',
        );

        final ApiHarness withoutDetails = harnessFor('cancelled');
        await repositoryOn(
          withoutDetails,
        ).cancel('a75221c8-03a0-4dc7-a4c0-c0047ad0713c', reason: 'Empêchement');
        expect(withoutDetails.lastBody.containsKey('details'), isFalse);
      },
    );

    test('l’annulation invalide le détail et la liste en cache', () async {
      // Un détail et une liste « À venir » sont en cache…
      await cache.writeMissionDetail(
        id: kMissionId,
        payload: fixtureData('missions/detail', 'confirmed'),
        fetchedAt: DateTime.now(),
      );
      await cache.writeMissions(MissionCacheRole.client, <
        ({
          String id,
          String status,
          DateTime scheduledAt,
          Map<String, Object?> payload,
        })
      >[
        (
          id: kMissionId,
          status: 'confirmed',
          scheduledAt: DateTime.utc(2026, 8, 3, 14),
          payload: <String, Object?>{'id': kMissionId},
        ),
      ], fetchedAt: DateTime.now());

      final MissionRepository repository = repositoryOn(
        harnessFor('cancelledLate'),
      );
      await repository.cancel(kMissionId, reason: 'Empêchement');

      // …et l'annulation les a rendus faux : ils ne doivent plus être servis.
      expect(await repository.cachedDetail(kMissionId), isNull);
      expect(await repository.cachedUpcoming(), isNull);
    });

    test('400 — le motif est obligatoire, l’erreur désigne le champ', () async {
      await expectLater(
        repositoryOn(
          harnessFor('missingReason'),
        ).cancel(kMissionId, reason: ''),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.isUserFixable,
                'corrigeable',
                isTrue,
              )
              .having(
                (ApiException e) => e.messageForField('reason'),
                'champ reason',
                'Un motif est obligatoire (au moins 3 caractères)',
              ),
        ),
      );
    });

    test(
      '400 — transition invalide : le statut a changé entre-temps',
      () async {
        await expectLater(
          repositoryOn(
            harnessFor('invalidTransition'),
          ).cancel(kMissionId, reason: 'Trop tard'),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.message,
              'message',
              'Transition de mission invalide : completed → cancelled',
            ),
          ),
        );
      },
    );

    test('403 — non partie à la mission', () async {
      await expectLater(
        repositoryOn(
          harnessFor('notParty'),
        ).cancel('m-etrangere', reason: 'Motif'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.isForbidden,
            'isForbidden',
            isTrue,
          ),
        ),
      );
    });
  });

  group('Avertissement de tardiveté — AVANT l’envoi (scénario 3.2)', () {
    // Le seuil vient de `GET /settings/public`, jamais d'une constante.
    const PublicSettings settings = PublicSettings.fallback;

    test('à moins du préavis de l’horaire, l’avertissement se déclenche', () {
      final DateTime scheduledAt = DateTime.utc(2026, 8, 3, 14);

      expect(
        isLateCancellation(
          scheduledAt: scheduledAt,
          now: DateTime.utc(2026, 8, 3, 10),
          notice: settings.cancellationNotice,
        ),
        isTrue,
        reason: '4 h avant, pour un préavis de 6 h : tardif',
      );
      expect(
        isLateCancellation(
          scheduledAt: scheduledAt,
          now: DateTime.utc(2026, 8, 2, 14),
          notice: settings.cancellationNotice,
        ),
        isFalse,
        reason: 'une journée avant : dans les temps',
      );
    });

    test('sans horaire connu, aucun avertissement — le service tranchera', () {
      expect(
        isLateCancellation(
          scheduledAt: null,
          now: DateTime.utc(2026, 8, 3),
          notice: settings.cancellationNotice,
        ),
        isFalse,
      );
    });

    test(
      'le client ne peut annuler que depuis pending_provider et confirmed',
      () {
        expect(MissionStatus.pendingProvider.clientMayCancel, isTrue);
        expect(MissionStatus.confirmed.clientMayCancel, isTrue);
        expect(MissionStatus.inProgress.clientMayCancel, isFalse);
        expect(MissionStatus.completed.clientMayCancel, isFalse);
        expect(MissionStatus.cancelled.clientMayCancel, isFalse);
        expect(MissionStatus.closed.clientMayCancel, isFalse);
        expect(MissionStatus.disputed.clientMayCancel, isFalse);
      },
    );
  });
}
