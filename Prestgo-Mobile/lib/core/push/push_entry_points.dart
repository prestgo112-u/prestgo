// Câblage des trois points d'entrée d'un push (T201, contracts/push-payloads.md §3).
//
//   1. **Premier plan** — bannière interne + rafraîchissement des compteurs et de
//      l'écran concerné ; **jamais** de navigation forcée ;
//   2. **Arrière-plan, notification touchée** — routage immédiat ;
//   3. **Application tuée, ouverte par la notification** — message initial, routé
//      **après** l'initialisation du routeur (destination différée de T203).
//
// La classe ne décide rien : elle relie les flux du transport aux réactions que
// la couche applicative lui confie (`lib/app/push_driver.dart`).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/push/push_service.dart';

class PushEntryPoints {
  PushEntryPoints(this._messenger);

  final PushMessenger _messenger;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  /// Attache les deux flux ; à appeler une seule fois par vie d'application.
  void bind({
    required void Function(PushMessage message) onForeground,
    required void Function(PushMessage message) onOpened,
  }) {
    _subscriptions
      ..add(_messenger.foregroundMessages.listen(onForeground))
      ..add(_messenger.openedMessages.listen(onOpened));
  }

  /// Notification qui a ouvert l'application tuée, s'il y en a une.
  Future<PushMessage?> takeInitialMessage() => _messenger.initialMessage();

  void dispose() {
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}

/// « Une notification vient d'arriver au premier plan. »
///
/// Les compteurs (badge du centre, pastille messagerie) et les écrans concernés
/// écoutent ce signal pour se rafraîchir (FR-082) — le socle ne connaît aucun
/// d'entre eux. [last] porte la dernière charge reçue.
class ReceivedPushSignal extends Notifier<int> {
  PushMessage? last;

  @override
  int build() => 0;

  void publish(PushMessage message) {
    last = message;
    state++;
  }
}

final NotifierProvider<ReceivedPushSignal, int> receivedPushSignalProvider =
    NotifierProvider<ReceivedPushSignal, int>(ReceivedPushSignal.new);
