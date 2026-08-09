// Catalogue et zones — opérations 22, 23 et 24 (T094).
//
// Ces trois routes sont publiques, non paginées, et leur contenu ne change qu'au
// rythme de l'administration. Elles sont donc mises en cache **24 heures sur
// disque** : au deuxième démarrage, les filtres de recherche s'affichent sans
// attendre le réseau, et restent utilisables hors ligne.
//
// `zones/nearby` fait exception : son résultat dépend de la position demandée, il
// n'a donc rien à faire dans un cache partagé.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/core/cache/stale_while_revalidate.dart';
import 'package:prestgo_mobile/features/search/domain/catalog.dart';

class CatalogRepository {
  const CatalogRepository(this._client, this._cache);

  final ApiClient _client;
  final CacheDao _cache;

  // --- 22. Catégories -----------------------------------------------------------

  /// `GET /categories`, cache d'abord puis revalidation.
  ///
  /// Émet une fois si le cache est vide, deux fois sinon. Au-delà de 24 heures, le
  /// service est rejoint ; en deçà, la valeur en cache suffit et aucune requête
  /// n'est faite.
  Stream<CacheSnapshot<List<Category>>> watchCategories() =>
      staleWhileRevalidate<List<Category>>(
        readCache: () async {
          final CachedValue<List<JsonMap>>? cached = await _cache.readCatalog();
          return cached?.map(
            (List<JsonMap> rows) =>
                rows.map(Category.fromJson).toList(growable: false),
          );
        },
        fetch: fetchCategories,
        writeCache: _writeCategories,
        ttl: CacheTtl.catalog,
      );

  Future<List<Category>> fetchCategories() async {
    final ApiEnvelope<List<Category>> envelope = await _client
        .get<List<Category>>(
          '/categories',
          parse: parseList<Category>(Category.fromJson),
        );
    return envelope.data ?? const <Category>[];
  }

  /// Catégories du cache, sans réseau. `null` si rien n'a jamais été chargé.
  Future<List<Category>?> cachedCategories() async {
    final CachedValue<List<JsonMap>>? cached = await _cache.readCatalog();
    return cached?.value.map(Category.fromJson).toList(growable: false);
  }

  // --- 23. Zones ----------------------------------------------------------------

  Stream<CacheSnapshot<List<Zone>>> watchZones() =>
      staleWhileRevalidate<List<Zone>>(
        readCache: () async {
          final CachedValue<List<JsonMap>>? cached = await _cache.readZones();
          return cached?.map(
            (List<JsonMap> rows) =>
                rows.map(Zone.fromJson).toList(growable: false),
          );
        },
        fetch: fetchZones,
        writeCache: _writeZones,
        ttl: CacheTtl.catalog,
      );

  Future<List<Zone>> fetchZones() async {
    final ApiEnvelope<List<Zone>> envelope = await _client.get<List<Zone>>(
      '/zones',
      parse: parseList<Zone>(Zone.fromJson),
    );
    return envelope.data ?? const <Zone>[];
  }

  // --- 24. Zones proches --------------------------------------------------------

  /// `GET /zones/nearby` — jamais mis en cache : le résultat dépend de la position.
  ///
  /// Une liste vide est un **succès** : aucune zone ne couvre ce point. L'écran
  /// propose d'élargir, il n'affiche pas d'erreur.
  Future<List<Zone>> nearbyZones({
    required double latitude,
    required double longitude,
    double radiusKm = 10,
  }) async {
    final ApiEnvelope<List<Zone>> envelope = await _client.get<List<Zone>>(
      '/zones/nearby',
      query: <String, Object?>{
        'latitude': latitude,
        'longitude': longitude,
        'radiusKm': radiusKm,
      },
      parse: parseList<Zone>(Zone.fromJson),
    );
    return envelope.data ?? const <Zone>[];
  }

  // --- Écriture du cache --------------------------------------------------------

  Future<void> _writeCategories(List<Category> categories) =>
      _cache.writeCatalog(<({String id, int displayOrder, JsonMap payload})>[
        for (final (int index, Category category) in categories.indexed)
          (
            id: category.id,
            // L'ordre du service est conservé tel quel : c'est celui de
            // `displayOrder` puis du nom, et l'application ne re-trie jamais.
            displayOrder: index,
            payload: _categoryToJson(category),
          ),
      ], fetchedAt: DateTime.now());

  Future<void> _writeZones(List<Zone> zones) =>
      _cache.writeZones(<({String id, String name, JsonMap payload})>[
        for (final Zone zone in zones)
          (id: zone.id, name: zone.name, payload: _zoneToJson(zone)),
      ], fetchedAt: DateTime.now());

  static JsonMap _categoryToJson(Category category) => <String, Object?>{
    'id': category.id,
    'name': category.name,
    'description': category.description,
    'serviceTypes': <JsonMap>[
      for (final ServiceType type in category.serviceTypes)
        <String, Object?>{
          'id': type.id,
          'name': type.name,
          'description': type.description,
        },
    ],
  };

  static JsonMap _zoneToJson(Zone zone) => <String, Object?>{
    'id': zone.id,
    'name': zone.name,
    'latitude': zone.latitude,
    'longitude': zone.longitude,
    'radiusKm': zone.radiusKm,
    if (zone.cityName case final String city)
      'city': <String, Object?>{'name': city},
  };
}

final Provider<CatalogRepository> catalogRepositoryProvider =
    Provider<CatalogRepository>(
      (Ref ref) => CatalogRepository(
        ref.watch(apiClientProvider),
        ref.watch(cacheDaoProvider),
      ),
    );
