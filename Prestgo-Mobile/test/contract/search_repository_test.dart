// T085 — Contrat de `GET /providers/search` (opération 25).
//
// Deux familles d'assertions :
//   • ce que l'application **envoie** — les combinaisons refusées par le service ne
//     doivent jamais partir (FR-024). Un test qui vérifie qu'un 400 est bien
//     transformé en message serait rassurant mais insuffisant : la bonne réponse est
//     de ne pas provoquer ce 400 ;
//   • ce qu'elle **lit** — pagination, et les trois valeurs absentes qui se masquent
//     au lieu de s'afficher à zéro (FR-026).

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/search/data/search_repository.dart';
import 'package:prestgo_mobile/features/search/domain/provider_search.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'booking/search',
    caseName,
  );
  return ApiHarness.always(status, body);
}

const SearchPosition abidjan = SearchPosition(latitude: 5.35, longitude: -3.98);

void main() {
  group('Lecture des résultats', () {
    test('la première page porte sa pagination', () async {
      final ApiHarness harness = harnessFor('firstPage');

      final PagedPage<ProviderSearchResult> page = await SearchRepository(
        harness.client,
      ).search(const ProviderSearchQuery(), page: 1, limit: 20);

      expect(page.items, hasLength(3));
      expect(page.meta?.page, 1);
      expect(page.meta?.total, 42);
      expect(page.meta?.hasMore, isTrue);
      expect(harness.lastUrl, contains('/providers/search'));
    });

    test('la dernière page arrête le défilement continu', () async {
      final PagedPage<ProviderSearchResult> page = await SearchRepository(
        harnessFor('lastPage').client,
      ).search(const ProviderSearchQuery(), page: 3, limit: 20);

      expect(page.meta?.hasMore, isFalse);
    });

    test(
      'un prestataire sans avis est « nouveau », jamais noté zéro',
      () async {
        final PagedPage<ProviderSearchResult> page = await SearchRepository(
          harnessFor('firstPage').client,
        ).search(const ProviderSearchQuery(), page: 1, limit: 20);

        final ProviderSearchResult kofi = page.items[1];
        expect(kofi.reviewsCount, 0);
        expect(
          kofi.isNew,
          isTrue,
          reason:
              'une note de 0 ferait passer un prestataire neuf pour un mauvais',
        );
      },
    );

    test(
      'distance et prix d’appel absents sont nuls, donc masquables',
      () async {
        final PagedPage<ProviderSearchResult> page = await SearchRepository(
          harnessFor('firstPage').client,
        ).search(const ProviderSearchQuery(), page: 1, limit: 20);

        final ProviderSearchResult ama = page.items[2];
        expect(ama.distanceKm, isNull);
        expect(ama.startingPrice, isNull);
        expect(page.items.first.distanceKm, 1.24);
        expect(page.items.first.startingPrice, 5000);
      },
    );

    test('un résultat vide reste un succès', () async {
      final PagedPage<ProviderSearchResult> page = await SearchRepository(
        harnessFor('empty').client,
      ).search(const ProviderSearchQuery(), page: 1, limit: 20);

      expect(page.items, isEmpty);
      expect(page.meta?.total, 0);
    });
  });

  group('Paramètres envoyés', () {
    Future<Map<String, Object?>> parametersFor(
      ProviderSearchQuery query,
    ) async {
      final ApiHarness harness = harnessFor('firstPage');
      await SearchRepository(harness.client).search(query, page: 1, limit: 20);
      return harness.lastCall.queryParameters;
    }

    test('sans filtre, seule la pagination part', () async {
      final Map<String, Object?> parameters = await parametersFor(
        const ProviderSearchQuery(),
      );

      expect(parameters.keys, containsAll(<String>['page', 'limit']));
      expect(parameters.containsKey('latitude'), isFalse);
      expect(
        parameters.containsKey('radiusKm'),
        isFalse,
        reason: 'un rayon sans position n’a pas de sens',
      );
      expect(parameters.containsKey('sort'), isFalse);
    });

    test('la position entraîne le rayon avec elle', () async {
      final Map<String, Object?> parameters = await parametersFor(
        const ProviderSearchQuery(position: abidjan, radiusKm: 25),
      );

      expect(parameters['latitude'], 5.35);
      expect(parameters['longitude'], -3.98);
      expect(parameters['radiusKm'], 25);
    });

    test('le créneau part au format attendu par le service', () async {
      final Map<String, Object?> parameters = await parametersFor(
        ProviderSearchQuery(
          slot: SearchSlot(date: DateTime.utc(2026, 8, 3), startTime: '09:00'),
        ),
      );

      expect(parameters['date'], '2026-08-03');
      expect(parameters['startTime'], '09:00');
    });

    test('`limit` est écrêté au plafond de la recherche', () async {
      final ApiHarness harness = harnessFor('firstPage');

      await SearchRepository(
        harness.client,
      ).search(const ProviderSearchQuery(), page: 1, limit: 200);

      expect(
        harness.lastCall.queryParameters['limit'],
        PaginationLimits.maxSearchPageSize,
        reason: 'la recherche plafonne à 50, contre 100 sur les autres routes',
      );
    });

    test('un mot-clé vide n’est pas transmis', () async {
      final Map<String, Object?> parameters = await parametersFor(
        const ProviderSearchQuery(query: '   '),
      );

      expect(parameters.containsKey('q'), isFalse);
    });
  });

  group('Combinaisons refusées — devancées, jamais provoquées', () {
    test('le tri « distance » sans position n’est pas envoyé', () async {
      const ProviderSearchQuery query = ProviderSearchQuery(
        sort: SearchSort.distance,
      );

      expect(query.isDistanceSortAvailable, isFalse);
      expect(query.requestsUnavailableSort, isTrue);

      final ApiHarness harness = harnessFor('firstPage');
      await SearchRepository(harness.client).search(query, page: 1, limit: 20);

      expect(
        harness.lastCall.queryParameters.containsKey('sort'),
        isFalse,
        reason:
            'le service répondrait 400 ; l’écran rend l’option indisponible avec '
            'son explication (scénario 2.2)',
      );
    });

    test(
      'avec une position, le tri « distance » redevient disponible',
      () async {
        const ProviderSearchQuery query = ProviderSearchQuery(
          position: abidjan,
          sort: SearchSort.distance,
        );

        expect(query.isDistanceSortAvailable, isTrue);

        final ApiHarness harness = harnessFor('firstPage');
        await SearchRepository(
          harness.client,
        ).search(query, page: 1, limit: 20);

        expect(harness.lastCall.queryParameters['sort'], 'distance');
      },
    );

    test('date et heure sont indissociables par construction', () {
      // Le type l'impose : `SearchSlot` exige les deux. Il n'existe aucun chemin
      // permettant d'envoyer l'une sans l'autre (scénario 2.3).
      final SearchSlot slot = SearchSlot(
        date: DateTime.utc(2026, 8, 3),
        startTime: '09:00',
      );
      expect(slot.wireDate, '2026-08-03');
      expect(slot.startTime, '09:00');
    });

    test(
      'le refus du service reste correctement traduit s’il survient',
      () async {
        // Filet de sécurité : un client tiers ou une version antérieure pourrait
        // encore provoquer ce 400.
        await expectLater(
          SearchRepository(
            harnessFor('distanceSortWithoutPosition').client,
          ).search(const ProviderSearchQuery(), page: 1, limit: 20),
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
                  'Le tri par distance exige latitude et longitude',
                ),
          ),
        );
      },
    );
  });

  group('Aides de l’écran de résultat vide', () {
    test('« Élargir le rayon » double sans dépasser le plafond', () {
      const ProviderSearchQuery query = ProviderSearchQuery(position: abidjan);

      expect(
        query.radiusKm,
        PaginationLimits.defaultRadiusKm,
        reason: '10 km par défaut, comme le service (FR-023)',
      );
      expect(query.canWidenRadius, isTrue);
      expect(query.widened().radiusKm, 20);
      expect(
        query.copyWith(radiusKm: 40).widened().radiusKm,
        PaginationLimits.maxRadiusKm,
      );
      expect(
        query.copyWith(radiusKm: PaginationLimits.maxRadiusKm).canWidenRadius,
        isFalse,
      );
    });

    test('sans position, il n’y a pas de rayon à élargir', () {
      expect(const ProviderSearchQuery().canWidenRadius, isFalse);
    });

    test('« Retirer les filtres » garde la position', () {
      final ProviderSearchQuery query = ProviderSearchQuery(
        position: abidjan,
        radiusKm: 25,
        categoryId: 'cat-1',
        minRating: 4,
        slot: SearchSlot(date: DateTime.utc(2026, 8, 3), startTime: '09:00'),
      );

      expect(query.hasFilters, isTrue);

      final ProviderSearchQuery cleared = query.cleared();
      expect(cleared.hasFilters, isFalse);
      expect(
        cleared.position,
        abidjan,
        reason:
            'la géolocalisation vient d’être accordée : la perdre en retirant les '
            'filtres serait un recul',
      );
      expect(cleared.radiusKm, 25);
    });
  });
}
