// T084 — Contrat du catalogue et des zones (opérations 22, 23, 24).
//
// Trois routes publiques, **non paginées** : `data` est un tableau nu, sans `meta`.
// Leur cache de 24 heures est ce qui rend les filtres de recherche disponibles au
// démarrage suivant, y compris hors ligne.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/cache/stale_while_revalidate.dart';
import 'package:prestgo_mobile/features/search/data/catalog_repository.dart';
import 'package:prestgo_mobile/features/search/domain/catalog.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

late LocalDatabase database;
late CacheDao cache;

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'booking/catalog',
    caseName,
  );
  return ApiHarness.always(status, body);
}

CatalogRepository repositoryOn(ApiHarness harness) =>
    CatalogRepository(harness.client, cache);

void main() {
  setUp(() {
    database = LocalDatabase.memory();
    cache = CacheDao(database);
  });

  tearDown(() => database.close());

  group('Opération 22 — GET /categories', () {
    test('les types de service sont imbriqués dans leur catégorie', () async {
      final ApiHarness harness = harnessFor('categories');

      final List<Category> categories = await repositoryOn(
        harness,
      ).fetchCategories();

      expect(categories, hasLength(3));
      expect(categories.first.name, 'Plomberie');
      expect(categories.first.serviceTypes, hasLength(2));
      expect(categories.first.serviceTypes.first.name, 'Réparation de fuite');
      expect(harness.lastUrl, '$kTestBaseUrl/categories');
    });

    test('une catégorie sans type actif reste sélectionnable', () async {
      final List<Category> categories = await repositoryOn(
        harnessFor('categories'),
      ).fetchCategories();

      final Category jardinage = categories.last;
      expect(jardinage.name, 'Jardinage');
      expect(
        jardinage.serviceTypes,
        isEmpty,
        reason: 'elle ne propose alors pas de second niveau de filtre',
      );
    });

    test('la réponse n’est pas paginée', () async {
      final ApiHarness harness = harnessFor('categories');
      await repositoryOn(harness).fetchCategories();

      expect(
        fixtureBody('booking/catalog', 'categories').containsKey('meta'),
        isFalse,
      );
    });

    test('l’ordre du service est conservé jusque dans le cache', () async {
      final CatalogRepository repository = repositoryOn(
        harnessFor('categories'),
      );

      final List<Category> fetched = await repository.fetchCategories();
      // Le flux écrit le cache lors de sa revalidation.
      await repository.watchCategories().drain<void>();
      final List<Category>? cached = await repository.cachedCategories();

      expect(cached, isNotNull);
      expect(
        cached!.map((Category c) => c.name),
        fetched.map((Category c) => c.name),
        reason: 'l’application ne re-trie jamais ce que le service a trié',
      );
    });
  });

  group('Cache 24 h', () {
    test(
      'le premier chargement émet une seule fois, depuis le réseau',
      () async {
        final ApiHarness harness = harnessFor('categories');

        final List<CacheSnapshot<List<Category>>> emissions =
            await repositoryOn(harness).watchCategories().toList();

        expect(emissions, hasLength(1));
        expect(emissions.single.isFromCache, isFalse);
        expect(harness.callCount, 1);
      },
    );

    test('le chargement suivant sert le cache sans joindre le service', () async {
      final ApiHarness first = harnessFor('categories');
      await repositoryOn(first).watchCategories().drain<void>();

      final ApiHarness second = harnessFor('categories');
      final List<CacheSnapshot<List<Category>>> emissions = await repositoryOn(
        second,
      ).watchCategories().toList();

      expect(emissions, hasLength(1));
      expect(emissions.single.isFromCache, isTrue);
      expect(
        second.callCount,
        0,
        reason:
            'le catalogue est quasi statique : le relire à chaque écran serait du '
            'gaspillage de réseau mobile',
      );
    });

    test(
      'hors ligne, le cache est servi avec l’erreur de revalidation',
      () async {
        await repositoryOn(
          harnessFor('categories'),
        ).watchCategories().drain<void>();

        // Cache périmé de force, puis réseau coupé.
        final ApiHarness offline = ApiHarness(
          (dynamic options, int index) => throw const _Offline(),
        );
        final CatalogRepository repository = repositoryOn(offline);
        final List<CacheSnapshot<List<Category>>>
        emissions = await staleWhileRevalidate<List<Category>>(
          readCache: () async {
            final List<Category>? cached = await repository.cachedCategories();
            return cached == null
                ? null
                : CachedValue<List<Category>>(
                    value: cached,
                    fetchedAt: DateTime.now().subtract(const Duration(days: 2)),
                  );
          },
          fetch: repository.fetchCategories,
          writeCache: (List<Category> _) async {},
          ttl: CacheTtl.catalog,
        ).toList();

        expect(emissions, hasLength(2));
        expect(emissions.first.isFromCache, isTrue);
        expect(emissions.last.isStale, isTrue);
        expect(emissions.last.revalidationError?.isNetwork, isTrue);
        expect(emissions.last.value, isNotEmpty);
      },
    );
  });

  group('Opérations 23 et 24 — zones', () {
    test('une zone sans centre est reconnue comme telle', () async {
      final List<Zone> zones = await repositoryOn(
        harnessFor('zones'),
      ).fetchZones();

      expect(zones, hasLength(3));
      expect(zones.first.hasPosition, isTrue);
      expect(
        zones.last.hasPosition,
        isFalse,
        reason:
            'elle ne peut alors ni être triée par distance ni couvrir une adresse',
      );
      expect(zones.first.label, 'Cocody, Abidjan');
    });

    test('`nearby` porte la distance et transmet le rayon', () async {
      final ApiHarness harness = harnessFor('nearby');

      final List<Zone> zones = await repositoryOn(
        harness,
      ).nearbyZones(latitude: 5.35, longitude: -3.98, radiusKm: 15);

      expect(zones.first.distanceKm, 0.42);
      expect(zones.last.distanceKm, 5.81);
      expect(harness.lastCall.queryParameters['radiusKm'], 15);
      expect(harness.lastUrl, contains('/zones/nearby'));
    });

    test('aucune zone dans le rayon est un succès, pas une erreur', () async {
      final List<Zone> zones = await repositoryOn(
        harnessFor('nearbyEmpty'),
      ).nearbyZones(latitude: 0, longitude: 0);

      expect(zones, isEmpty);
    });

    test('les zones ne sont pas paginées non plus', () {
      expect(
        fixtureBody('booking/catalog', 'zones').containsKey('meta'),
        isFalse,
      );
    });
  });
}

/// Coupure réseau simulée : `dio` la présente comme un échec sans réponse.
class _Offline implements Exception {
  const _Offline();
}
