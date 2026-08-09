// Écran de recherche (T098, FR-022, FR-025).
//
// C'est l'écran d'accueil de l'application, et il est **consultable sans compte** :
// aucune de ses routes n'exige de session. Obliger à s'inscrire pour regarder l'offre
// ferait fuir la moitié des visiteurs — c'est le raisonnement du service, et
// l'application le respecte jusqu'au bout, avatars compris.
//
// Le défilement continu s'appuie sur `meta` : `page`, `limit` et `total` suffisent,
// il n'existe pas de curseur côté service.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/search/domain/provider_search.dart';
import 'package:prestgo_mobile/features/search/presentation/search_controller.dart';
import 'package:prestgo_mobile/features/search/presentation/search_filters.dart';
import 'package:prestgo_mobile/features/search/presentation/search_states.dart';
import 'package:prestgo_mobile/features/search/presentation/widgets/provider_card.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  /// Charge la page suivante avant d'atteindre le bas.
  ///
  /// `loadMore` est déjà protégé contre les appels concurrents : un défilement
  /// rapide en fin de liste ne déclenche pas de rafale.
  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    final double remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 400) {
      ref.read(searchResultsProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ProviderSearchQuery query = ref.watch(searchQueryProvider);
    final AsyncValue<PagedState<ProviderSearchResult>> results = ref.watch(
      searchResultsProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trouver un prestataire'),
        actions: <Widget>[
          IconButton(
            onPressed: () => context.push(Routes.favorites),
            icon: const Icon(Icons.favorite_border),
            tooltip: 'Mes favoris',
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _SearchField(
            controller: _search,
            onSubmitted: (String value) =>
                ref.read(searchQueryProvider.notifier).setQuery(value),
          ),
          _FilterBar(
            query: query,
            onOpenFilters: () => showSearchFilters(context),
          ),
          Expanded(
            child: results.when(
              loading: () =>
                  const LoadingView(label: 'Recherche des prestataires…'),
              error: (Object error, StackTrace _) => ErrorView(
                message: error is ApiException
                    ? error.message
                    : ApiFallbackMessages.unknown,
                onRetry: () =>
                    ref.read(searchResultsProvider.notifier).refresh(),
              ),
              data: (PagedState<ProviderSearchResult> state) => state.isEmpty
                  ? SearchEmptyView(
                      query: query,
                      onWidenRadius: () =>
                          ref.read(searchQueryProvider.notifier).widenRadius(),
                      onClearFilters: () =>
                          ref.read(searchQueryProvider.notifier).clearFilters(),
                    )
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.read(searchResultsProvider.notifier).refresh(),
                      child: ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        // Une ligne de plus : le compteur en tête, le pied en fin.
                        itemCount: state.items.length + 2,
                        itemBuilder: (BuildContext context, int index) {
                          if (index == 0) {
                            return SearchResultCount(total: state.total);
                          }
                          if (index == state.items.length + 1) {
                            return SearchListFooter(
                              isLoadingMore: state.isLoadingMore,
                              hasError: state.loadMoreError != null,
                              onRetry: () => ref
                                  .read(searchResultsProvider.notifier)
                                  .loadMore(),
                            );
                          }
                          final ProviderSearchResult provider =
                              state.items[index - 1];
                          return ProviderCard(
                            provider: provider,
                            onTap: () => context.push(
                              Routes.providerProfileFor(provider.id),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Plombier, électricien, ménage…',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Effacer',
                onPressed: () {
                  controller.clear();
                  onSubmitted('');
                },
              ),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      // La recherche part à la validation, pas à chaque frappe : une requête par
      // caractère saturerait un réseau mobile pour un résultat instable.
      onSubmitted: onSubmitted,
    ),
  );
}

/// Résumé des filtres actifs, avec accès au panneau.
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.query, required this.onOpenFilters});

  final ProviderSearchQuery query;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Row(
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: onOpenFilters,
          icon: const Icon(Icons.tune, size: 18),
          label: Text(query.hasFilters ? 'Filtres actifs' : 'Filtrer'),
        ),
        const SizedBox(width: 8),
        if (query.sort case final SearchSort sort)
          Expanded(
            child: Text(
              sort.label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.end,
            ),
          ),
      ],
    ),
  );
}
