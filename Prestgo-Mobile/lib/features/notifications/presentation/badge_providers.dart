// Pastille de notifications non lues et ses moments de rafraîchissement
// (T198, FR-082).
//
// Trois déclencheurs, et seulement eux — aucune interrogation périodique :
//   1. **le démarrage** — la première lecture du provider ;
//   2. **le retour au premier plan** — l'observateur de cycle de vie ;
//   3. **la réception d'une notification** — le signal du socle, levé par le
//      pilote push au premier plan (`lib/app/push_driver.dart`).
//
// Le compte vient de la route légère dédiée (`unread-count`), jamais d'un
// comptage de la liste. Persistance : mémoire seulement (data-model §12).

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/push/push_entry_points.dart';
import 'package:prestgo_mobile/features/notifications/data/notification_repository.dart';

class NotificationsBadge extends AsyncNotifier<int> {
  @override
  Future<int> build() async {
    // Réception d'une notification au premier plan → relire le compte.
    ref.listen<int>(receivedPushSignalProvider, (int? previous, int next) {
      refresh();
    });

    // Retour au premier plan → relire le compte.
    final _ResumeObserver observer = _ResumeObserver(onResume: refresh);
    final WidgetsBinding binding = WidgetsBinding.instance;
    binding.addObserver(observer);
    ref.onDispose(() => binding.removeObserver(observer));

    return ref.read(notificationRepositoryProvider).unreadCount();
  }

  /// Relit le compteur sans passer par un état de chargement visible :
  /// une pastille qui clignote à chaque rafraîchissement serait du bruit.
  Future<void> refresh() async {
    final AsyncValue<int> next = await AsyncValue.guard<int>(
      () => ref.read(notificationRepositoryProvider).unreadCount(),
    );
    // Un échec de rafraîchissement conserve la dernière valeur connue.
    if (next is AsyncData<int>) {
      state = next;
    }
  }
}

/// Compteur global de notifications non lues — la pastille (FR-082).
final AsyncNotifierProvider<NotificationsBadge, int>
notificationsUnreadCountProvider =
    AsyncNotifierProvider<NotificationsBadge, int>(NotificationsBadge.new);

/// À appeler après toute écriture qui change le compte (marquage lu, action de
/// mission) — la table d'invalidation de api-consumption.md.
void refreshNotificationBadges(WidgetRef ref) =>
    ref.invalidate(notificationsUnreadCountProvider);

class _ResumeObserver with WidgetsBindingObserver {
  _ResumeObserver({required this.onResume});

  final void Function() onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}
