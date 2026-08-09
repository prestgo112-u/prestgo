// Planning et demandes (T169, FR-038, FR-043).
//
// Trois onglets — demandes à traiter, planning, historique — chacun construit
// en **un appel** grâce au filtre `status` multi-valeurs. Le tri est celui du
// service : `scheduledAt` **croissant**, ce qui arrive d'abord en premier —
// l'inverse exact du client — et il n'est **jamais** recalculé. Le planning
// hors ligne est servi par le cache de la première page : l'agenda reste
// consultable sur place.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_list_item.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_mission_tabs.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/provider_mission_providers.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/widgets/provider_mission_tile.dart';

class ProviderMissionsScreen extends StatelessWidget {
  const ProviderMissionsScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: ProviderMissionTab.values.length,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Planning et demandes'),
        bottom: TabBar(
          tabs: <Widget>[
            for (final ProviderMissionTab tab in ProviderMissionTab.values)
              Tab(text: tab.label),
          ],
        ),
      ),
      body: TabBarView(
        children: <Widget>[
          for (final ProviderMissionTab tab in ProviderMissionTab.values)
            _ProviderMissionTabView(tab: tab),
        ],
      ),
    ),
  );
}

class _ProviderMissionTabView extends ConsumerStatefulWidget {
  const _ProviderMissionTabView({required this.tab});

  final ProviderMissionTab tab;

  @override
  ConsumerState<_ProviderMissionTabView> createState() =>
      _ProviderMissionTabViewState();
}

class _ProviderMissionTabViewState
    extends ConsumerState<_ProviderMissionTabView>
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
      ref.read(providerMissionTabProvider(widget.tab).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final AsyncValue<PagedState<MissionListItem>> missions = ref.watch(
      providerMissionTabProvider(widget.tab),
    );

    return missions.when(
      loading: () => const LoadingView(label: 'Chargement de vos missions…'),
      error: (Object error, StackTrace _) => ErrorView(
        message: error is ApiException
            ? error.message
            : ApiFallbackMessages.unknown,
        onRetry: () =>
            ref.read(providerMissionTabProvider(widget.tab).notifier).refresh(),
      ),
      data: (PagedState<MissionListItem> state) {
        if (state.isEmpty) {
          return EmptyView(
            icon: Icons.event_note_outlined,
            title: widget.tab.emptyMessage,
            description: widget.tab == ProviderMissionTab.requests
                ? 'Les nouvelles demandes de réservation arrivent ici.'
                : null,
          );
        }
        return RefreshIndicator(
          onRefresh: () => ref
              .read(providerMissionTabProvider(widget.tab).notifier)
              .refresh(),
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
                  onRetry: () => ref
                      .read(providerMissionTabProvider(widget.tab).notifier)
                      .loadMore(),
                );
              }
              return ProviderMissionTile(mission: state.items[index]);
            },
          ),
        );
      },
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
