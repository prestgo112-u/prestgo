// États de la recherche (T101, FR-025).
//
// L'état **vide** est le seul qui mérite un fichier : une recherche sans résultat
// n'est pas un échec, c'est une situation à laquelle il faut donner une suite. Deux
// suites, précisément — élargir le rayon, ou retirer les filtres — et elles ne sont
// proposées que lorsqu'elles ont un sens : pas de « élargir » sans position, pas de
// « retirer les filtres » quand il n'y en a aucun.
//
// Le chargement et l'erreur réutilisent les composants du socle : les redéfinir ici
// les ferait diverger du reste de l'application.

import 'package:flutter/material.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/features/search/domain/provider_search.dart';

/// Résultat vide, avec les seules suites qui s'appliquent.
class SearchEmptyView extends StatelessWidget {
  const SearchEmptyView({
    required this.query,
    required this.onWidenRadius,
    required this.onClearFilters,
    super.key,
  });

  final ProviderSearchQuery query;
  final VoidCallback onWidenRadius;
  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) => EmptyView(
    icon: Icons.search_off_outlined,
    title: 'Aucun prestataire trouvé',
    description: _description,
    actions: <EmptyAction>[
      if (query.canWidenRadius)
        EmptyAction(
          label: 'Élargir à ${_widenedRadius.round()} km',
          onPressed: onWidenRadius,
        ),
      if (query.hasFilters)
        EmptyAction(label: 'Retirer les filtres', onPressed: onClearFilters),
    ],
  );

  double get _widenedRadius => query.widened().radiusKm;

  /// Le texte dit **pourquoi** c'est vide, quand on peut le savoir.
  String get _description {
    if (query.slot != null) {
      return 'Personne n’est disponible sur ce créneau. Essayez une autre '
          'date ou un autre horaire.';
    }
    if (query.canWidenRadius) {
      return 'Aucun prestataire dans un rayon de ${query.radiusKm.round()} km.';
    }
    if (query.radiusKm >= PaginationLimits.maxRadiusKm) {
      return 'Aucun prestataire dans un rayon de '
          '${PaginationLimits.maxRadiusKm.round()} km, le maximum couvert.';
    }
    return 'Essayez d’élargir votre recherche ou de retirer un filtre.';
  }
}

/// Pied de liste du défilement continu.
///
/// Trois états : plus rien à charger (rien n'est affiché), chargement en cours, ou
/// échec de la page suivante. Ce dernier ne remplace **pas** la liste déjà chargée :
/// il propose une reprise sous elle.
class SearchListFooter extends StatelessWidget {
  const SearchListFooter({
    required this.isLoadingMore,
    required this.hasError,
    required this.onRetry,
    super.key,
  });

  final bool isLoadingMore;
  final bool hasError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox.square(
            dimension: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }
    if (hasError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Charger la suite'),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// Nombre de résultats, affiché au-dessus de la liste.
class SearchResultCount extends StatelessWidget {
  const SearchResultCount({required this.total, super.key});

  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(
      total <= 1 ? '$total prestataire' : '$total prestataires',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}
