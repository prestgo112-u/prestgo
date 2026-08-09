// Base des listes paginées (R10).
//
// `meta` porte tout ce qu'il faut pour le défilement infini : `page`, `limit`,
// `total`. Aucun curseur n'est disponible côté service.
//
// ⚠️ Les tris par défaut **diffèrent selon le rôle** (missions client : plus
// récentes d'abord ; missions prestataire : chronologique croissant). Ils sont pris
// tels quels du service : cette base ne re-trie jamais (FR-038).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

/// Une page renvoyée par le service.
class PagedPage<T> {
  const PagedPage({required this.items, this.meta});

  final List<T> items;
  final ApiMeta? meta;
}

/// État d'une liste paginée.
class PagedState<T> {
  const PagedState({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  const PagedState.empty({this.limit = PaginationLimits.defaultPageSize})
    : items = const <Never>[],
      page = PaginationLimits.firstPage,
      total = 0,
      isLoadingMore = false,
      loadMoreError = null;

  final List<T> items;

  /// Dernière page chargée.
  final int page;

  final int limit;

  /// Total annoncé par le service ; `0` quand la réponse n'est pas paginée.
  final int total;

  final bool isLoadingMore;

  /// Échec du chargement de la page suivante.
  ///
  /// Distinct de l'erreur globale : la liste déjà chargée reste affichée, et seul
  /// le pied de liste signale l'échec avec une reprise.
  final ApiException? loadMoreError;

  /// Vrai s'il reste des éléments à charger.
  bool get hasMore => page * limit < total;

  bool get isEmpty => items.isEmpty;

  PagedState<T> copyWith({
    List<T>? items,
    int? page,
    int? limit,
    int? total,
    bool? isLoadingMore,
    ApiException? loadMoreError,
    bool clearLoadMoreError = false,
  }) => PagedState<T>(
    items: items ?? this.items,
    page: page ?? this.page,
    limit: limit ?? this.limit,
    total: total ?? this.total,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    loadMoreError: clearLoadMoreError
        ? null
        : loadMoreError ?? this.loadMoreError,
  );

  @override
  String toString() =>
      'PagedState(${items.length}/$total, page $page, limit $limit)';
}

/// Contrôleur de liste paginée.
///
/// Les sous-classes n'implémentent que [fetchPage] ; le chargement initial, le
/// défilement infini et le rafraîchissement sont fournis.
abstract class PagedNotifier<T> extends AsyncNotifier<PagedState<T>> {
  /// Taille de page demandée au service.
  ///
  /// `GET /providers/search` plafonne à 50, les autres routes à 100.
  int get pageSize => PaginationLimits.defaultPageSize;

  /// Charge une page auprès du service.
  Future<PagedPage<T>> fetchPage({required int page, required int limit});

  @override
  Future<PagedState<T>> build() => _loadFirstPage();

  /// Charge la page suivante et l'ajoute à la liste.
  ///
  /// Sans effet si un chargement est déjà en cours ou s'il n'y a plus de page :
  /// un défilement rapide en fin de liste ne doit pas déclencher de rafale.
  Future<void> loadMore() async {
    final PagedState<T>? current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) {
      return;
    }

    state = AsyncData<PagedState<T>>(
      current.copyWith(isLoadingMore: true, clearLoadMoreError: true),
    );

    try {
      final PagedPage<T> next = await fetchPage(
        page: current.page + 1,
        limit: current.limit,
      );
      state = AsyncData<PagedState<T>>(
        current.copyWith(
          items: <T>[...current.items, ...next.items],
          page: next.meta?.page ?? current.page + 1,
          total: next.meta?.total ?? current.total,
          isLoadingMore: false,
          clearLoadMoreError: true,
        ),
      );
    } on ApiException catch (error) {
      // La liste déjà chargée reste à l'écran : seul le pied signale l'échec.
      state = AsyncData<PagedState<T>>(
        current.copyWith(isLoadingMore: false, loadMoreError: error),
      );
    }
  }

  /// Recharge depuis la première page — geste de rafraîchissement, retour au
  /// premier plan, retour du réseau.
  Future<void> refresh() async {
    state = await AsyncValue.guard<PagedState<T>>(_loadFirstPage);
  }

  Future<PagedState<T>> _loadFirstPage() async {
    final PagedPage<T> first = await fetchPage(
      page: PaginationLimits.firstPage,
      limit: pageSize,
    );
    return PagedState<T>(
      items: first.items,
      page: first.meta?.page ?? PaginationLimits.firstPage,
      limit: first.meta?.limit ?? pageSize,
      // Une réponse non paginée n'a pas de `meta` : le total est alors le nombre
      // d'éléments reçus, et `hasMore` vaut faux.
      total: first.meta?.total ?? first.items.length,
    );
  }
}
