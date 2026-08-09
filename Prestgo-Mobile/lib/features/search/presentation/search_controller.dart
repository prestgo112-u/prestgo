// État de la recherche : filtres d'un côté, résultats paginés de l'autre.
//
// Séparer les deux est ce qui rend le défilement continu correct. Si les résultats
// dépendaient directement des filtres, chaque frappe dans le champ de recherche
// invaliderait la liste et repartirait de la page 1 — y compris pendant qu'une page
// suivante est en vol. Ici, l'écran modifie la requête, puis **demande**
// explicitement un rechargement.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/cache/stale_while_revalidate.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/location/location_service.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/search/data/catalog_repository.dart';
import 'package:prestgo_mobile/features/search/data/search_repository.dart';
import 'package:prestgo_mobile/features/search/domain/catalog.dart';
import 'package:prestgo_mobile/features/search/domain/provider_search.dart';

/// Filtres courants.
class SearchQueryController extends Notifier<ProviderSearchQuery> {
  @override
  ProviderSearchQuery build() => const ProviderSearchQuery();

  void replace(ProviderSearchQuery query) => state = query;

  void setCategory(String? categoryId) => state = state.copyWith(
    categoryId: categoryId,
    clearCategory: categoryId == null,
    // Un type de service appartient à une catégorie : changer de catégorie rend
    // le type précédent incohérent.
    clearServiceType: true,
  );

  void setServiceType(String? serviceTypeId) => state = state.copyWith(
    serviceTypeId: serviceTypeId,
    clearServiceType: serviceTypeId == null,
  );

  void setZone(String? zoneId) =>
      state = state.copyWith(zoneId: zoneId, clearZone: zoneId == null);

  void setSlot(SearchSlot? slot) =>
      state = state.copyWith(slot: slot, clearSlot: slot == null);

  void setMinRating(double? minRating) => state = state.copyWith(
    minRating: minRating,
    clearMinRating: minRating == null,
  );

  void setQuery(String? query) => state = state.copyWith(
    query: query,
    clearQuery: query == null || query.trim().isEmpty,
  );

  void setRadius(double radiusKm) => state = state.copyWith(
    radiusKm: radiusKm.clamp(
      PaginationLimits.minRadiusKm,
      PaginationLimits.maxRadiusKm,
    ),
  );

  /// Change le tri.
  ///
  /// Refuse « distance » sans position : l'écran désactive déjà l'option, mais un
  /// second verrou ici évite qu'un appel programmatique produise un 400 (FR-024).
  void setSort(SearchSort? sort) {
    if (sort == SearchSort.distance && state.position == null) {
      return;
    }
    state = state.copyWith(sort: sort, clearSort: sort == null);
  }

  void setPosition(SearchPosition? position) => state = state.copyWith(
    position: position,
    clearPosition: position == null,
    // Le tri par distance devient impossible sans position : le retirer évite
    // d'envoyer une requête que le service refuserait.
    clearSort: position == null && state.sort == SearchSort.distance,
  );

  void clearFilters() => state = state.cleared();

  void widenRadius() => state = state.widened();

  /// Demande la position et l'applique, sans jamais échouer.
  ///
  /// Renvoie le résultat pour que l'écran puisse expliquer un refus.
  Future<LocationResult> requestPosition() async {
    final LocationResult result = await ref
        .read(locationServiceProvider)
        .current();
    final GeoPoint? point = result.point;
    if (result.isGranted && point != null) {
      setPosition(
        SearchPosition(latitude: point.latitude, longitude: point.longitude),
      );
    }
    return result;
  }
}

final NotifierProvider<SearchQueryController, ProviderSearchQuery>
searchQueryProvider =
    NotifierProvider<SearchQueryController, ProviderSearchQuery>(
      SearchQueryController.new,
    );

/// Résultats paginés, rechargés à chaque changement de filtres.
class SearchResultsController extends PagedNotifier<ProviderSearchResult> {
  /// La recherche plafonne à 50 ; on reste sur la taille de page usuelle, qui
  /// suffit à remplir un écran et limite le coût d'un défilement rapide.
  @override
  int get pageSize => PaginationLimits.defaultPageSize;

  @override
  Future<PagedPage<ProviderSearchResult>> fetchPage({
    required int page,
    required int limit,
  }) => ref
      .read(searchRepositoryProvider)
      .search(ref.read(searchQueryProvider), page: page, limit: limit);

  @override
  Future<PagedState<ProviderSearchResult>> build() {
    // Observer les filtres reconstruit le contrôleur à chaque changement : c'est
    // exactement le rechargement attendu, sans qu'aucun écran ait à le déclencher.
    ref.watch(searchQueryProvider);
    // Trace de la première page de résultats — la mesure directe de SC-005
    // (« résultats visibles en moins de 2 s »).
    return ref
        .read(errorReporterProvider)
        .traceScreen('screen.search.results', super.build);
  }
}

final AsyncNotifierProvider<
  SearchResultsController,
  PagedState<ProviderSearchResult>
>
searchResultsProvider =
    AsyncNotifierProvider<
      SearchResultsController,
      PagedState<ProviderSearchResult>
    >(SearchResultsController.new);

/// Catalogue des filtres, servi par le cache puis rafraîchi.
///
/// Le flux émet deux fois quand un cache existe : les filtres s'affichent d'abord
/// instantanément, puis se corrigent si l'administration a changé quelque chose.
final StreamProvider<List<Category>> categoriesProvider =
    StreamProvider<List<Category>>(
      (Ref ref) => ref
          .watch(catalogRepositoryProvider)
          .watchCategories()
          .map((CacheSnapshot<List<Category>> snapshot) => snapshot.value),
    );

final StreamProvider<List<Zone>> zonesProvider = StreamProvider<List<Zone>>(
  (Ref ref) => ref
      .watch(catalogRepositoryProvider)
      .watchZones()
      .map((CacheSnapshot<List<Zone>> snapshot) => snapshot.value),
);
