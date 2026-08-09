// Fiche prestataire (T102, FR-027).
//
// **Un seul chargement** compose tout l'écran. C'est une exigence de réseau mobile
// avant d'être une exigence d'ergonomie : neuf appels feraient apparaître la fiche
// section par section, chacune avec son propre risque d'échec.
//
// Consultable sans compte (FR-022). Les deux seules actions qui exigent une session —
// mettre en favori, réserver — passent par le mur d'authentification, qui ramène
// ensuite **sur cette même fiche** (FR-028, scénario 2.4).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/files/file_avatar.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/format/money.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/auth/presentation/auth_wall.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_rules.dart';
import 'package:prestgo_mobile/features/profile/presentation/favorites_controller.dart';
import 'package:prestgo_mobile/features/search/data/search_repository.dart';
import 'package:prestgo_mobile/features/search/domain/catalog.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';

/// Fiche publique d'un prestataire, chargée une fois.
final providerProfileProvider =
    FutureProvider.family<ProviderPublicProfile, String>(
      (Ref ref, String providerId) =>
          ref.watch(searchRepositoryProvider).publicProfile(providerId),
    );

class ProviderProfileScreen extends ConsumerWidget {
  const ProviderProfileScreen({required this.providerId, super.key});

  final String providerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ProviderPublicProfile> profile = ref.watch(
      providerProfileProvider(providerId),
    );

    return Scaffold(
      body: profile.when(
        loading: () =>
            const Scaffold(body: LoadingView(label: 'Chargement de la fiche…')),
        error: (Object error, StackTrace _) => Scaffold(
          appBar: AppBar(),
          body: ErrorView(
            message: error is ApiException
                ? error.message
                : ApiFallbackMessages.unknown,
            onRetry: () => ref.invalidate(providerProfileProvider(providerId)),
          ),
        ),
        data: (ProviderPublicProfile provider) =>
            _ProfileBody(provider: provider),
      ),
      bottomNavigationBar: profile.maybeWhen(
        data: (ProviderPublicProfile provider) =>
            provider.isBookable ? _BookingBar(provider: provider) : null,
        orElse: () => null,
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.provider});

  final ProviderPublicProfile provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CustomScrollView(
    slivers: <Widget>[
      SliverAppBar(
        pinned: true,
        title: Text(provider.publicName),
        actions: <Widget>[FavoriteButton(providerId: provider.id)],
      ),
      SliverList(
        delegate: SliverChildListDelegate(<Widget>[
          _Header(provider: provider),
          const Divider(height: 32),
          if (provider.bio case final String bio) ...<Widget>[
            const _SectionTitle('Présentation'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(bio),
            ),
            const SizedBox(height: 24),
          ],
          if (provider.services.isNotEmpty) ...<Widget>[
            const _SectionTitle('Prestations et tarifs'),
            for (final PublicService service in provider.services)
              _ServiceBlock(service: service),
            const SizedBox(height: 16),
          ],
          if (provider.portfolio.isNotEmpty) ...<Widget>[
            const _SectionTitle('Réalisations'),
            _Portfolio(items: provider.portfolio),
            const SizedBox(height: 24),
          ],
          if (provider.availability.isNotEmpty) ...<Widget>[
            const _SectionTitle('Disponibilités'),
            _Availability(provider: provider),
            const SizedBox(height: 24),
          ],
          if (provider.zones.isNotEmpty) ...<Widget>[
            const _SectionTitle('Zones d’intervention'),
            _Zones(zones: provider.zones),
            const SizedBox(height: 24),
          ],
          const _SectionTitle('Avis'),
          _Reviews(provider: provider),
          const SizedBox(height: 32),
        ]),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.provider});

  final ProviderPublicProfile provider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ProviderAvatar(
            fileId: provider.avatarFileId,
            name: provider.publicName,
            radius: 36,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(provider.publicName, style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                // « Nouveau » plutôt qu'une note de 0 (FR-026).
                if (provider.isNew)
                  Chip(
                    label: const Text('Nouveau'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.secondaryContainer,
                  )
                else
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.star_rounded,
                        size: 20,
                        color: theme.colorScheme.tertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(provider.score.toStringAsFixed(1)),
                      const SizedBox(width: 6),
                      Text(
                        '(${provider.reviewsCount} avis)',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                const SizedBox(height: 6),
                if (provider.experienceYears case final int years)
                  Text(
                    '$years ans d’expérience',
                    style: theme.textTheme.bodySmall,
                  ),
                Text(
                  'Sur PRESTGO depuis ${DateLabels.dayWithYear(provider.memberSince)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (provider.categories.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: <Widget>[
                      for (final Category category in provider.categories)
                        Chip(
                          label: Text(category.name),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceBlock extends StatelessWidget {
  const _ServiceBlock({required this.service});

  final PublicService service;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(service.title, style: theme.textTheme.titleSmall),
          if (service.description case final String description)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(description, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          for (final ServicePack pack in service.packs)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(child: Text(pack.title)),
                        Text(
                          Money.format(pack.price),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      BookingRules.formatDuration(pack.durationMinutes),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (pack.options.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Text('Options', style: theme.textTheme.labelMedium),
                      for (final PackOption option in pack.options)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  option.title,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                '+ ${Money.format(option.price)}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Portfolio extends StatelessWidget {
  const _Portfolio({required this.items});

  final List<PortfolioItem> items;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 140,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(width: 12),
      itemBuilder: (BuildContext context, int index) {
        final PortfolioItem item = items[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 180,
            child: item.fileId == null
                ? ColoredBox(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Icons.image_outlined)),
                  )
                // Les réalisations sont publiques : visibles sans compte.
                : RemoteFileImage.public(fileId: item.fileId!),
          ),
        );
      },
    ),
  );
}

class _Availability extends StatelessWidget {
  const _Availability({required this.provider});

  final ProviderPublicProfile provider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // 0 = dimanche : la convention du service, appliquée telle quelle.
          for (
            int weekday = AppFormats.firstWeekday;
            weekday <= AppFormats.lastWeekday;
            weekday++
          )
            if (provider.slotsForWeekday(weekday)
                case final List<WeeklySlot> slots when slots.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 90,
                      child: Text(
                        Weekdays.label(weekday),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        slots
                            .map(
                              (WeeklySlot slot) =>
                                  '${slot.startTime} – ${slot.endTime}',
                            )
                            .join(', '),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          if (provider.upcomingUnavailabilities.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Text('Absences annoncées', style: theme.textTheme.labelMedium),
            for (final Unavailability absence
                in provider.upcomingUnavailabilities)
              Text(
                'Du ${DateLabels.day(absence.startAt)} au '
                '${DateLabels.day(absence.endAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Zones extends StatelessWidget {
  const _Zones({required this.zones});

  final List<Zone> zones;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final Zone zone in zones)
          Chip(
            avatar: const Icon(Icons.place_outlined, size: 16),
            label: Text(zone.label),
            visualDensity: VisualDensity.compact,
          ),
      ],
    ),
  );
}

class _Reviews extends StatelessWidget {
  const _Reviews({required this.provider});

  final ProviderPublicProfile provider;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (provider.latestReviews.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          'Aucun avis pour le moment.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: <Widget>[
              // Répartition des notes, de 5 à 1.
              for (int rating = 5; rating >= 1; rating--)
                _RatingBar(
                  rating: rating,
                  count: provider.ratingDistribution[rating] ?? 0,
                  total: provider.reviewsCount,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final ProviderReview review in provider.latestReviews)
          ListTile(
            title: Row(
              children: <Widget>[
                Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 4),
                Text('${review.rating}'),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    review.authorLabel,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  DateLabels.day(review.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            subtitle: review.comment == null ? null : Text(review.comment!),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton(
            onPressed: () =>
                context.push(Routes.providerReviewsFor(provider.id)),
            child: Text('Voir les ${provider.reviewsCount} avis'),
          ),
        ),
      ],
    );
  }
}

class _RatingBar extends StatelessWidget {
  const _RatingBar({
    required this.rating,
    required this.count,
    required this.total,
  });

  final int rating;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: <Widget>[
        SizedBox(width: 16, child: Text('$rating')),
        const Icon(Icons.star_rounded, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : count / total,
            minHeight: 6,
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$count',
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    ),
  );
}

/// Barre de réservation, ancrée en bas.
class _BookingBar extends ConsumerWidget {
  const _BookingBar({required this.provider});

  final ProviderPublicProfile provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: <Widget>[
            if (provider.startingPrice case final int price)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text('À partir de', style: theme.textTheme.bodySmall),
                    Text(
                      Money.format(price),
                      style: theme.textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            FilledButton(
              // Réserver exige une session. Le mur mémorise **cette fiche** et y
              // ramène après connexion — pas l'écran de réservation, que
              // l'utilisateur n'avait pas encore ouvert (scénario 2.4).
              onPressed: () {
                if (!requireSession(context, ref)) {
                  return;
                }
                context.push(Routes.bookingFor(provider.id));
              },
              style: FilledButton.styleFrom(minimumSize: const Size(180, 52)),
              child: const Text('Réserver'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Text(label, style: Theme.of(context).textTheme.titleMedium),
  );
}
