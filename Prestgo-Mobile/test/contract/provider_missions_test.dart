// T164 — Contrat de la liste prestataire (opération 33, GET /providers/me/missions).
//
// Ce que cette route a de singulier, tout est vérifié ici :
//   • le tri par défaut est `scheduledAt` **croissant** — l'inverse exact du
//     client : le prestataire veut voir ce qui arrive d'abord (FR-038), et la
//     liste n'est jamais retriée localement ;
//   • `status` accepte une **liste** dans un seul paramètre — un bloc du tableau
//     de bord = un appel (FR-065) ; une liste contenant un statut inconnu est
//     refusée en bloc ;
//   • `from`/`to` partent en `AAAA-MM-JJ`, la borne `to` est **inclusive** côté
//     service — le bloc « missions du jour » envoie le même jour aux deux bornes ;
//   • le DTO est le même `MissionListItem` que côté client ;
//   • la première page du planning est mise en cache sous le rôle **prestataire**,
//     séparé du cache client (les tris sont opposés).

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_list_item.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';
import 'package:prestgo_mobile/features/provider_space/data/provider_mission_repository.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_mission_tabs.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

late LocalDatabase database;
late CacheDao cache;

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'provider_missions/list',
    caseName,
  );
  return ApiHarness.always(status, body);
}

ProviderMissionRepository repositoryOn(ApiHarness harness) =>
    ProviderMissionRepository(harness.client, cache);

void main() {
  setUp(() {
    database = LocalDatabase.memory();
    cache = CacheDao(database);
  });

  tearDown(() => database.close());

  group('Opération 33 — GET /providers/me/missions', () {
    test(
      'le tri CROISSANT du service est conservé — jamais recalculé',
      () async {
        final ApiHarness harness = harnessFor('planning');

        final PagedPage<MissionListItem> page = await repositoryOn(
          harness,
        ).missions(statuses: ProviderMissionTab.planning.statuses);

        expect(harness.lastCall.uri.path, endsWith('/providers/me/missions'));
        expect(page.items, hasLength(3));
        expect(
          page.items.first.scheduledAt!.isBefore(page.items.last.scheduledAt!),
          isTrue,
          reason:
              'côté prestataire, ce qui arrive d’abord vient en premier '
              '(FR-038) — l’inverse exact du client',
        );
      },
    );

    test('un bloc du tableau de bord = UN appel, statuts joints', () async {
      final ApiHarness harness = harnessFor('today');

      final PagedPage<MissionListItem> page = await repositoryOn(harness)
          .missions(
            statuses: ProviderMissionTab.planning.statuses,
            from: DateTime(2026, 8, 5),
            to: DateTime(2026, 8, 5),
            limit: 50,
          );

      expect(harness.callCount, 1);
      final Map<String, String> query = harness.lastCall.uri.queryParameters;
      expect(query['status'], 'confirmed,in_progress');
      // `from` et `to` au même jour : la borne `to` est inclusive côté service —
      // c'est LUI qui ajoute le jour, pas l'application.
      expect(query['from'], '2026-08-05');
      expect(query['to'], '2026-08-05');
      expect(query['limit'], '50');
      expect(page.items, hasLength(2));
    });

    test('le compteur du bloc « demandes » est meta.total, pas un comptage '
        'local', () async {
      final PagedPage<MissionListItem> page = await repositoryOn(
        harnessFor('pendingRequests'),
      ).missions(statuses: ProviderMissionTab.requests.statuses);

      expect(page.meta?.total, 2);
      expect(page.items.first.status, MissionStatus.pendingProvider);
      expect(page.items.first.clientName, 'Awa Client');
    });

    test('le DTO est le même MissionListItem que côté client — '
        '`quotedAmount` nul accepté', () async {
      final PagedPage<MissionListItem> page = await repositoryOn(
        harnessFor('planning'),
      ).missions(statuses: ProviderMissionTab.planning.statuses);

      final MissionListItem historic = page.items.first;
      expect(historic.quotedAmount, isNull, reason: '« — », jamais « 0 XOF »');
      expect(historic.clientName, 'Awa Client');
      expect(historic.locality, 'Cocody, Abidjan');
      expect(historic.status, MissionStatus.inProgress);
    });

    test(
      '400 — une liste contenant un statut inconnu est refusée en bloc',
      () async {
        await expectLater(
          repositoryOn(
            harnessFor('unknownStatus'),
          ).missions(statuses: ProviderMissionTab.planning.statuses),
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
                  'Statut de mission inconnu',
                ),
          ),
        );
      },
    );

    test('la première page du planning est mise en cache sous le rôle '
        'PRESTATAIRE, tri croissant conservé', () async {
      final ProviderMissionRepository repository = repositoryOn(
        harnessFor('planning'),
      );

      expect(await repository.cachedPlanning(), isNull);
      await repository.missions(statuses: ProviderMissionTab.planning.statuses);
      final List<MissionListItem>? cached =
          (await repository.cachedPlanning())?.value;

      expect(cached, hasLength(3));
      expect(
        cached!.first.scheduledAt!.isBefore(cached.last.scheduledAt!),
        isTrue,
        reason: 'le cache rend la liste dans le tri du service (croissant)',
      );
      // Le cache client, lui, reste intact : les deux surfaces ne partagent
      // jamais leur cache, même pour un compte à double casquette.
      expect(await cache.readMissions(MissionCacheRole.client), isNull);
    });

    test(
      'les lectures filtrées ne remplacent pas le cache du planning',
      () async {
        final ProviderMissionRepository repository = repositoryOn(
          harnessFor('planning'),
        );
        await repository.missions(
          statuses: ProviderMissionTab.planning.statuses,
        );

        final ProviderMissionRepository other = repositoryOn(
          harnessFor('today'),
        );
        // Un autre statut, une autre page, une plage de dates : aucun ne touche
        // au cache du planning.
        await other.missions(statuses: ProviderMissionTab.requests.statuses);
        await other.missions(
          statuses: ProviderMissionTab.planning.statuses,
          page: 2,
        );
        await other.missions(
          statuses: ProviderMissionTab.planning.statuses,
          from: DateTime(2026, 8, 5),
          to: DateTime(2026, 8, 5),
        );

        final List<MissionListItem>? cached =
            (await repository.cachedPlanning())?.value;
        expect(cached, hasLength(3));
      },
    );

    // Le compteur de notifications non lues a rejoint son dépôt de plein droit
    // à T196 : voir `test/contract/notification_repository_test.dart`.
  });
}
