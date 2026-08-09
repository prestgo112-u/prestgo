// Centre de notifications (T197, FR-081).
//
// Quatre règles, prises au service :
//   • liste **paginée**, filtrable sur les non-lues (`unread=true` explicite) ;
//   • marquage **unitaire optimiste** — l'idempotence du service le rend sans
//     risque : déjà lue, inexistante → `{ updated: 0 }`, jamais d'erreur ;
//   • marquage **global**, dont le message du service est affiché tel quel ;
//   • **aucune suppression** — la route n'existe pas, l'affordance non plus.
//
// Le tap sur une ligne route par la MÊME fonction qu'un push (FR-083) : la
// charge utile `data` est identique dans les deux canaux.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/app/push_driver.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/push/notification_payload.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/notifications/data/notification_repository.dart';
import 'package:prestgo_mobile/features/notifications/domain/app_notification.dart';
import 'package:prestgo_mobile/features/notifications/presentation/badge_providers.dart';

/// Liste paginée du centre — une famille par filtre (toutes / non lues).
class NotificationsController extends PagedNotifier<AppNotification> {
  NotificationsController(this.unreadOnly);

  final bool unreadOnly;

  @override
  Future<PagedPage<AppNotification>> fetchPage({
    required int page,
    required int limit,
  }) => ref
      .read(notificationRepositoryProvider)
      .notifications(
        page: page,
        limit: limit,
        // `unread=true` part explicitement ; sans filtre, le paramètre ne part pas.
        unreadOnly: unreadOnly ? true : null,
      );

  /// Marquage unitaire **optimiste** (FR-081).
  ///
  /// L'écran change immédiatement ; l'appel part ensuite, et son échec est
  /// silencieux — l'idempotence du service rend l'écart sans conséquence, le
  /// prochain rafraîchissement resservira l'état exact.
  void markRead(AppNotification notification) {
    if (notification.isRead) {
      return;
    }
    final PagedState<AppNotification>? current = state.value;
    if (current != null) {
      state = AsyncData<PagedState<AppNotification>>(
        current.copyWith(
          items: unreadOnly
              // Dans la vue « non lues », une notification lue sort de la liste.
              ? current.items
                    .where((AppNotification n) => n.id != notification.id)
                    .toList(growable: false)
              : <AppNotification>[
                  for (final AppNotification n in current.items)
                    n.id == notification.id ? n.asRead(DateTime.now()) : n,
                ],
          total: unreadOnly ? current.total - 1 : current.total,
        ),
      );
    }
    unawaited(_persistMarkRead(notification.id));
  }

  Future<void> _persistMarkRead(String id) async {
    try {
      await ref.read(notificationRepositoryProvider).markRead(id);
    } on ApiException {
      // Optimisme assumé : le service est idempotent, le compte se recalera.
    }
    ref.invalidate(notificationsUnreadCountProvider);
  }

  /// Marquage global — le message du service porte le compte exact (FR-088).
  Future<String> markAllRead() async {
    final ReadAllResult result = await ref
        .read(notificationRepositoryProvider)
        .markAllRead();
    await refresh();
    ref.invalidate(notificationsUnreadCountProvider);
    return result.message;
  }
}

final notificationsProvider =
    AsyncNotifierProvider.family<
      NotificationsController,
      PagedState<AppNotification>,
      bool
    >(NotificationsController.new);

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  final ScrollController _scroll = ScrollController();
  bool _unreadOnly = false;

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
      ref.read(notificationsProvider(_unreadOnly).notifier).loadMore();
    }
  }

  Future<void> _refresh() {
    ref.invalidate(notificationsUnreadCountProvider);
    return ref.read(notificationsProvider(_unreadOnly).notifier).refresh();
  }

  Future<void> _markAllRead() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final String message = await ref
          .read(notificationsProvider(_unreadOnly).notifier)
          .markAllRead();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PagedState<AppNotification>> notifications = ref.watch(
      notificationsProvider(_unreadOnly),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Tout marquer lu',
            onPressed: _markAllRead,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: FilterChip(
                label: const Text('Non lues seulement'),
                selected: _unreadOnly,
                onSelected: (bool selected) =>
                    setState(() => _unreadOnly = selected),
              ),
            ),
          ),
          Expanded(
            child: notifications.when(
              loading: () =>
                  const LoadingView(label: 'Chargement des notifications…'),
              error: (Object error, StackTrace _) => ErrorView(
                message: error is ApiException
                    ? error.message
                    : ApiFallbackMessages.unknown,
                onRetry: _refresh,
              ),
              data: (PagedState<AppNotification> state) {
                if (state.isEmpty) {
                  return EmptyView(
                    icon: Icons.notifications_none_outlined,
                    title: _unreadOnly
                        ? 'Aucune notification non lue'
                        : 'Aucune notification',
                    description: _unreadOnly
                        ? 'Tout est lu — les prochaines arriveront ici.'
                        : 'Les évènements de vos missions arriveront ici.',
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
                          onRetry: () => ref
                              .read(notificationsProvider(_unreadOnly).notifier)
                              .loadMore(),
                        );
                      }
                      return _NotificationTile(
                        notification: state.items[index],
                        unreadOnly: _unreadOnly,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({
    required this.notification,
    required this.unreadOnly,
  });

  final AppNotification notification;
  final bool unreadOnly;

  static IconData _iconFor(NotificationPayload payload) => switch (payload) {
    MissionPayload() => Icons.event_note_outlined,
    ChatPayload() => Icons.chat_bubble_outline,
    ReschedulePayload() => Icons.schedule_outlined,
    ReviewPayload() => Icons.star_border,
    UnknownPayload() => Icons.notifications_none_outlined,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool unread = !notification.isRead;

    return ListTile(
      leading: Icon(
        _iconFor(notification.payload),
        color: unread ? theme.colorScheme.primary : theme.colorScheme.outline,
      ),
      title: Text(
        notification.title,
        style: unread ? const TextStyle(fontWeight: FontWeight.bold) : null,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(notification.body, maxLines: 2, overflow: TextOverflow.ellipsis),
          Text(
            DateLabels.dayAndTime(notification.createdAt),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
      trailing: unread
          ? Icon(Icons.circle, size: 10, color: theme.colorScheme.primary)
          : null,
      isThreeLine: true,
      onTap: () {
        // Marquage optimiste PUIS routage — le même chemin qu'un push (FR-083).
        ref
            .read(notificationsProvider(unreadOnly).notifier)
            .markRead(notification);
        ref.read(notificationRouterProvider).open(notification.data);
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
