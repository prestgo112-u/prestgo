// T121 — Contrat des listes et du détail de mission (opérations 32, 34, 35).
//
// Ce que cette famille de routes a de singulier, tout est vérifié ici :
//   • `status` accepte une **liste** dans un seul paramètre — un onglet = un appel,
//     `meta.total` reflète l'union (scénario 3.1) ; une liste contenant un statut
//     inconnu est refusée **en bloc** ;
//   • le tri est celui du service et n'est jamais recalculé (FR-038) ;
//   • `quotedAmount` peut être `null` — « — », jamais « 0 XOF » ;
//   • le détail n'expose **aucune coordonnée personnelle** de l'autre partie ;
//   • la première page « À venir » et chaque détail sont mis en cache (T135).

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/features/missions/data/mission_repository.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_detail.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_history.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_list_item.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

late LocalDatabase database;
late CacheDao cache;

/// Identité du compte client des captures (`auth/me`, cas `client`).
const String kMeId = 'c4f8a2e1-9d3b-4e5a-8f6c-1a2b3c4d5e6f';

ApiHarness harnessFor(String file, String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'missions/$file',
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

  group('Opération 32 — GET /me/missions', () {
    test(
      'un onglet = UN appel, statuts joints dans le même paramètre',
      () async {
        final ApiHarness harness = harnessFor('list', 'completedTab');

        final PagedPage<MissionListItem> page = await repositoryOn(
          harness,
        ).myMissions(statuses: MissionTab.completed.statuses);

        expect(harness.callCount, 1);
        expect(
          harness.lastCall.uri.queryParameters['status'],
          'completed,closed',
        );
        expect(page.items, hasLength(2));
        expect(
          page.meta?.total,
          2,
          reason: 'le total reflète l’union des deux statuts',
        );
      },
    );

    test('le tri du service est conservé — jamais recalculé', () async {
      final PagedPage<MissionListItem> page = await repositoryOn(
        harnessFor('list', 'completedTab'),
      ).myMissions(statuses: MissionTab.completed.statuses);

      expect(page.items.first.status, MissionStatus.completed);
      expect(page.items.last.status, MissionStatus.closed);
      expect(
        page.items.first.scheduledAt!.isAfter(page.items.last.scheduledAt!),
        isTrue,
        reason: 'côté client, le service trie par scheduledAt décroissant',
      );
    });

    test('`quotedAmount` nul est accepté — mission historique', () async {
      final ApiHarness harness = harnessFor('list', 'confirmedOnly');

      final PagedPage<MissionListItem> page = await repositoryOn(
        harness,
      ).myMissions(statuses: <MissionStatus>[MissionStatus.confirmed]);

      final MissionListItem mission = page.items.single;
      expect(mission.quotedAmount, isNull);
      expect(mission.packTitle, 'Réparation de fuite simple');
      expect(mission.locality, 'Cocody, Abidjan');
      expect(
        harness.lastUrl,
        '$kTestBaseUrl/me/missions?status=confirmed&page=1&limit=20',
      );
    });

    test('`from` et `to` partent en AAAA-MM-JJ — la borne `to` est inclusive '
        'côté service', () async {
      final ApiHarness harness = harnessFor('list', 'empty');

      await repositoryOn(harness).myMissions(
        statuses: MissionTab.upcoming.statuses,
        from: DateTime(2026, 8, 5),
        to: DateTime(2026, 8, 5),
      );

      final Map<String, String> query = harness.lastCall.uri.queryParameters;
      expect(query['from'], '2026-08-05');
      expect(query['to'], '2026-08-05');
    });

    test('la pagination suit `meta` — page 1 de 2 annonce une suite', () async {
      final PagedPage<MissionListItem> page = await repositoryOn(
        harnessFor('list', 'firstOfTwoPages'),
      ).myMissions(statuses: MissionTab.completed.statuses, limit: 2);

      expect(page.meta?.page, 1);
      expect(page.meta?.total, 3);
      expect(page.meta?.hasMore, isTrue);
    });

    test(
      '400 — une liste contenant un statut inconnu est refusée en bloc',
      () async {
        await expectLater(
          repositoryOn(
            harnessFor('list', 'unknownStatus'),
          ).myMissions(statuses: MissionTab.upcoming.statuses),
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

    test(
      'la première page « À venir » est mise en cache, tri conservé',
      () async {
        final MissionRepository repository = repositoryOn(
          harnessFor('list', 'upcoming'),
        );

        expect(await repository.cachedUpcoming(), isNull);
        await repository.myMissions(statuses: MissionTab.upcoming.statuses);
        final List<MissionListItem>? cached =
            (await repository.cachedUpcoming())?.value;

        expect(cached, hasLength(2));
        expect(
          cached!.first.status,
          MissionStatus.pendingProvider,
          reason: 'le cache rend la liste dans le tri du service (décroissant)',
        );
      },
    );

    test(
      'les onglets filtrés ne remplacent pas le cache de l’agenda',
      () async {
        final MissionRepository repository = repositoryOn(
          harnessFor('list', 'upcoming'),
        );
        await repository.myMissions(statuses: MissionTab.upcoming.statuses);

        // Un autre onglet, une autre page, une plage de dates : aucun ne touche
        // au cache « À venir ».
        final MissionRepository other = repositoryOn(
          harnessFor('list', 'completedTab'),
        );
        await other.myMissions(statuses: MissionTab.completed.statuses);
        await other.myMissions(statuses: MissionTab.upcoming.statuses, page: 2);
        await other.myMissions(
          statuses: MissionTab.upcoming.statuses,
          from: DateTime(2026, 8, 5),
          to: DateTime(2026, 8, 5),
        );

        final List<MissionListItem>? cached =
            (await repository.cachedUpcoming())?.value;
        expect(cached, hasLength(2));
        expect(cached!.first.status, MissionStatus.pendingProvider);
      },
    );
  });

  group('Opération 34 — GET /missions/{id}', () {
    test('toutes les sections arrivent en un seul appel', () async {
      final ApiHarness harness = harnessFor('detail', 'confirmed');

      final MissionDetail detail = await repositoryOn(
        harness,
      ).detail('b86332d9-14a0-4ec8-b5d0-d0158ae1824d');

      expect(harness.callCount, 1);
      expect(detail.status, MissionStatus.confirmed);
      expect(detail.quotedAmount, isNull, reason: 'afficher « — », pas 0 XOF');
      expect(detail.instructions, "Fuite sous l'évier de la cuisine.");
      expect(detail.pack.title, 'Réparation de fuite simple');
      expect(detail.pack.serviceTypeName, 'Réparation de fuite');
      expect(detail.address?.label, 'Domicile');
      expect(detail.thread?.id, isNotEmpty);
      expect(detail.thread?.isOpen, isTrue);
      expect(detail.cancellation, isNull);
      expect(detail.reschedules, isEmpty);
    });

    test(
      '`reviews` réduit sert uniquement à savoir si MOI j’ai noté',
      () async {
        final MissionDetail detail = await repositoryOn(
          harnessFor('detail', 'confirmed'),
        ).detail('b86332d9-14a0-4ec8-b5d0-d0158ae1824d');

        expect(detail.hasReviewBy(kMeId), isTrue);
        expect(detail.hasReviewBy('un-autre-compte'), isFalse);
        expect(detail.isClient(kMeId), isTrue);
      },
    );

    test('une annulation tardive est signalée explicitement', () async {
      final MissionDetail detail = await repositoryOn(
        harnessFor('detail', 'cancelledLate'),
      ).detail('f2a772a3-58f5-4b3d-e915-1549cf25c681');

      expect(detail.status, MissionStatus.cancelled);
      expect(detail.cancellation, isNotNull);
      expect(detail.cancellation!.late, isTrue);
      expect(detail.cancellation!.reason, 'Empêchement de dernière minute');
    });

    test(
      'une demande de report en attente est exposée avec son auteur',
      () async {
        final MissionDetail detail = await repositoryOn(
          harnessFor('detail', 'withPendingReschedule'),
        ).detail('b86332d9-14a0-4ec8-b5d0-d0158ae1824d');

        expect(detail.pendingReschedule, isNotNull);
        expect(
          detail.pendingReschedule!.canRespond(kMeId),
          isTrue,
          reason: 'créée par le prestataire : le client peut répondre',
        );
        expect(
          detail.pendingReschedule!.canRespond(detail.provider.id),
          isFalse,
          reason: 'jamais de boutons Accepter/Refuser sur sa propre demande',
        );
      },
    );

    test('le détail est mis en cache pour la consultation sur place', () async {
      final MissionRepository repository = repositoryOn(
        harnessFor('detail', 'confirmed'),
      );
      const String id = 'b86332d9-14a0-4ec8-b5d0-d0158ae1824d';

      expect(await repository.cachedDetail(id), isNull);
      await repository.detail(id);
      final MissionDetail? cached = (await repository.cachedDetail(id))?.value;

      expect(cached?.id, id);
      expect(cached?.address?.label, 'Domicile');
    });

    test(
      '403 — révéler l’existence d’une mission d’autrui serait une fuite',
      () async {
        await expectLater(
          repositoryOn(harnessFor('detail', 'notParty')).detail('m-inconnue'),
          throwsA(
            isA<ApiException>()
                .having(
                  (ApiException e) => e.isForbidden,
                  'isForbidden',
                  isTrue,
                )
                .having(
                  (ApiException e) => e.message,
                  'message',
                  "Vous n'êtes pas partie à cette mission",
                ),
          ),
        );
      },
    );
  });

  group('Opération 35 — GET /missions/{id}/history', () {
    test(
      'la frise lit les changements de statut dans l’ordre du service',
      () async {
        final ApiHarness harness = harnessFor('history', 'timeline');

        final MissionHistory history = await repositoryOn(
          harness,
        ).history('b86332d9-14a0-4ec8-b5d0-d0158ae1824d');

        expect(harness.lastUrl, endsWith('/history'));
        expect(history.statusHistory, hasLength(2));
        expect(history.statusHistory.first.oldStatus, isNull);
        expect(
          history.statusHistory.first.newStatus,
          MissionStatus.pendingProvider,
        );
        expect(history.statusHistory.last.newStatus, MissionStatus.confirmed);
        expect(history.reschedules, hasLength(1));
        expect(history.completedAt, isNull);
      },
    );

    test('la date d’entrée en `completed` ouvre la fenêtre d’avis', () async {
      final MissionHistory history = await repositoryOn(
        harnessFor('history', 'completedTimeline'),
      ).history('c9744fd0-25c2-4e0a-b6e2-e2169cf2935e');

      expect(
        history.completedAt,
        DateTime.parse('2026-07-12T11:07:02.876Z').toLocal(),
      );
    });
  });
}
