// Liste des conversations et pastille globale (T182, FR-074).
//
// Chaque ligne porte l'interlocuteur — déjà résolu du bon côté par le service —,
// l'aperçu du dernier message et le compteur de non-lus du fil. La pastille
// globale vient de sa route dédiée (écart n°4 clos), jamais d'une somme locale.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/files/file_avatar.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/messaging/domain/thread.dart';
import 'package:prestgo_mobile/features/messaging/presentation/messaging_providers.dart';

class ThreadsScreen extends ConsumerStatefulWidget {
  const ThreadsScreen({super.key});

  @override
  ConsumerState<ThreadsScreen> createState() => _ThreadsScreenState();
}

class _ThreadsScreenState extends ConsumerState<ThreadsScreen> {
  final ScrollController _scroll = ScrollController();

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

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    final double remaining =
        _scroll.position.maxScrollExtent - _scroll.position.pixels;
    if (remaining < 400) {
      ref.read(threadsProvider.notifier).loadMore();
    }
  }

  Future<void> _refresh() {
    ref.invalidate(threadsUnreadCountProvider);
    return ref.read(threadsProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PagedState<Thread>> threads = ref.watch(threadsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messagerie'),
        actions: <Widget>[_GlobalUnreadBadge()],
      ),
      body: threads.when(
        loading: () =>
            const LoadingView(label: 'Chargement de vos conversations…'),
        error: (Object error, StackTrace _) => ErrorView(
          message: error is ApiException
              ? error.message
              : ApiFallbackMessages.unknown,
          onRetry: _refresh,
        ),
        data: (PagedState<Thread> state) {
          if (state.isEmpty) {
            return const EmptyView(
              icon: Icons.chat_bubble_outline,
              title: 'Aucune conversation',
              description:
                  'Une conversation s’ouvre avec chaque mission réservée.',
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              controller: _scroll,
              itemCount: state.items.length + 1,
              separatorBuilder: (BuildContext context, int index) =>
                  const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) {
                if (index == state.items.length) {
                  return _ListFooter(
                    isLoadingMore: state.isLoadingMore,
                    hasError: state.loadMoreError != null,
                    onRetry: () =>
                        ref.read(threadsProvider.notifier).loadMore(),
                  );
                }
                return _ThreadTile(thread: state.items[index]);
              },
            ),
          );
        },
      ),
    );
  }
}

/// Pastille globale — la somme exacte des non-lus, servie par le service.
class _GlobalUnreadBadge extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int unread = ref.watch(threadsUnreadCountProvider).value ?? 0;
    if (unread == 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: Center(
        child: Badge.count(
          count: unread,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile({required this.thread});

  final Thread thread;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ThreadLastMessage? last = thread.lastMessage;
    final bool hasUnread = thread.unreadCount > 0;

    return ListTile(
      leading: ProviderAvatar(
        name: thread.counterpartName,
        fileId: thread.counterpartAvatarFileId,
        radius: 24,
      ),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              thread.counterpartName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: hasUnread
                  ? const TextStyle(fontWeight: FontWeight.bold)
                  : null,
            ),
          ),
          if (last?.createdAt case final DateTime at)
            Text(
              DateLabels.dayAndTime(at),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
      subtitle: Text(
        last?.message ?? 'Conversation ouverte',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: hasUnread ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      trailing: hasUnread
          ? Badge.count(
              count: thread.unreadCount,
              backgroundColor: theme.colorScheme.error,
            )
          : thread.isOpen
          ? const Icon(Icons.chevron_right)
          // Le fil reste consultable : clôturé n'est jamais masqué (FR-078).
          : Icon(Icons.lock_outline, color: theme.colorScheme.outline),
      onTap: () => context.push(
        Routes.conversationFor(thread.id, missionId: thread.missionId),
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
