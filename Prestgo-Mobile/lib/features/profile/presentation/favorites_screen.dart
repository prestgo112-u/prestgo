// Mes favoris (T105, FR-021).
//
// Un prestataire devenu non réservable — dossier suspendu, indisponibilité déclarée —
// est **grisé**, jamais masqué. Le faire disparaître serait pire que de l'afficher
// inactif : le client croirait avoir perdu son favori, sans jamais savoir pourquoi.
//
// Sa fiche reste ouverte : elle explique la situation mieux qu'une liste.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/files/file_avatar.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/profile/data/favorites_repository.dart';
import 'package:prestgo_mobile/features/profile/presentation/favorites_controller.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FavoriteProvider>> favorites = ref.watch(
      favoritesProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Mes favoris')),
      body: favorites.when(
        loading: () => const LoadingView(label: 'Chargement de vos favoris…'),
        error: (Object error, StackTrace _) => ErrorView(
          message: error is ApiException
              ? error.message
              : ApiFallbackMessages.unknown,
          onRetry: () => ref.read(favoritesProvider.notifier).reload(),
        ),
        data: (List<FavoriteProvider> providers) => providers.isEmpty
            ? EmptyView(
                icon: Icons.favorite_border,
                title: 'Aucun favori',
                description:
                    'Touchez le cœur sur la fiche d’un prestataire pour le '
                    'retrouver ici.',
                actions: <EmptyAction>[
                  EmptyAction(
                    label: 'Chercher un prestataire',
                    onPressed: () => context.go(Routes.search),
                  ),
                ],
              )
            : RefreshIndicator(
                onRefresh: () => ref.read(favoritesProvider.notifier).reload(),
                child: ListView.separated(
                  itemCount: providers.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) =>
                      _FavoriteTile(provider: providers[index]),
                ),
              ),
      ),
    );
  }
}

class _FavoriteTile extends ConsumerWidget {
  const _FavoriteTile({required this.provider});

  final FavoriteProvider provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    // Grisé, pas masqué : l'opacité dit l'indisponibilité sans effacer l'entrée.
    final double opacity = provider.available ? 1 : 0.5;

    return Opacity(
      opacity: opacity,
      child: ListTile(
        leading: ProviderAvatar(name: provider.publicName, radius: 24),
        title: Text(provider.publicName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (provider.categories.isNotEmpty)
              Text(
                provider.categories.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (provider.isNew)
              Text('Nouveau', style: theme.textTheme.bodySmall)
            else
              Row(
                children: <Widget>[
                  Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: theme.colorScheme.tertiary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${provider.score.toStringAsFixed(1)} '
                    '(${provider.reviewsCount})',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            if (!provider.available)
              Text(
                'Indisponible pour le moment',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ),
        trailing: FavoriteButton(providerId: provider.id),
        // La fiche reste accessible : elle explique la situation mieux qu'une
        // ligne de liste.
        onTap: () => context.push(Routes.providerProfileFor(provider.id)),
      ),
    );
  }
}
