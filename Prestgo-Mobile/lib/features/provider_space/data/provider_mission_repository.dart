// Missions côté prestataire — opération 33 (T166), cache persistant de la
// première page du planning, et compteurs du tableau de bord (T167, FR-065).
//
// `GET /providers/me/missions` accepte exactement les mêmes paramètres que
// `GET /me/missions` et renvoie le même `MissionListItemDto` — seule différence,
// décisive : le tri par défaut est `scheduledAt` **croissant** (le prestataire
// veut voir ce qui arrive, pas son historique), servi tel quel et jamais
// recalculé (FR-038). Le cache le conserve sous le rôle `provider`, séparé du
// cache client : les deux tris sont opposés, même pour un compte à double
// casquette.
//
// Les **transitions** (accepter, refuser, démarrer, terminer, annuler) vivent
// dans `features/missions/data/mission_transition_controller.dart` (T174) : les
// routes `/missions/{id}/*` appartiennent à la fonctionnalité commune `missions`
// — c'est son écran de détail qui porte les boutons — et la règle
// `cross_feature_data` interdit à `missions` d'importer ce dépôt-ci.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_list_item.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_mission_tabs.dart';

class ProviderMissionRepository {
  const ProviderMissionRepository(this._client, this._cache);

  final ApiClient _client;
  final CacheDao _cache;

  /// `GET /providers/me/missions` — opération 33.
  ///
  /// [statuses] est joint en une **liste dans le même paramètre** — un bloc du
  /// tableau de bord ou un onglet = un appel (FR-065). [from] et [to] partent
  /// en `AAAA-MM-JJ` ; la borne [to] est **inclusive** — le bloc « missions du
  /// jour » envoie le même jour aux deux bornes, c'est le service qui ajoute le
  /// jour.
  Future<PagedPage<MissionListItem>> missions({
    required List<MissionStatus> statuses,
    int page = PaginationLimits.firstPage,
    int limit = PaginationLimits.defaultPageSize,
    DateTime? from,
    DateTime? to,
  }) async {
    final ApiEnvelope<List<JsonMap>> envelope = await _client
        .get<List<JsonMap>>(
          '/providers/me/missions',
          query: <String, Object?>{
            if (statuses.isNotEmpty)
              'status': statuses.map((MissionStatus s) => s.apiValue).join(','),
            if (from != null) 'from': MissionDates.toApiDate(from),
            if (to != null) 'to': MissionDates.toApiDate(to),
            'page': page,
            'limit': limit,
          },
          parse: parseList<JsonMap>((JsonMap json) => json),
        );

    final List<JsonMap> payloads = envelope.data ?? const <JsonMap>[];
    final List<MissionListItem> items = payloads
        .map(MissionListItem.fromJson)
        .toList(growable: false);

    // Seule la première page du planning est conservée : l'agenda — ce que le
    // terrain consulte hors ligne (data-model §12), dans le tri du service.
    if (page == PaginationLimits.firstPage &&
        from == null &&
        to == null &&
        _isPlanningFilter(statuses)) {
      await _writeListCache(payloads, items);
    }

    return PagedPage<MissionListItem>(items: items, meta: envelope.meta);
  }

  /// Première page du planning du dernier chargement, avec son âge.
  Future<CachedValue<List<MissionListItem>>?> cachedPlanning() async {
    final CachedValue<List<JsonMap>>? cached = await _cache.readMissions(
      MissionCacheRole.provider,
    );
    return cached?.map(
      (List<JsonMap> payloads) =>
          payloads.map(MissionListItem.fromJson).toList(growable: false),
    );
  }

  // Le compteur de notifications non lues, hébergé ici en attendant le centre
  // de notifications, est reparti à T196 : `NotificationRepository.unreadCount`
  // (`features/notifications/data`). Le bloc du tableau de bord lit désormais
  // le compteur commun de T198 (`notificationsUnreadCountProvider`).

  Future<void> _writeListCache(
    List<JsonMap> payloads,
    List<MissionListItem> items,
  ) => _cache.writeMissions(
    MissionCacheRole.provider,
    <({String id, String status, DateTime scheduledAt, JsonMap payload})>[
      for (int i = 0; i < items.length; i++)
        (
          id: items[i].id,
          status: items[i].rawStatus,
          scheduledAt:
              items[i].scheduledAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          payload: payloads[i],
        ),
    ],
    fetchedAt: DateTime.now(),
  );

  static bool _isPlanningFilter(List<MissionStatus> statuses) {
    final Set<MissionStatus> requested = statuses.toSet();
    return requested.length == ProviderMissionTab.planning.statuses.length &&
        requested.containsAll(ProviderMissionTab.planning.statuses);
  }
}

final Provider<ProviderMissionRepository> providerMissionRepositoryProvider =
    Provider<ProviderMissionRepository>(
      (Ref ref) => ProviderMissionRepository(
        ref.watch(apiClientProvider),
        ref.watch(cacheDaoProvider),
      ),
    );
