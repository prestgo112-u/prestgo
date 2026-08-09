// Tableau de bord prestataire (T167, FR-065, scénario 5.1).
//
// Il n'existe pas d'endpoint d'agrégation : le tableau se **compose** de blocs
// alimentés par des providers **indépendants** — demandes en attente, missions
// du jour, non-lus. L'échec d'un bloc affiche SON erreur avec SA reprise, et
// n'empêche jamais les autres de s'afficher : un prestataire dont le compteur
// de notifications est en panne doit quand même voir la demande qui expire dans
// une heure.
//
// L'interrupteur de disponibilité est en évidence (cahier §4.1) : c'est le
// réglage d'exploitation du quotidien, et son explication — « Occupé » reste
// réservable, « Indisponible » retire de la recherche — est portée par le
// composant partagé (scénario 5.6).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/features/auth/presentation/logout_action.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_list_item.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_overview_controller.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/availability_switch.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/provider_mission_providers.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/widgets/provider_mission_tile.dart';

class ProviderDashboardScreen extends ConsumerWidget {
  const ProviderDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(
      title: const Text('Tableau de bord'),
      actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.person_outline),
          tooltip: 'Mon profil',
          onPressed: () => context.push(Routes.profile),
        ),
        const LogoutAction(),
      ],
    ),
    body: RefreshIndicator(
      onRefresh: () async {
        invalidateProviderMissionReads(ref);
        ref.invalidate(providerOverviewProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: const <Widget>[
          _AvailabilityCard(),
          SizedBox(height: 12),
          _PendingRequestsBlock(),
          SizedBox(height: 12),
          _TodayMissionsBlock(),
          SizedBox(height: 12),
          _UnreadBlock(),
          SizedBox(height: 12),
          _NavigationCard(),
        ],
      ),
    ),
  );
}

/// L'interrupteur de disponibilité, en évidence.
///
/// Son échec de chargement est compact : le reste du tableau vit sans lui.
class _AvailabilityCard extends ConsumerWidget {
  const _AvailabilityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<ProviderProfile> overview = ref.watch(
      providerOverviewProvider,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Ma disponibilité', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            switch (overview) {
              AsyncValue<ProviderProfile>(:final ProviderProfile value) =>
                AvailabilityControl(profile: value),
              AsyncValue<ProviderProfile>(hasError: true) => _InlineBlockError(
                message: 'Disponibilité indisponible pour le moment.',
                onRetry: () =>
                    ref.read(providerOverviewProvider.notifier).reload(),
              ),
              _ => const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              ),
            },
          ],
        ),
      ),
    );
  }
}

/// Bloc « en attente de mon action » — le plus important du tableau.
class _PendingRequestsBlock extends ConsumerWidget {
  const _PendingRequestsBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PagedPage<MissionListItem>> requests = ref.watch(
      pendingRequestsProvider,
    );

    return _DashboardBlock(
      title: 'Demandes en attente',
      // Le compteur est `meta.total` — jamais un comptage local.
      count: requests.value?.meta?.total,
      child: requests.when(
        loading: () => const _BlockLoading(),
        error: (Object error, StackTrace _) => _InlineBlockError(
          message: error is ApiException
              ? error.message
              : ApiFallbackMessages.unknown,
          onRetry: () => ref.invalidate(pendingRequestsProvider),
        ),
        data: (PagedPage<MissionListItem> page) => page.items.isEmpty
            ? const _BlockEmpty(message: 'Aucune demande en attente.')
            : Column(
                children: <Widget>[
                  for (final MissionListItem mission in page.items)
                    ProviderMissionTile(mission: mission),
                ],
              ),
      ),
    );
  }
}

/// Bloc « missions du jour ».
class _TodayMissionsBlock extends ConsumerWidget {
  const _TodayMissionsBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PagedPage<MissionListItem>> today = ref.watch(
      todayMissionsProvider,
    );

    return _DashboardBlock(
      title: 'Missions du jour',
      count: today.value?.meta?.total,
      child: today.when(
        loading: () => const _BlockLoading(),
        error: (Object error, StackTrace _) => _InlineBlockError(
          message: error is ApiException
              ? error.message
              : ApiFallbackMessages.unknown,
          onRetry: () => ref.invalidate(todayMissionsProvider),
        ),
        data: (PagedPage<MissionListItem> page) => page.items.isEmpty
            ? const _BlockEmpty(message: 'Aucune mission pour aujourd’hui.')
            : Column(
                children: <Widget>[
                  for (final MissionListItem mission in page.items)
                    ProviderMissionTile(mission: mission),
                ],
              ),
      ),
    );
  }
}

/// Bloc « non lus » — pastille vers le centre de notifications.
class _UnreadBlock extends ConsumerWidget {
  const _UnreadBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<int> unread = ref.watch(dashboardUnreadProvider);

    return Card(
      child: unread.when(
        loading: () => const ListTile(
          leading: Icon(Icons.notifications_outlined),
          title: Text('Notifications'),
          trailing: SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (Object error, StackTrace _) => ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications'),
          subtitle: const Text('Compteur indisponible pour le moment.'),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Réessayer le compteur',
            onPressed: () => ref.invalidate(dashboardUnreadProvider),
          ),
        ),
        data: (int count) => ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('Notifications'),
          trailing: count == 0
              ? const Icon(Icons.chevron_right)
              : Badge(
                  label: Text('$count'),
                  backgroundColor: theme.colorScheme.error,
                ),
          onTap: () => context.push(Routes.notifications),
        ),
      ),
    );
  }
}

/// Entrées vers le reste de l'espace prestataire.
class _NavigationCard extends StatelessWidget {
  const _NavigationCard();

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.calendar_month_outlined),
          title: const Text('Planning et demandes'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.providerMissions),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.storefront_outlined),
          title: const Text('Mon profil prestataire'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.providerProfileSpace),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.chat_bubble_outline),
          title: const Text('Messagerie'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.threads),
        ),
        const Divider(height: 1),
        // La vie de l'offre après approbation (US8, T210 à T216).
        ListTile(
          leading: const Icon(Icons.handyman_outlined),
          title: const Text('Mes prestations'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.providerServices),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.map_outlined),
          title: const Text('Zones d’intervention'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.providerZones),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.schedule_outlined),
          title: const Text('Agenda hebdomadaire'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.providerAvailabilities),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.event_busy_outlined),
          title: const Text('Absences exceptionnelles'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.providerUnavailabilities),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Mes réalisations'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.providerPortfolio),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Justificatifs'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(Routes.providerDocuments),
        ),
      ],
    ),
  );
}

class _DashboardBlock extends StatelessWidget {
  const _DashboardBlock({required this.title, required this.child, this.count});

  final String title;
  final int? count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                  if (count case final int total when total > 0)
                    Badge.count(
                      count: total,
                      backgroundColor: theme.colorScheme.tertiary,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            child,
          ],
        ),
      ),
    );
  }
}

class _BlockLoading extends StatelessWidget {
  const _BlockLoading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _BlockEmpty extends StatelessWidget {
  const _BlockEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Text(
      message,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// Erreur d'UN bloc : son message, sa reprise — les autres blocs vivent.
class _InlineBlockError extends StatelessWidget {
  const _InlineBlockError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
          TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}
