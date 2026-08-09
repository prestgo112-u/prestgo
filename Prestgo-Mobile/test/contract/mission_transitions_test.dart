// T165 — Contrat des transitions de mission (opérations 36 à 40, côté
// prestataire).
//
// Ce que cette famille de routes a de singulier, tout est vérifié ici :
//   • cinq actions, une réponse commune `{ missionId, previousStatus, status,
//     late }` — le message de l'enveloppe est le verdict, affiché tel quel ;
//   • `accept`, `start` et `complete` partent **sans corps** ; `refuse` et
//     `cancel` portent un motif (FR-044) ;
//   • une transition n'est **jamais** rejouée (porte G4, FR-046) : la réponse
//     non reçue se classe `outcomeUnknown` — recharger l'état réel, laisser
//     l'utilisateur décider ;
//   • « Action impossible depuis le statut … » et « pas encore acceptée :
//     utilisez le refus » signalent que la réalité a changé → rechargement ;
//   • le 403 « pas le prestataire » est vérifié AVANT le statut ;
//   • un succès invalide le détail et les listes en cache — des DEUX rôles.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/features/missions/data/mission_transition_controller.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

late LocalDatabase database;
late CacheDao cache;

const String kMissionId = 'a75221c8-03a0-4dc7-a4c0-c0047ad0713c';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'provider_missions/transitions',
    caseName,
  );
  return ApiHarness.always(status, body);
}

MissionTransitionController controllerOn(ApiHarness harness) =>
    MissionTransitionController(harness.client, cache);

/// Sème le cache que la transition doit invalider.
Future<void> seedCaches() async {
  await cache.writeMissionDetail(
    id: kMissionId,
    payload: <String, Object?>{'id': kMissionId, 'status': 'pending_provider'},
    fetchedAt: DateTime.now(),
  );
  for (final MissionCacheRole role in MissionCacheRole.values) {
    await cache.writeMissions(
      role,
      <({String id, String status, DateTime scheduledAt, JsonMap payload})>[
        (
          id: kMissionId,
          status: 'pending_provider',
          scheduledAt: DateTime(2026, 8, 6, 9),
          payload: <String, Object?>{'id': kMissionId},
        ),
      ],
      fetchedAt: DateTime.now(),
    );
  }
}

void main() {
  setUp(() {
    database = LocalDatabase.memory();
    cache = CacheDao(database);
  });

  tearDown(() => database.close());

  group('Opération 36 — POST /missions/{id}/accept', () {
    test('part sans corps et rend le résultat commun', () async {
      final ApiHarness harness = harnessFor('accepted');

      final MissionTransitionResult result = await controllerOn(
        harness,
      ).accept(kMissionId);

      expect(harness.callCount, 1);
      expect(harness.lastCall.method, 'POST');
      expect(harness.lastUrl, '$kTestBaseUrl/missions/$kMissionId/accept');
      expect(harness.lastBody, isEmpty, reason: 'accept n’a pas de corps');
      expect(result.missionId, kMissionId);
      expect(result.previousStatus, MissionStatus.pendingProvider);
      expect(result.status, MissionStatus.confirmed);
      expect(result.late, isFalse);
      expect(result.message, 'Mission acceptée');
    });

    test('un succès invalide le détail et les listes des DEUX rôles', () async {
      await seedCaches();

      await controllerOn(harnessFor('accepted')).accept(kMissionId);

      expect(await cache.readMissionDetail(kMissionId), isNull);
      expect(await cache.readMissions(MissionCacheRole.client), isNull);
      expect(await cache.readMissions(MissionCacheRole.provider), isNull);
    });
  });

  group('Opération 37 — POST /missions/{id}/refuse', () {
    test(
      'porte le motif — refus avant acceptation, jamais « annulation »',
      () async {
        final ApiHarness harness = harnessFor('refused');

        final MissionTransitionResult result = await controllerOn(
          harness,
        ).refuse(kMissionId, reason: 'Déjà engagé sur un autre chantier.');

        expect(harness.lastUrl, endsWith('/missions/$kMissionId/refuse'));
        expect(harness.lastBody, <String, Object?>{
          'reason': 'Déjà engagé sur un autre chantier.',
        });
        expect(result.status, MissionStatus.cancelled);
        expect(result.message, 'Mission refusée');
      },
    );
  });

  group('Opération 38 — POST /missions/{id}/start', () {
    test('part sans corps quand la fenêtre est ouverte', () async {
      final ApiHarness harness = harnessFor('started');

      final MissionTransitionResult result = await controllerOn(
        harness,
      ).start(kMissionId);

      expect(harness.lastUrl, endsWith('/start'));
      expect(harness.lastBody, isEmpty);
      expect(result.status, MissionStatus.inProgress);
    });

    test('400 hors fenêtre — le message interpolé du service prime sur '
        'l’estimation locale', () async {
      await expectLater(
        controllerOn(harnessFor('startTooEarly')).start(kMissionId),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.isUserFixable,
                'corrigeable',
                isTrue,
              )
              .having(
                (ApiException e) => e.message,
                'message',
                'Vous pourrez démarrer cette mission au plus tôt 120 minutes '
                    'avant l\'heure prévue',
              ),
        ),
      );
    });
  });

  group('Opération 39 — POST /missions/{id}/complete', () {
    test('part sans corps et clôt l’exécution', () async {
      final ApiHarness harness = harnessFor('completed');

      final MissionTransitionResult result = await controllerOn(
        harness,
      ).complete(kMissionId);

      expect(harness.lastUrl, endsWith('/complete'));
      expect(harness.lastBody, isEmpty);
      expect(result.previousStatus, MissionStatus.inProgress);
      expect(result.status, MissionStatus.completed);
    });
  });

  group('Opération 40 — POST /missions/{id}/cancel (prestataire)', () {
    test('porte motif et précisions — le verdict de tardiveté est celui du '
        'service', () async {
      final ApiHarness harness = harnessFor('cancelledLate');

      final MissionTransitionResult result = await controllerOn(harness).cancel(
        kMissionId,
        reason: 'Panne de véhicule',
        details: 'Je préviens le client par message.',
      );

      expect(harness.lastBody, <String, Object?>{
        'reason': 'Panne de véhicule',
        'details': 'Je préviens le client par message.',
      });
      expect(result.late, isTrue);
      expect(
        result.message,
        "Mission annulée. L'annulation est enregistrée comme tardive.",
      );
    });

    test('400 sur pending_provider : « utilisez le refus » — la réalité a '
        'changé, rechargement', () async {
      ApiException? failure;
      try {
        await controllerOn(
          harnessFor('cancelOnPending'),
        ).cancel(kMissionId, reason: 'Je ne suis plus disponible.');
      } on ApiException catch (error) {
        failure = error;
      }

      expect(failure, isNotNull);
      expect(
        failure!.message,
        startsWith("Cette mission n'est pas encore acceptée"),
      );
      expect(MissionTransitionController.stateChanged(failure), isTrue);
    });

    test('400 sans motif — le service l’exige toujours', () async {
      await expectLater(
        controllerOn(
          harnessFor('missingReason'),
        ).cancel(kMissionId, reason: ''),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            'Un motif est obligatoire pour passer au statut "cancelled"',
          ),
        ),
      );
    });
  });

  group('Classement des échecs (porte G4, FR-046)', () {
    test('« Action impossible depuis le statut … » = réalité changée → '
        'rechargement, jamais de rejeu', () async {
      ApiException? failure;
      try {
        await controllerOn(harnessFor('invalidFromStatus')).start(kMissionId);
      } on ApiException catch (error) {
        failure = error;
      }

      expect(
        failure!.message,
        'Action impossible depuis le statut « completed »',
      );
      expect(MissionTransitionController.stateChanged(failure), isTrue);
      expect(MissionTransitionController.outcomeUnknown(failure), isFalse);
    });

    test('403 « pas le prestataire » n’est NI une issue inconnue NI un '
        'changement d’état', () async {
      ApiException? failure;
      try {
        await controllerOn(harnessFor('notProvider')).accept(kMissionId);
      } on ApiException catch (error) {
        failure = error;
      }

      expect(failure!.isForbidden, isTrue);
      expect(
        failure.message,
        "Vous n'êtes pas le prestataire de cette mission",
      );
      expect(MissionTransitionController.stateChanged(failure), isFalse);
      expect(MissionTransitionController.outcomeUnknown(failure), isFalse);
    });

    test('réponse jamais reçue = issue INCONNUE : un seul appel, aucun rejeu, '
        'et le cache invalidé pour forcer la relecture', () async {
      await seedCaches();
      final ApiHarness harness = ApiHarness(
        (dynamic options, int index) => throw StateError('réseau coupé'),
      );

      ApiException? failure;
      try {
        await controllerOn(harness).accept(kMissionId);
      } on ApiException catch (error) {
        failure = error;
      }

      expect(failure!.isNetwork, isTrue);
      expect(MissionTransitionController.outcomeUnknown(failure), isTrue);
      expect(
        harness.callCount,
        1,
        reason: 'une transition n’est JAMAIS rejouée automatiquement (FR-046)',
      );
      // L'issue est inconnue : ce que le cache porte est peut-être faux — il
      // est purgé pour que la relecture parte bien du service.
      expect(await cache.readMissionDetail(kMissionId), isNull);
    });
  });
}
