// Missions côté client — opérations 32, 34, 35 et 40 (T125), cache persistant de
// la première page et des détails (T135).
//
// Deux décisions structurantes :
//
//   • **un onglet = un appel** : `status` accepte une liste séparée par des
//     virgules (`completed,closed`), et `meta.total` reflète l'union. Fusionner
//     plusieurs appels côté client serait à la fois plus lent et faux (écart n°7
//     clos, scénario 3.1) ;
//   • **le tri est celui du service** — `scheduledAt` décroissant côté client —
//     et n'est jamais recalculé (FR-038). Le cache le conserve tel quel.
//
// Le cache ne retient que la **première page de l'onglet « À venir »** — l'agenda,
// ce qu'on consulte sur place quand le réseau manque (data-model §12) — et chaque
// détail ouvert. `POST /missions/{id}/cancel` est une transition : jamais rejouée
// (porte G4), suivie d'une invalidation du détail et des listes.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/missions/domain/cancellation.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_detail.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_history.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_list_item.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';

class MissionRepository {
  const MissionRepository(this._client, this._cache);

  final ApiClient _client;
  final CacheDao _cache;

  /// `GET /me/missions` — opération 32.
  ///
  /// [statuses] est joint en une **liste dans le même paramètre**, jamais en
  /// plusieurs appels. [from] et [to] partent en `AAAA-MM-JJ` ; la borne [to] est
  /// **inclusive** — c'est le service qui ajoute le jour, pas l'application.
  Future<PagedPage<MissionListItem>> myMissions({
    required List<MissionStatus> statuses,
    int page = PaginationLimits.firstPage,
    int limit = PaginationLimits.defaultPageSize,
    DateTime? from,
    DateTime? to,
  }) async {
    final ApiEnvelope<List<JsonMap>> envelope = await _client
        .get<List<JsonMap>>(
          '/me/missions',
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

    // Seule la première page de l'onglet « À venir » est conservée : c'est
    // l'agenda — ce que le terrain consulte hors ligne (data-model §12).
    if (page == PaginationLimits.firstPage &&
        from == null &&
        to == null &&
        _isUpcomingFilter(statuses)) {
      await _writeListCache(payloads, items);
    }

    return PagedPage<MissionListItem>(items: items, meta: envelope.meta);
  }

  /// Première page « À venir » du dernier chargement, avec son âge.
  Future<CachedValue<List<MissionListItem>>?> cachedUpcoming() async {
    final CachedValue<List<JsonMap>>? cached = await _cache.readMissions(
      MissionCacheRole.client,
    );
    return cached?.map(
      (List<JsonMap> payloads) =>
          payloads.map(MissionListItem.fromJson).toList(growable: false),
    );
  }

  /// `GET /missions/{id}` — opération 34, accessible aux deux parties.
  Future<MissionDetail> detail(String missionId) async {
    final ApiEnvelope<JsonMap> envelope = await _client.get<JsonMap>(
      '/missions/$missionId',
      parse: parseObject<JsonMap>((JsonMap json) => json),
    );
    final JsonMap payload = envelope.requireData;
    final MissionDetail detail = MissionDetail.fromJson(payload);
    await _cache.writeMissionDetail(
      id: detail.id,
      payload: payload,
      fetchedAt: DateTime.now(),
    );
    return detail;
  }

  /// Détail du dernier chargement, avec son âge — adresse et instructions
  /// consultables sur place, réseau faible.
  Future<CachedValue<MissionDetail>?> cachedDetail(String missionId) async {
    final CachedValue<JsonMap>? cached = await _cache.readMissionDetail(
      missionId,
    );
    return cached?.map(MissionDetail.fromJson);
  }

  /// `GET /missions/{id}/history` — opération 35, non paginé.
  Future<MissionHistory> history(String missionId) async {
    final ApiEnvelope<MissionHistory> envelope = await _client
        .get<MissionHistory>(
          '/missions/$missionId/history',
          parse: parseStructured<MissionHistory>(MissionHistory.fromJson),
        );
    return envelope.requireData;
  }

  /// `POST /missions/{id}/cancel` — opération 40, motif obligatoire.
  ///
  /// Transition : **jamais rejouée** automatiquement (porte G4). Le verdict de
  /// tardiveté est celui du service ; le message renvoyé est affiché tel quel.
  Future<CancellationResult> cancel(
    String missionId, {
    required String reason,
    String? details,
  }) async {
    final ApiEnvelope<JsonMap> envelope = await _client.post<JsonMap>(
      '/missions/$missionId/cancel',
      body: <String, Object?>{'reason': reason, 'details': ?details},
      parse: parseObject<JsonMap>((JsonMap json) => json),
    );
    // Le statut vient de changer : ce que le cache porte est faux.
    await _cache.invalidateMissionDetail(missionId);
    await _cache.invalidateMissions(MissionCacheRole.client);
    return CancellationResult.fromJson(
      envelope.data ?? const <String, Object?>{},
      message: envelope.message ?? 'Mission annulée',
    );
  }

  Future<void> _writeListCache(
    List<JsonMap> payloads,
    List<MissionListItem> items,
  ) => _cache.writeMissions(
    MissionCacheRole.client,
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

  static bool _isUpcomingFilter(List<MissionStatus> statuses) {
    final Set<MissionStatus> requested = statuses.toSet();
    return requested.length == MissionTab.upcoming.statuses.length &&
        requested.containsAll(MissionTab.upcoming.statuses);
  }
}

final Provider<MissionRepository> missionRepositoryProvider =
    Provider<MissionRepository>(
      (Ref ref) => MissionRepository(
        ref.watch(apiClientProvider),
        ref.watch(cacheDaoProvider),
      ),
    );
