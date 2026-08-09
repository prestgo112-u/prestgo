// Tous les avis d'un prestataire (T103, opération 30).
//
// Route paginée dont `data` est un **tableau** — la forme du contrat d'enveloppe qui
// se combine avec `meta`.
//
// La fiche affiche les cinq derniers avis ; cet écran-ci les charge tous, par pages.
// Les séparer évite qu'un prestataire à trois cents avis fasse peser sa liste
// complète sur l'ouverture de sa fiche (FR-027).
//
// La pagination est tenue dans l'état de l'écran plutôt que dans un provider : cette
// liste n'est lue que d'ici, et n'a aucune raison de survivre à sa fermeture.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/reviews/presentation/report_review_action.dart';
import 'package:prestgo_mobile/features/search/data/search_repository.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/search/presentation/search_states.dart';

class ProviderReviewsScreen extends ConsumerStatefulWidget {
  const ProviderReviewsScreen({required this.providerId, super.key});

  final String providerId;

  @override
  ConsumerState<ProviderReviewsScreen> createState() =>
      _ProviderReviewsScreenState();
}

class _ProviderReviewsScreenState extends ConsumerState<ProviderReviewsScreen> {
  final ScrollController _scroll = ScrollController();
  final List<ProviderReview> _reviews = <ProviderReview>[];

  int _page = 0;
  int _total = 0;
  bool _isLoadingFirstPage = true;
  bool _isLoadingMore = false;
  ApiException? _firstPageError;
  ApiException? _loadMoreError;

  bool get _hasMore => _page * PaginationLimits.defaultPageSize < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFirstPage());
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.maxScrollExtent - _scroll.position.pixels < 300) {
      _loadMore();
    }
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoadingFirstPage = true;
      _firstPageError = null;
    });
    try {
      final PagedPage<ProviderReview> first = await ref
          .read(searchRepositoryProvider)
          .reviews(
            widget.providerId,
            page: PaginationLimits.firstPage,
            limit: PaginationLimits.defaultPageSize,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _reviews
          ..clear()
          ..addAll(first.items);
        _page = first.meta?.page ?? PaginationLimits.firstPage;
        _total = first.meta?.total ?? first.items.length;
        _isLoadingFirstPage = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _isLoadingFirstPage = false;
          _firstPageError = error;
        });
      }
    }
  }

  /// Charge la page suivante.
  ///
  /// Sans effet si un chargement est déjà en cours : un défilement rapide en fin de
  /// liste ne doit pas déclencher de rafale.
  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoadingFirstPage) {
      return;
    }
    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });

    try {
      final PagedPage<ProviderReview> next = await ref
          .read(searchRepositoryProvider)
          .reviews(
            widget.providerId,
            page: _page + 1,
            limit: PaginationLimits.defaultPageSize,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _reviews.addAll(next.items);
        _page = next.meta?.page ?? _page + 1;
        _total = next.meta?.total ?? _total;
        _isLoadingMore = false;
      });
    } on ApiException catch (error) {
      // La liste déjà chargée reste affichée : seul le pied signale l'échec.
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _loadMoreError = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_total == 0 ? 'Avis' : 'Tous les avis ($_total)'),
    ),
    body: _body,
  );

  Widget get _body {
    if (_isLoadingFirstPage) {
      return const LoadingView(label: 'Chargement des avis…');
    }
    if (_firstPageError case final ApiException error) {
      return ErrorView(message: error.message, onRetry: _loadFirstPage);
    }
    if (_reviews.isEmpty) {
      return const EmptyView(
        icon: Icons.reviews_outlined,
        title: 'Aucun avis pour le moment',
        description:
            'Les avis apparaissent après la première mission terminée.',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        controller: _scroll,
        itemCount: _reviews.length + 1,
        separatorBuilder: (BuildContext context, int index) =>
            const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) =>
            index == _reviews.length
            ? SearchListFooter(
                isLoadingMore: _isLoadingMore,
                hasError: _loadMoreError != null,
                onRetry: _loadMore,
              )
            : _ReviewTile(review: _reviews[index]),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final ProviderReview review;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListTile(
      title: Row(
        children: <Widget>[
          for (int star = 1; star <= 5; star++)
            Icon(
              star <= review.rating
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              size: 16,
              color: theme.colorScheme.tertiary,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(review.authorLabel, style: theme.textTheme.bodySmall),
          ),
          Text(
            DateLabels.day(review.createdAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // Signalement (US9, T226) : la page publique n'identifie pas
          // l'auteur — le 403 « votre propre avis » du service est le filet.
          ReportReviewAction(reviewId: review.id),
        ],
      ),
      subtitle: review.comment == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(review.comment!),
            ),
    );
  }
}
