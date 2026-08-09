// Carte d'un résultat de recherche (T100, FR-026).
//
// Trois règles d'affichage, toutes des règles de **masquage** :
//   • aucun avis → « Nouveau », jamais une note de 0. Un prestataire qui débute
//     n'est pas un mauvais prestataire ;
//   • aucune position fournie → pas de distance affichée. « 0 km » serait faux ;
//   • aucune formule tarifée → pas de prix d'appel. « 0 F CFA » serait pire que rien.
//
// Chaque valeur absente disparaît donc, au lieu de s'afficher à zéro.

import 'package:flutter/material.dart';
import 'package:prestgo_mobile/core/files/file_avatar.dart';
import 'package:prestgo_mobile/core/format/money.dart';
import 'package:prestgo_mobile/features/search/domain/provider_search.dart';

class ProviderCard extends StatelessWidget {
  const ProviderCard({required this.provider, required this.onTap, super.key});

  final ProviderSearchResult provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      // Rôle de bouton pour la lecture d'écran : la carte entière ouvre la fiche.
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ProviderAvatar(
                  fileId: provider.avatarFileId,
                  name: provider.publicName,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              provider.publicName,
                              style: theme.textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (provider.availableNow) const _AvailableBadge(),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _RatingLine(
                        score: provider.score,
                        reviewsCount: provider.reviewsCount,
                        isNew: provider.isNew,
                      ),
                      if (provider.categories.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          provider.categories.join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          // Prix d'appel : masqué quand le service n'en renvoie pas.
                          if (provider.startingPrice case final int price)
                            Text(
                              'À partir de ${Money.format(price)}',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          const Spacer(),
                          // Distance : masquée sans position demandée.
                          if (provider.distanceKm case final double distance)
                            _Distance(distanceKm: distance),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Note, ou « Nouveau » — jamais les deux, jamais zéro.
class _RatingLine extends StatelessWidget {
  const _RatingLine({
    required this.score,
    required this.reviewsCount,
    required this.isNew,
  });

  final double score;
  final int reviewsCount;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (isNew) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Nouveau',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      );
    }

    // L'étoile est décorative : la lecture d'écran énonce la note en toutes
    // lettres au lieu de « 4.5 (12 avis) ».
    return Semantics(
      label: 'Note ${score.toStringAsFixed(1)} sur 5, $reviewsCount avis',
      excludeSemantics: true,
      child: Row(
        children: <Widget>[
          Icon(Icons.star_rounded, size: 18, color: theme.colorScheme.tertiary),
          const SizedBox(width: 4),
          Text(
            score.toStringAsFixed(1),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($reviewsCount avis)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Distance extends StatelessWidget {
  const _Distance({required this.distanceKm});

  final double distanceKm;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Sous le kilomètre, les mètres parlent davantage.
    final String label = distanceKm < 1
        ? '${(distanceKm * 1000).round()} m'
        : '${distanceKm.toStringAsFixed(1)} km';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.near_me_outlined,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AvailableBadge extends StatelessWidget {
  const _AvailableBadge();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Tooltip(
      message: 'Disponible actuellement',
      child: Icon(Icons.circle, size: 10, color: theme.colorScheme.primary),
    );
  }
}
