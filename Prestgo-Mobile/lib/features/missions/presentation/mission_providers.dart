// État des missions côté client, et invalidations après écriture (T133, FR-050).
//
// Un provider par lecture — un onglet, un détail, un historique, des reports — et
// **une seule** fonction d'invalidation, appelée après chaque écriture. Éparpiller
// les `ref.invalidate` dans les écrans garantirait qu'un jour l'un d'eux oublie la
// liste pendant qu'un autre oublie le détail.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/features/missions/data/mission_repository.dart';
import 'package:prestgo_mobile/features/missions/data/reschedule_repository.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_detail.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_history.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_list_item.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';
import 'package:prestgo_mobile/features/missions/domain/reschedule_request.dart';
import 'package:prestgo_mobile/features/notifications/presentation/badge_providers.dart';

/// Liste paginée d'un onglet — **un appel** par onglet, statuts joints (3.1).
class MissionTabController extends PagedNotifier<MissionListItem> {
  MissionTabController(this.tab);

  final MissionTab tab;

  @override
  Future<PagedPage<MissionListItem>> fetchPage({
    required int page,
    required int limit,
  }) => ref
      .read(missionRepositoryProvider)
      .myMissions(statuses: tab.statuses, page: page, limit: limit);

  @override
  Future<PagedState<MissionListItem>> build() async {
    try {
      // Trace du premier chargement de l'onglet — budget d'écran clé (SC-005).
      return await ref
          .read(errorReporterProvider)
          .traceScreen('screen.missions.${tab.name}', super.build);
    } on ApiException catch (error) {
      // Hors ligne, l'agenda du dernier chargement vaut mieux qu'une erreur :
      // c'est précisément ce que le cache de la première page existe pour servir
      // (data-model §12). Les autres onglets n'ont pas de cache — leur erreur
      // s'affiche.
      if (tab == MissionTab.upcoming && error.isNetwork) {
        final CachedValue<List<MissionListItem>>? cached = await ref
            .read(missionRepositoryProvider)
            .cachedUpcoming();
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

final missionTabProvider =
    AsyncNotifierProvider.family<
      MissionTabController,
      PagedState<MissionListItem>,
      MissionTab
    >(MissionTabController.new);

/// Détail d'une mission, servi par le cache quand le réseau manque.
class MissionDetailController extends AsyncNotifier<MissionDetail> {
  MissionDetailController(this.missionId);

  final String missionId;

  @override
  Future<MissionDetail> build() async {
    final MissionRepository repository = ref.read(missionRepositoryProvider);
    try {
      // Trace du détail de mission — budget d'écran clé (SC-005).
      return await ref
          .read(errorReporterProvider)
          .traceScreen(
            'screen.mission.detail',
            () => repository.detail(missionId),
          );
    } on ApiException catch (error) {
      // Adresse et instructions restent consultables sur place, réseau faible.
      final MissionDetail? cached = (await repository.cachedDetail(
        missionId,
      ))?.value;
      if (cached != null && error.isNetwork) {
        return cached;
      }
      rethrow;
    }
  }
}

final missionDetailProvider =
    AsyncNotifierProvider.family<
      MissionDetailController,
      MissionDetail,
      String
    >(MissionDetailController.new);

/// Date d'obtention de la première page « À venir » en cache — l'âge affiché
/// hors ligne (US10, FR-096).
final FutureProvider<DateTime?>
upcomingMissionsFetchedAtProvider = FutureProvider.autoDispose<DateTime?>(
  (Ref ref) async =>
      (await ref.watch(missionRepositoryProvider).cachedUpcoming())?.fetchedAt,
);

/// Date d'obtention du détail en cache — même usage.
final missionDetailFetchedAtProvider = FutureProvider.autoDispose
    .family<DateTime?, String>(
      (Ref ref, String missionId) async =>
          (await ref.watch(missionRepositoryProvider).cachedDetail(missionId))
              ?.fetchedAt,
    );

/// Historique — alimente la frise chronologique (T129).
final missionHistoryProvider = FutureProvider.family<MissionHistory, String>(
  (Ref ref, String missionId) =>
      ref.watch(missionRepositoryProvider).history(missionId),
);

/// Historique complet des reports d'une mission.
final missionReschedulesProvider =
    FutureProvider.family<List<RescheduleRequest>, String>(
      (Ref ref, String missionId) =>
          ref.watch(rescheduleRepositoryProvider).history(missionId),
    );

/// Invalidation en cascade après une écriture sur une mission (FR-050).
///
/// Annulation, report proposé ou tranché, litige ouvert : dans tous les cas le
/// détail, la frise, les reports et **toutes** les listes d'onglets sont à
/// relire — et le compteur de notifications aussi, l'autre partie étant
/// notifiée de chacune de ces écritures (T198).
void invalidateAfterMissionWrite(WidgetRef ref, String missionId) {
  ref
    ..invalidate(missionDetailProvider(missionId))
    ..invalidate(missionHistoryProvider(missionId))
    ..invalidate(missionReschedulesProvider(missionId))
    ..invalidate(missionTabProvider);
  refreshNotificationBadges(ref);
}
