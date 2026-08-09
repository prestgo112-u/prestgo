// « Mes avis » (T225, FR-072 ; data-model §6).
//
// Les états de modération commandent le rendu :
//   • `published` — l'avis, tel que déposé ;
//   • `reported`  — l'avis RESTE visible, avec la mention du signalement ;
//   • `hidden` / `rejected` — le contenu est remplacé par une mention de
//     retrait : ni la note ni le commentaire ne s'affichent.
//
// Ni modification ni suppression : aucune action d'édition n'existe ici.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/reviews/data/review_repository.dart';
import 'package:prestgo_mobile/features/reviews/domain/review.dart';

class MyReviewsController extends PagedNotifier<Review> {
  @override
  Future<PagedPage<Review>> fetchPage({
    required int page,
    required int limit,
  }) => ref.read(reviewRepositoryProvider).myReviews(page: page, limit: limit);
}

final AsyncNotifierProvider<MyReviewsController, PagedState<Review>>
myReviewsProvider =
    AsyncNotifierProvider<MyReviewsController, PagedState<Review>>(
      MyReviewsController.new,
    );

class MyReviewsScreen extends ConsumerWidget {
  const MyReviewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PagedState<Review>> reviews = ref.watch(myReviewsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mes avis')),
      body: reviews.when(
        loading: () => const LoadingView(label: 'Chargement de vos avis…'),
        error: (Object error, StackTrace _) => ErrorView(
          message: error is ApiException
              ? error.message
              : ApiFallbackMessages.unknown,
          onRetry: () => ref.read(myReviewsProvider.notifier).refresh(),
        ),
        data: (PagedState<Review> state) => state.isEmpty
            ? const EmptyView(
                icon: Icons.reviews_outlined,
                title: 'Aucun avis déposé',
                description:
                    'Après une mission terminée, vous pouvez noter votre '
                    'prestataire depuis le détail de la mission.',
              )
            : RefreshIndicator(
                onRefresh: () => ref.read(myReviewsProvider.notifier).refresh(),
                child: ListView.separated(
                  itemCount: state.items.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    if (index == state.items.length - 1 && state.hasMore) {
                      ref.read(myReviewsProvider.notifier).loadMore();
                    }
                    return _ReviewTile(review: state.items[index]);
                  },
                ),
              ),
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ReviewMissionRef? mission = review.mission;
    final String header = <String?>[
      mission?.providerName,
      if (mission?.scheduledAt case final DateTime date)
        'mission du ${DateLabels.day(date)}',
    ].whereType<String>().join(' — ');

    return ListTile(
      title: Text(
        header.isEmpty ? 'Mission' : header,
        style: theme.textTheme.bodySmall,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: review.isWithdrawn
            // Le contenu retiré n'est PAS affiché — la mention le remplace.
            ? Text(
                'Avis retiré par la modération.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
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
                      // Un avis signalé reste visible, et le dit.
                      if (review.status == ReviewStatus.reported)
                        Chip(
                          label: const Text('Signalé — en cours d’examen'),
                          visualDensity: VisualDensity.compact,
                          backgroundColor:
                              theme.colorScheme.surfaceContainerHighest,
                        ),
                    ],
                  ),
                  if (review.comment case final String comment
                      when comment.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(comment),
                    ),
                ],
              ),
      ),
    );
  }
}
