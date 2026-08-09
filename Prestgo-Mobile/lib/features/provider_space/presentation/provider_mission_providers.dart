// État des missions côté prestataire (T167, T169, FR-065).
//
// Le tableau de bord est **composé** — il n'existe pas d'endpoint d'agrégation
// (cahier §4.1, écart n°10) : trois providers indépendants, un par bloc, pour
// que l'échec de l'un n'invalide jamais les autres (scénario 5.1). Le planning
// reprend la mécanique des onglets client : un onglet = un appel, tri du
// service conservé.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_list_item.dart';
import 'package:prestgo_mobile/features/notifications/presentation/badge_providers.dart';
import 'package:prestgo_mobile/features/provider_space/data/provider_mission_repository.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_mission_tabs.dart';

/// Liste paginée d'un onglet du planning — un appel, tri croissant du service.
class ProviderMissionTabController extends PagedNotifier<MissionListItem> {
  ProviderMissionTabController(this.tab);

  final ProviderMissionTab tab;

  @override
  Future<PagedPage<MissionListItem>> fetchPage({
    required int page,
    required int limit,
  }) => ref
      .read(providerMissionRepositoryProvider)
      .missions(statuses: tab.statuses, page: page, limit: limit);

  @override
  Future<PagedState<MissionListItem>> build() async {
    try {
      return await super.build();
    } on ApiException catch (error) {
      // Hors ligne, le planning du dernier chargement vaut mieux qu'une
      // erreur : c'est l'agenda qu'on consulte sur place (data-model §12).
      if (tab == ProviderMissionTab.planning && error.isNetwork) {
        final CachedValue<List<MissionListItem>>? cached = await ref
            .read(providerMissionRepositoryProvider)
            .cachedPlanning();
        if (cached != null) {
          return PagedState<MissionListItem>(
            items: cached.value,
            page: 1,
            limit: cached.value.length,
            total: cached.value.length,
          );
        }
      }
      rethrow;
    }
  }
}

final providerMissionTabProvider =
    AsyncNotifierProvider.family<
      ProviderMissionTabController,
      PagedState<MissionListItem>,
      ProviderMissionTab
    >(ProviderMissionTabController.new);

/// Bloc « en attente de mon action » — compteur = `meta.total`, jamais un
/// comptage local.
final FutureProvider<PagedPage<MissionListItem>> pendingRequestsProvider =
    FutureProvider<PagedPage<MissionListItem>>(
      (Ref ref) => ref
          .watch(providerMissionRepositoryProvider)
          .missions(statuses: ProviderMissionTab.requests.statuses),
    );

/// Bloc « missions du jour » — `from` et `to` au même jour, la borne `to` est
/// inclusive côté service.
final FutureProvider<PagedPage<MissionListItem>> todayMissionsProvider =
    FutureProvider<PagedPage<MissionListItem>>((Ref ref) {
      final DateTime today = DateTime.now();
      return ref
          .watch(providerMissionRepositoryProvider)
          .missions(
            statuses: ProviderMissionTab.planning.statuses,
            from: today,
            to: today,
            limit: 50,
          );
    });

/// Bloc « non lus » — pastille du centre de notifications.
///
/// Branché sur le compteur **commun** de T198 depuis l'arrivée du centre : le
/// dépôt provisoire de `provider_space` a rendu la route à `features/
/// notifications`. L'alias survit pour que le tableau de bord garde des blocs
/// indépendants et nommés (scénario 5.1).
final FutureProvider<int> dashboardUnreadProvider = FutureProvider<int>(
  (Ref ref) => ref.watch(notificationsUnreadCountProvider.future),
);

/// Recharge les trois blocs du tableau de bord et les onglets du planning.
///
/// Une seule fonction, comme `invalidateAfterMissionWrite` côté missions :
/// éparpiller les `invalidate` garantirait qu'un écran en oublie un.
void invalidateProviderMissionReads(WidgetRef ref) {
  ref
    ..invalidate(pendingRequestsProvider)
    ..invalidate(todayMissionsProvider)
    // Le compteur commun est la source ; l'alias du bloc suit tout seul.
    ..invalidate(notificationsUnreadCountProvider)
    ..invalidate(providerMissionTabProvider);
}
