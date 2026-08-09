// État de la messagerie et invalidations après écriture (FR-050, FR-074, FR-079).
//
// Un provider par lecture — la liste des fils, la pastille globale, un fil — et une
// seule fonction de marquage lu : c'est elle qui applique la table d'invalidation
// de api-consumption.md (`PATCH .../read` → liste des fils + compteur global).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/features/messaging/data/messaging_repository.dart';
import 'package:prestgo_mobile/features/messaging/domain/message.dart';
import 'package:prestgo_mobile/features/messaging/domain/thread.dart';

/// Liste paginée des conversations — l'onglet Messagerie (T182).
class ThreadsController extends PagedNotifier<Thread> {
  @override
  Future<PagedPage<Thread>> fetchPage({
    required int page,
    required int limit,
  }) => ref.read(messagingRepositoryProvider).threads(page: page, limit: limit);
}

final AsyncNotifierProvider<ThreadsController, PagedState<Thread>>
threadsProvider = AsyncNotifierProvider<ThreadsController, PagedState<Thread>>(
  ThreadsController.new,
);

/// Pastille globale de l'onglet Messagerie (FR-074).
///
/// Route dédiée (écart n°4 clos) : jamais une somme de la première page des fils.
final FutureProvider<int> threadsUnreadCountProvider = FutureProvider<int>(
  (Ref ref) => ref.watch(messagingRepositoryProvider).unreadCount(),
);

/// Fil de conversation — ouvre sur les messages **récents**, l'historique se
/// charge en remontant (T183, FR-075).
///
/// Les éléments sont portés du plus récent au plus ancien, l'ordre que sert
/// `sort=-createdAt` : c'est celui d'une liste inversée à l'écran, où la page
/// suivante prolonge le haut (le passé).
class ConversationController extends PagedNotifier<Message> {
  ConversationController(this.threadId);

  final String threadId;

  @override
  Future<PagedPage<Message>> fetchPage({
    required int page,
    required int limit,
  }) => ref
      .read(messagingRepositoryProvider)
      .messages(threadId, page: page, limit: limit);

  @override
  Future<PagedState<Message>> build() async {
    try {
      return await super.build();
    } on ApiException catch (error) {
      // Hors ligne, la relecture du fil vaut mieux qu'une erreur : c'est ce que
      // le cache persistant par fil existe pour servir (T189, data-model §12).
      if (error.isNetwork) {
        final CachedValue<List<Message>>? cached = await ref
            .read(messagingRepositoryProvider)
            .cachedMessages(threadId);
        if (cached != null && cached.value.isNotEmpty) {
          final List<Message> items = cached.value.reversed.toList(
            growable: false,
          );
          return PagedState<Message>(
            items: items,
            page: 1,
            limit: items.length,
            total: items.length,
          );
        }
      }
      rethrow;
    }
  }

  /// Insère un message que le service vient de confirmer (envoi optimiste).
  ///
  /// La bulle « en cours » devient un message ordinaire sans relire la page ;
  /// l'écriture est ignorée si le message est déjà là (rafraîchissement croisé).
  void deliver(Message message) {
    final PagedState<Message>? current = state.value;
    if (current == null) {
      return;
    }
    if (current.items.any((Message m) => m.id == message.id)) {
      return;
    }
    state = AsyncData<PagedState<Message>>(
      current.copyWith(
        items: <Message>[message, ...current.items],
        total: current.total + 1,
      ),
    );
  }
}

final conversationProvider =
    AsyncNotifierProvider.family<
      ConversationController,
      PagedState<Message>,
      String
    >(ConversationController.new);

/// Arguments d'ouverture d'une conversation.
///
/// [missionId] est la mission porteuse quand l'appelant la connaît — détail de
/// mission, notification `chat` — et permet de lire le statut du fil par
/// l'opération 50 sans dépendre de `/me/threads`.
typedef ConversationArgs = ({String threadId, String? missionId});

/// Ce que l'écran de conversation doit savoir de son fil : la saisie est-elle
/// permise (FR-078), et sous quel titre l'afficher.
class ConversationInfo {
  const ConversationInfo({required this.isOpen, this.title});

  final bool isOpen;

  /// Nom de l'interlocuteur, quand la liste des fils l'a fourni.
  final String? title;
}

/// Statut et titre du fil, par la meilleure source disponible.
///
/// 1. La liste des fils — elle porte le nom **et** le statut, et la suivre fait
///    vivre l'info : un fil clôturé entre-temps se reflète au rafraîchissement.
/// 2. La mission porteuse (opération 50) — l'arrivée depuis un détail de mission
///    ou une notification, sans que `/me/threads` soit joignable ou suffisant.
/// 3. Sinon : considéré ouvert. Le service reste le filet à l'envoi
///    (400 « Conversation clôturée » — la capture `send.closed`).
final conversationInfoProvider =
    FutureProvider.family<ConversationInfo, ConversationArgs>((
      Ref ref,
      ConversationArgs args,
    ) async {
      try {
        final PagedState<Thread> threads = await ref.watch(
          threadsProvider.future,
        );
        for (final Thread thread in threads.items) {
          if (thread.id == args.threadId) {
            return ConversationInfo(
              isOpen: thread.isOpen,
              title: thread.counterpartName,
            );
          }
        }
      } on ApiException {
        // Liste injoignable : la mission porteuse reste une source de statut.
      }

      final String? missionId = args.missionId;
      if (missionId != null && missionId.isNotEmpty) {
        try {
          final MissionThread thread = await ref
              .read(messagingRepositoryProvider)
              .threadForMission(missionId);
          return ConversationInfo(isOpen: thread.isOpen);
        } on ApiException {
          // Même filet que ci-dessous.
        }
      }
      return const ConversationInfo(isOpen: true);
    });

/// Marque le fil lu et répercute les compteurs (T187, FR-079).
///
/// Au mieux : hors ligne ou session en cours de renouvellement, l'échec est
/// silencieux — le service resservira le compte exact au prochain passage.
Future<void> markThreadRead(WidgetRef ref, String threadId) async {
  try {
    await ref.read(messagingRepositoryProvider).markRead(threadId);
  } on ApiException {
    return;
  }
  // `PATCH .../read` → liste des fils et compteur global (api-consumption.md).
  ref.invalidate(threadsProvider);
  ref.invalidate(threadsUnreadCountProvider);
}
