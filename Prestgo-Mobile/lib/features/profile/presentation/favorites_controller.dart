// Favoris : état, bascule optimiste, et bouton cœur (T104, FR-021).
//
// L'affichage est **optimiste** : le cœur change à l'instant du geste, l'appel part
// derrière. C'est justifié ici et nulle part ailleurs, parce que les deux routes sont
// idempotentes par construction — un doublon d'appel ne produit aucune erreur, et une
// reprise donne le même résultat. En cas d'échec réel, l'état revient en arrière.
//
// Le cœur n'est pas affiché sur sa **propre** fiche : le service refuserait
// « Vous ne pouvez pas vous ajouter à vos propres favoris », et devancer ce refus vaut
// mieux que de l'afficher.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/features/auth/presentation/auth_wall.dart';
import 'package:prestgo_mobile/features/profile/data/favorites_repository.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';

class FavoritesController extends AsyncNotifier<List<FavoriteProvider>> {
  @override
  Future<List<FavoriteProvider>> build() async {
    // Les favoris appartiennent à un compte : sans session, la liste est vide et
    // aucun appel n'est fait.
    if (!ref.watch(sessionControllerProvider).isAuthenticated) {
      return const <FavoriteProvider>[];
    }
    return ref.read(favoritesRepositoryProvider).list();
  }

  bool contains(String providerId) =>
      state.value?.any((FavoriteProvider p) => p.id == providerId) ?? false;

  /// Ajoute ou retire, en mettant l'écran à jour immédiatement.
  ///
  /// Renvoie l'état final du cœur. Sur échec, l'état d'origine est rétabli et
  /// l'exception remonte à l'appelant, qui affiche le message.
  Future<bool> toggle(String providerId) async {
    final List<FavoriteProvider> current =
        state.value ?? const <FavoriteProvider>[];
    final bool wasFavorite = contains(providerId);

    // Bascule optimiste. Le retrait est complet ; l'ajout ne peut poser qu'un
    // marqueur, faute de connaître la fiche — la liste sera relue.
    state = AsyncValue<List<FavoriteProvider>>.data(
      wasFavorite
          ? <FavoriteProvider>[
              for (final FavoriteProvider provider in current)
                if (provider.id != providerId) provider,
            ]
          : <FavoriteProvider>[
              ...current,
              FavoriteProvider(
                id: providerId,
                publicName: '',
                score: 0,
                reviewsCount: 0,
                available: true,
                favoritedAt: DateTime.now(),
              ),
            ],
    );

    try {
      final FavoritesRepository repository = ref.read(
        favoritesRepositoryProvider,
      );
      if (wasFavorite) {
        await repository.remove(providerId);
      } else {
        await repository.add(providerId);
      }
      // Relecture : elle apporte le nom, la note et la disponibilité que la
      // bascule optimiste ne pouvait pas deviner.
      state = await AsyncValue.guard<List<FavoriteProvider>>(repository.list);
      return !wasFavorite;
    } on ApiException {
      state = AsyncValue<List<FavoriteProvider>>.data(current);
      rethrow;
    }
  }

  Future<void> reload() async {
    state = await AsyncValue.guard<List<FavoriteProvider>>(
      ref.read(favoritesRepositoryProvider).list,
    );
  }
}

final AsyncNotifierProvider<FavoritesController, List<FavoriteProvider>>
favoritesProvider =
    AsyncNotifierProvider<FavoritesController, List<FavoriteProvider>>(
      FavoritesController.new,
    );

/// Bouton cœur — et mur d'authentification quand il n'y a pas de session.
///
/// Le retour se fait sur la route courante, paramètres compris : après connexion,
/// l'utilisateur revient exactement là où il était (FR-028).
class FavoriteButton extends ConsumerWidget {
  const FavoriteButton({required this.providerId, super.key});

  final String providerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Observer la session garde le cœur en phase avec elle : une déconnexion le
    // remet à vide sans qu'il faille quitter l'écran.
    ref.watch(sessionControllerProvider);

    // Sur sa propre fiche, le cœur n'a pas de sens.
    final String? myProviderId = ref
        .watch(meControllerProvider)
        .value
        ?.providerId;
    if (myProviderId != null && myProviderId == providerId) {
      return const SizedBox.shrink();
    }

    final bool isFavorite = ref
        .watch(favoritesProvider.notifier)
        .contains(providerId);
    // Observer la liste garde le bouton en phase avec elle.
    ref.watch(favoritesProvider);

    return IconButton(
      icon: Icon(isFavorite ? Icons.favorite : Icons.favorite_border),
      tooltip: isFavorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
      color: isFavorite ? Theme.of(context).colorScheme.error : null,
      onPressed: () async {
        // Mur d'authentification : la route courante est mémorisée, et l'on y
        // revient après connexion (FR-028).
        if (!requireSession(context, ref)) {
          return;
        }
        try {
          await ref.read(favoritesProvider.notifier).toggle(providerId);
        } on ApiException catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(error.message)));
          }
        }
      },
    );
  }
}
