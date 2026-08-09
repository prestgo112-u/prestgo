// Centre de notifications — opérations 54 à 57 (T196).
//
// Trois règles du service, prises au mot :
//   • `unread=true|false` part **explicitement** — le paramètre est transformé
//     côté serveur, `"false"` est bien compris comme faux ;
//   • le marquage lu est **idempotent** : déjà lue, inexistante ou à autrui →
//     `{ updated: 0 }`, jamais d'erreur — la mise à jour optimiste est sans
//     risque ;
//   • il n'existe **aucune route de suppression** (FR-081).
//
// Persistance : mémoire seulement (data-model §12) — les notifications sont
// volatiles par nature, aucune table de cache ne les porte.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/notifications/domain/app_notification.dart';

/// Issue du marquage global — le message du service porte le compte exact.
class ReadAllResult {
  const ReadAllResult({required this.updated, required this.message});

  final int updated;

  /// « n notification(s) marquée(s) lue(s) » — affiché tel quel (FR-088).
  final String message;
}

class NotificationRepository {
  const NotificationRepository(this._client);

  final ApiClient _client;

  /// `GET /me/notifications` — opération 54, paginée.
  ///
  /// [unreadOnly] à `true` restreint aux non-lues ; `null` n'envoie pas le
  /// paramètre (toutes).
  Future<PagedPage<AppNotification>> notifications({
    int page = PaginationLimits.firstPage,
    int limit = PaginationLimits.defaultPageSize,
    bool? unreadOnly,
  }) async {
    final ApiEnvelope<List<JsonMap>> envelope = await _client
        .get<List<JsonMap>>(
          '/me/notifications',
          query: <String, Object?>{
            if (unreadOnly != null) 'unread': unreadOnly.toString(),
            'page': page,
            'limit': limit,
          },
          parse: parseList<JsonMap>((JsonMap json) => json),
        );
    final List<AppNotification> items = (envelope.data ?? const <JsonMap>[])
        .map(AppNotification.fromJson)
        .toList(growable: false);
    return PagedPage<AppNotification>(items: items, meta: envelope.meta);
  }

  /// `GET /me/notifications/unread-count` — opération 55, la pastille.
  Future<int> unreadCount() async {
    final ApiEnvelope<JsonMap> envelope = await _client.get<JsonMap>(
      '/me/notifications/unread-count',
      parse: parseObject<JsonMap>((JsonMap json) => json),
    );
    return switch (envelope.requireData['unread']) {
      final int v => v,
      final num v => v.toInt(),
      _ => 0,
    };
  }

  /// `PATCH /me/notifications/{id}/read` — opération 56, idempotente.
  Future<int> markRead(String notificationId) async {
    final ApiEnvelope<JsonMap> envelope = await _client.patch<JsonMap>(
      '/me/notifications/$notificationId/read',
      parse: parseObject<JsonMap>((JsonMap json) => json),
    );
    return switch (envelope.data?['updated']) {
      final int v => v,
      final num v => v.toInt(),
      _ => 0,
    };
  }

  /// `POST /me/notifications/read-all` — opération 57.
  Future<ReadAllResult> markAllRead() async {
    final ApiEnvelope<JsonMap> envelope = await _client.post<JsonMap>(
      '/me/notifications/read-all',
      parse: parseObject<JsonMap>((JsonMap json) => json),
    );
    return ReadAllResult(
      updated: switch (envelope.data?['updated']) {
        final int v => v,
        final num v => v.toInt(),
        _ => 0,
      },
      message: envelope.message ?? 'Notifications marquées lues',
    );
  }
}

final Provider<NotificationRepository> notificationRepositoryProvider =
    Provider<NotificationRepository>(
      (Ref ref) => NotificationRepository(ref.watch(apiClientProvider)),
    );
