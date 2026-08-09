// Messagerie — opérations 48 à 53 (T181), cache persistant par fil (T189).
//
// Trois décisions structurantes :
//
//   • **l'écran ouvre sur les récents** : le tri par défaut du service est
//     croissant — la page 1 est le DÉBUT du fil (écart n°12 clos) — donc la lecture
//     d'écran demande `sort=-createdAt` et l'historique se charge en remontant
//     (FR-075) ;
//   • **le compteur global vient de sa route dédiée** (écart n°4 clos), jamais
//     d'une somme de la première page de `/me/threads` ;
//   • **l'envoi n'est jamais rejoué automatiquement** — pas de clé d'idempotence
//     sur cette route, un rejeu créerait des doublons (porte G4) ; la politique de
//     rejeu du socle l'exclut nommément, l'écran offre un « Renvoyer » manuel.
//
// Le cache retient chaque page lue **et** chaque message envoyé : la relecture
// hors ligne rend le fil dans son ordre naturel (data-model §12).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/messaging/domain/message.dart';
import 'package:prestgo_mobile/features/messaging/domain/thread.dart';

class MessagingRepository {
  const MessagingRepository(this._client, this._cache);

  final ApiClient _client;
  final CacheDao _cache;

  /// `GET /me/threads` — opération 48, l'onglet Messagerie.
  ///
  /// `counterpartName` arrive déjà résolu du bon côté : aucune logique de rôle ici.
  Future<PagedPage<Thread>> threads({
    int page = PaginationLimits.firstPage,
    int limit = PaginationLimits.defaultPageSize,
  }) async {
    final ApiEnvelope<List<JsonMap>> envelope = await _client
        .get<List<JsonMap>>(
          '/me/threads',
          query: <String, Object?>{'page': page, 'limit': limit},
          parse: parseList<JsonMap>((JsonMap json) => json),
        );
    final List<Thread> items = (envelope.data ?? const <JsonMap>[])
        .map(Thread.fromJson)
        .toList(growable: false);
    return PagedPage<Thread>(items: items, meta: envelope.meta);
  }

  /// `GET /me/threads/unread-count` — opération 49, la pastille globale.
  Future<int> unreadCount() async {
    final ApiEnvelope<JsonMap> envelope = await _client.get<JsonMap>(
      '/me/threads/unread-count',
      parse: parseObject<JsonMap>((JsonMap json) => json),
    );
    return switch (envelope.requireData['unread']) {
      final int v => v,
      final num v => v.toInt(),
      _ => 0,
    };
  }

  /// `GET /missions/{id}/thread` — opération 50.
  ///
  /// Le chemin d'entrée depuis le détail d'une mission, sans avoir chargé
  /// `/me/threads`. 404 si la mission n'a pas de conversation.
  Future<MissionThread> threadForMission(String missionId) async {
    final ApiEnvelope<MissionThread> envelope = await _client
        .get<MissionThread>(
          '/missions/$missionId/thread',
          parse: parseObject<MissionThread>(MissionThread.fromJson),
        );
    return envelope.requireData;
  }

  /// `GET /messages/threads/{id}/messages` — opération 51.
  ///
  /// [newestFirst] est le régime de l'écran : `sort=-createdAt`, la page 1 porte la
  /// fin du fil et les pages suivantes remontent l'historique. Sans lui, l'ordre
  /// est celui du service — **croissant**, page 1 = début de la conversation.
  Future<PagedPage<Message>> messages(
    String threadId, {
    int page = PaginationLimits.firstPage,
    int limit = PaginationLimits.defaultPageSize,
    bool newestFirst = true,
  }) async {
    final ApiEnvelope<List<JsonMap>> envelope = await _client
        .get<List<JsonMap>>(
          '/messages/threads/$threadId/messages',
          query: <String, Object?>{
            if (newestFirst) 'sort': '-createdAt',
            'page': page,
            'limit': limit,
          },
          parse: parseList<JsonMap>((JsonMap json) => json),
        );

    final List<JsonMap> payloads = envelope.data ?? const <JsonMap>[];
    final List<Message> items = payloads
        .map(Message.fromJson)
        .toList(growable: false);

    // Chaque page lue rejoint le cache du fil ; l'écriture est idempotente par
    // identifiant, relire une page n'y crée jamais de doublon (T189).
    await _writeToCache(threadId, payloads, items);

    return PagedPage<Message>(items: items, meta: envelope.meta);
  }

  /// Fil du dernier chargement, dans son ordre naturel (croissant), avec son âge.
  Future<CachedValue<List<Message>>?> cachedMessages(String threadId) async {
    final CachedValue<List<JsonMap>>? cached = await _cache.readMessages(
      threadId,
    );
    return cached?.map(
      (List<JsonMap> payloads) =>
          payloads.map(Message.fromJson).toList(growable: false),
    );
  }

  /// `POST /messages/threads/{id}/messages` — opération 52.
  ///
  /// Les plafonds sont appliqués **avant** tout appel réseau (FR-090) ; les pièces
  /// jointes ont été envoyées **au préalable** par `POST /files/upload`, seuls
  /// leurs identifiants partent ici. Jamais rejoué automatiquement : l'appelant
  /// offre un renvoi manuel (FR-077).
  Future<Message> send(
    String threadId, {
    required String text,
    List<String> fileIds = const <String>[],
  }) async {
    if (text.length < ContentLimits.messageMinLength ||
        text.length > ContentLimits.messageMaxLength) {
      throw ArgumentError.value(
        text.length,
        'text',
        'Le message doit compter de ${ContentLimits.messageMinLength} à '
            '${ContentLimits.messageMaxLength} caractères',
      );
    }
    if (fileIds.length > ContentLimits.attachmentsPerMessage) {
      throw ArgumentError.value(
        fileIds.length,
        'fileIds',
        'Pas plus de ${ContentLimits.attachmentsPerMessage} pièces jointes',
      );
    }
    if (fileIds.toSet().length != fileIds.length) {
      throw ArgumentError.value(
        fileIds,
        'fileIds',
        'Le même fichier est joint plusieurs fois',
      );
    }

    final ApiEnvelope<JsonMap> envelope = await _client.post<JsonMap>(
      '/messages/threads/$threadId/messages',
      body: <String, Object?>{
        'message': text,
        if (fileIds.isNotEmpty) 'fileIds': fileIds,
      },
      parse: parseObject<JsonMap>((JsonMap json) => json),
    );

    final JsonMap payload = envelope.requireData;
    final Message sent = Message.fromJson(payload);
    await _writeToCache(threadId, <JsonMap>[payload], <Message>[sent]);
    return sent;
  }

  /// `PATCH /messages/threads/{id}/read` — opération 53, à l'ouverture du fil.
  ///
  /// L'appelant rafraîchit ensuite la liste des fils et le compteur global —
  /// table d'invalidation de api-consumption.md (FR-079).
  Future<int> markRead(String threadId) async {
    final ApiEnvelope<JsonMap> envelope = await _client.patch<JsonMap>(
      '/messages/threads/$threadId/read',
      parse: parseObject<JsonMap>((JsonMap json) => json),
    );
    return switch (envelope.data?['updated']) {
      final int v => v,
      final num v => v.toInt(),
      _ => 0,
    };
  }

  Future<void> _writeToCache(
    String threadId,
    List<JsonMap> payloads,
    List<Message> items,
  ) {
    if (items.isEmpty) {
      return Future<void>.value();
    }
    return _cache.writeMessages(threadId, <
      ({String id, DateTime createdAt, JsonMap payload})
    >[
      for (int i = 0; i < items.length; i++)
        (id: items[i].id, createdAt: items[i].createdAt, payload: payloads[i]),
    ], fetchedAt: DateTime.now());
  }
}

final Provider<MessagingRepository> messagingRepositoryProvider =
    Provider<MessagingRepository>(
      (Ref ref) => MessagingRepository(
        ref.watch(apiClientProvider),
        ref.watch(cacheDaoProvider),
      ),
    );
