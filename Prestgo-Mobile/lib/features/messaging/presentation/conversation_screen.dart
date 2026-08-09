// Écran de conversation (T183, T186, T187 — FR-075, FR-078, FR-079).
//
// Trois décisions structurantes :
//
//   • **ouvre sur les récents** : la liste est inversée et servie par
//     `sort=-createdAt` — l'historique se charge en remontant, page par page
//     (écart n°12 clos, scénario 6.1) ;
//   • **la saisie se masque en amont** sur un fil non ouvert, avec explication —
//     le 400 « Conversation clôturée » du service n'est qu'un filet (6.4) ;
//   • **marquage lu à l'ouverture**, puis répercussion sur la liste des fils et la
//     pastille globale (table d'invalidation de api-consumption.md, 6.2).
//
// Aucun temps réel : les rafraîchissements sont l'ouverture, le geste, le retour
// au premier plan et le signal de notification (`ConversationRefreshDriver`).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/files/file_avatar.dart';
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/messaging/domain/message.dart';
import 'package:prestgo_mobile/features/messaging/presentation/conversation_refresh.dart';
import 'package:prestgo_mobile/features/messaging/presentation/message_composer.dart';
import 'package:prestgo_mobile/features/messaging/presentation/message_send_controller.dart';
import 'package:prestgo_mobile/features/messaging/presentation/messaging_providers.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({required this.threadId, this.missionId, super.key});

  final String threadId;

  /// Mission porteuse, quand l'appelant la connaît (`?mission=`).
  final String? missionId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final ScrollController _scroll = ScrollController();

  ConversationArgs get _args =>
      (threadId: widget.threadId, missionId: widget.missionId);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Marquage lu à l'ouverture (FR-079) — au mieux, sans bloquer l'affichage.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        markThreadRead(ref, widget.threadId);
      }
    });
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// La liste étant inversée, la fin du défilement est le **passé** : approcher
  /// le haut de l'écran charge la page d'historique suivante (6.1).
  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    final double remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 400) {
      ref.read(conversationProvider(widget.threadId).notifier).loadMore();
    }
  }

  /// Geste de rafraîchissement : recharge les récents puis marque lu (FR-080).
  Future<void> _refresh() async {
    await ref.read(conversationProvider(widget.threadId).notifier).refresh();
    if (mounted) {
      await markThreadRead(ref, widget.threadId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PagedState<Message>> messages = ref.watch(
      conversationProvider(widget.threadId),
    );
    final ConversationInfo? info = ref
        .watch(conversationInfoProvider(_args))
        .value;
    final List<OutgoingMessage> outgoing = ref.watch(
      messageSendControllerProvider(widget.threadId),
    );
    final String? meId = ref.watch(meControllerProvider).value?.id;

    return Scaffold(
      appBar: AppBar(title: Text(info?.title ?? 'Conversation')),
      body: ConversationRefreshDriver(
        threadId: widget.threadId,
        child: Column(
          children: <Widget>[
            Expanded(
              child: messages.when(
                loading: () =>
                    const LoadingView(label: 'Chargement des messages…'),
                error: (Object error, StackTrace _) => ErrorView(
                  message: error is ApiException
                      ? error.message
                      : ApiFallbackMessages.unknown,
                  onRetry: _refresh,
                ),
                data: (PagedState<Message> state) => _MessageList(
                  state: state,
                  outgoing: outgoing,
                  meId: meId,
                  threadId: widget.threadId,
                  scroll: _scroll,
                  onRefresh: _refresh,
                  composerVisible: info?.isOpen ?? true,
                ),
              ),
            ),
            // Tant que le statut du fil est inconnu, ni saisie ni explication :
            // afficher une saisie qui disparaît serait pire qu'une courte attente.
            if (info != null)
              info.isOpen
                  ? MessageComposer(threadId: widget.threadId)
                  : const _ClosedThreadBanner(),
          ],
        ),
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.state,
    required this.outgoing,
    required this.meId,
    required this.threadId,
    required this.scroll,
    required this.onRefresh,
    required this.composerVisible,
  });

  final PagedState<Message> state;
  final List<OutgoingMessage> outgoing;
  final String? meId;
  final String threadId;
  final ScrollController scroll;
  final Future<void> Function() onRefresh;
  final bool composerVisible;

  @override
  Widget build(BuildContext context) {
    if (state.isEmpty && outgoing.isEmpty) {
      return EmptyView(
        icon: Icons.forum_outlined,
        title: 'Aucun message',
        description: composerVisible
            ? 'Écrivez le premier message de cette conversation.'
            : null,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: scroll,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // Bulles sortantes (les plus récentes, en bas) + messages + pied
        // d'historique (visuellement en haut).
        itemCount: outgoing.length + state.items.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index < outgoing.length) {
            // La dernière bulle envoyée est la plus basse (indice 0 du renversé).
            return _OutgoingBubble(
              outgoing: outgoing[outgoing.length - 1 - index],
              threadId: threadId,
            );
          }
          final int messageIndex = index - outgoing.length;
          if (messageIndex == state.items.length) {
            return _HistoryFooter(state: state, threadId: threadId);
          }
          return _MessageBubble(message: state.items[messageIndex], meId: meId);
        },
      ),
    );
  }
}

/// Tête du fil — chargement de l'historique en cours, reprise, ou son début.
class _HistoryFooter extends ConsumerWidget {
  const _HistoryFooter({required this.state, required this.threadId});

  final PagedState<Message> state;
  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (state.loadMoreError != null) {
      return Center(
        child: TextButton.icon(
          onPressed: () =>
              ref.read(conversationProvider(threadId).notifier).loadMore(),
          icon: const Icon(Icons.refresh),
          label: const Text('Réessayer le chargement'),
        ),
      );
    }
    if (!state.hasMore && state.items.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Début de la conversation',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return const SizedBox(height: 8);
  }
}

/// Fil non ouvert : la saisie est masquée, avec explication (FR-078, 6.4).
class _ClosedThreadBanner extends StatelessWidget {
  const _ClosedThreadBanner();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              Icon(Icons.lock_outline, color: theme.colorScheme.outline),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Conversation clôturée : il n’est plus possible d’écrire. '
                  'Les échanges restent consultables.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.meId});

  final Message message;
  final String? meId;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    // Message système : centré, discret — « Mission confirmée. ».
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Text(
            message.message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }

    final bool mine = meId != null && message.isMine(meId!);
    final ColorScheme scheme = theme.colorScheme;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final FileRef file in message.files)
              _AttachmentPreview(file: file),
            if (message.message.isNotEmpty) Text(message.message),
            const SizedBox(height: 2),
            Text(
              DateLabels.time(message.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pièce jointe d'un message reçu ou confirmé.
///
/// Les images s'affichent en vignette — protégées, donc lisibles avec jeton et
/// jamais écrites sur disque (porte G6) ; les autres types montrent leur nom.
class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.file});

  final FileRef file;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (file.isImage) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: RemoteFileImage(
            fileId: file.id,
            visibility: file.visibility,
            width: 200,
            height: 150,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.attach_file, size: 16, color: theme.colorScheme.outline),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              file.originalName,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bulle d'un message en cours d'envoi ou en échec (T185, scénario 6.3).
class _OutgoingBubble extends ConsumerWidget {
  const _OutgoingBubble({required this.outgoing, required this.threadId});

  final OutgoingMessage outgoing;
  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool failed = outgoing.isFailed;

    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.78,
            ),
            decoration: BoxDecoration(
              color: failed
                  ? scheme.errorContainer
                  : scheme.primaryContainer.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(outgoing.text),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (failed)
                      Icon(Icons.error_outline, size: 14, color: scheme.error)
                    else
                      const SizedBox.square(
                        dimension: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    const SizedBox(width: 4),
                    Text(
                      failed ? 'Échec de l’envoi' : 'Envoi en cours…',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: failed ? scheme.error : scheme.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (failed)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextButton(
                  onPressed: () => ref
                      .read(messageSendControllerProvider(threadId).notifier)
                      .discard(outgoing.localId),
                  child: const Text('Abandonner'),
                ),
                // Renvoi MANUEL — le seul rejeu permis sur cette route (FR-077).
                TextButton.icon(
                  onPressed: () => ref
                      .read(messageSendControllerProvider(threadId).notifier)
                      .resend(outgoing.localId),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Renvoyer'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
