// Mes missions — quatre onglets, un appel par onglet (T127, FR-037, FR-038).
//
// Chaque onglet est construit en **un seul appel** grâce au filtre `status`
// multi-valeurs (`completed,closed`), et `meta.total` reflète l'union — le total
// affiché est celui du service, pas un comptage local (scénario 3.1).
//
// Le tri est celui du service — plus récentes d'abord côté client — et n'est
// **jamais** recalculé (FR-038). L'onglet « À venir » hors ligne est servi par le
// cache de la première page : l'agenda reste consultable sur place.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/connectivity/reconnect_refresher.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/files/file_avatar.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/format/money.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/widgets/data_age_label.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_list_item.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_providers.dart';

class MyMissionsScreen extends StatelessWidget {
  const MyMissionsScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: MissionTab.values.length,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Mes missions'),
        bottom: TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: <Widget>[
            for (final MissionTab tab in MissionTab.values)
              Tab(text: tab.label),
          ],
        ),
      ),
      body: TabBarView(
        children: <Widget>[
          for (final MissionTab tab in MissionTab.values)
            _MissionTabView(tab: tab),
        ],
      ),
    ),
  );
}

class _MissionTabView extends ConsumerStatefulWidget {
  const _MissionTabView({required this.tab});

  final MissionTab tab;

  @override
  ConsumerState<_MissionTabView> createState() => _MissionTabViewState();
}

class _MissionTabViewState extends ConsumerState<_MissionTabView>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();

  // Garder l'onglet vivant évite de rappeler le service à chaque va-et-vient
  // entre les onglets — le rafraîchissement reste au geste.
  @override
  bool get wantKeepAlive => true;

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
    super.dispose();
  }

  /// Charge la page suivante avant d'atteindre le bas — `loadMore` est déjà
  /// protégé contre les rafales.
  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    final double remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 400) {
      ref.read(missionTabProvider(widget.tab).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final AsyncValue<PagedState<MissionListItem>> missions = ref.watch(
      missionTabProvider(widget.tab),
    );

    // Au retour du réseau, l'onglet affiché se relit tout seul (10.3).
    return RefreshOnReconnect(
      onReconnect: () => ref.invalidate(missionTabProvider(widget.tab)),
      child: _buildTab(missions),
    );
  }

  Widget _buildTab(AsyncValue<PagedState<MissionListItem>> missions) {
    return missions.when(
      loading: () => const LoadingView(label: 'Chargement de vos missions…'),
      error: (Object error, StackTrace _) => ErrorView(
        message: error is ApiException
            ? error.message
            : ApiFallbackMessages.unknown,
        onRetry: () =>
            ref.read(missionTabProvider(widget.tab).notifier).refresh(),
      ),
      data: (PagedState<MissionListItem> state) {
        if (state.isEmpty) {
          return EmptyView(
            icon: Icons.event_note_outlined,
            title: widget.tab.emptyMessage,
            description: widget.tab == MissionTab.upcoming
                ? 'Réservez une prestation pour la retrouver ici.'
                : null,
            actions: <EmptyAction>[
              // L'onglet À venir incite à réserver ; les autres constatent.
              if (widget.tab == MissionTab.upcoming)
                EmptyAction(
                  label: 'Réserver une prestation',
                  onPressed: () => context.go(Routes.search),
                ),
            ],
          );
        }
        // Hors ligne, l'agenda servi par le cache s'affiche AVEC son âge
        // (10.1) : jamais une donnée d'hier présentée comme fraîche.
        final bool online = ref.watch(isOnlineProvider).value ?? true;
        final AsyncValue<DateTime?> fetchedAt = ref.watch(
          upcomingMissionsFetchedAtProvider,
        );
        if (!online &&
            widget.tab == MissionTab.upcoming &&
            fetchedAt.value != null) {
          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: DataAgeLabel(fetchedAt: fetchedAt.value!),
              ),
              Expanded(child: _list(state)),
            ],
          );
        }
        return _list(state);
      },
    );
  }

  Widget _list(PagedState<MissionListItem> state) {
    return RefreshIndicator(
      onRefresh: () =>
          ref.read(missionTabProvider(widget.tab).notifier).refresh(),
      child: ListView.separated(
        controller: _scroll,
        // Une ligne de plus pour le pied — chargement ou reprise.
        itemCount: state.items.length + 1,
        separatorBuilder: (BuildContext context, int index) =>
            const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          if (index == state.items.length) {
            return _ListFooter(
              isLoadingMore: state.isLoadingMore,
              hasError: state.loadMoreError != null,
              onRetry: () =>
                  ref.read(missionTabProvider(widget.tab).notifier).loadMore(),
            );
          }
          return MissionTile(mission: state.items[index]);
        },
      ),
    );
  }
}

/// Ligne de mission — statut, horaire, formule, prestataire, montant.
class MissionTile extends StatelessWidget {
  const MissionTile({required this.mission, super.key});

  final MissionListItem mission;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? scheduledAt = mission.scheduledAt;

    return ListTile(
      leading: ProviderAvatar(name: mission.providerName, radius: 24),
      title: Text(
        mission.packTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            mission.providerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (scheduledAt != null)
            Text(
              '${DateLabels.dayAndTime(scheduledAt)} · ${mission.locality}',
              style: theme.textTheme.bodySmall,
            ),
          _StatusChip(mission: mission),
        ],
      ),
      // « — » quand le montant n'existe pas, jamais « 0 XOF » (data-model §5.1).
      trailing: Text(
        Money.formatOrAbsent(mission.quotedAmount),
        style: theme.textTheme.labelLarge,
      ),
      isThreeLine: true,
      onTap: () => context.push(Routes.missionDetailFor(mission.id)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.mission});

  final MissionListItem mission;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = switch (mission.status) {
      MissionStatus.pendingProvider => scheme.tertiary,
      MissionStatus.confirmed || MissionStatus.inProgress => scheme.primary,
      MissionStatus.completed || MissionStatus.closed => scheme.secondary,
      MissionStatus.cancelled || MissionStatus.disputed => scheme.error,
      MissionStatus.draft || MissionStatus.unknown => scheme.outline,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        mission.statusLabel,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({
    required this.isLoadingMore,
    required this.hasError,
    required this.onRetry,
  });

  final bool isLoadingMore;
  final bool hasError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (hasError) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer le chargement'),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}
