// Déclencheurs de rafraîchissement d'une conversation (T188, FR-080).
//
// Aucun flux temps réel, aucune interrogation périodique. Quatre moments, et
// seulement eux :
//   1. l'ouverture               — le chargement initial du provider ;
//   2. le geste                  — le `RefreshIndicator` de l'écran ;
//   3. le retour au premier plan — l'observateur de cycle de vie ci-dessous ;
//   4. une notification `chat`   — le signal ci-dessous, actionné par le routage
//      des notifications (T203, US7) et par les parcours de test.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/features/messaging/presentation/messaging_providers.dart';

/// « Un message est arrivé sur ce fil. »
///
/// Le routage des notifications le lèvera à la réception d'une charge utile
/// `chat` portant ce `threadId` (T203) ; l'écran de conversation y répond en
/// rechargeant le fil. D'ici là, seuls les tests l'actionnent.
class ChatMessageSignal extends Notifier<int> {
  ChatMessageSignal(this.threadId);

  final String threadId;

  @override
  int build() => 0;

  void notify() => state++;
}

final chatMessageSignalProvider =
    NotifierProvider.family<ChatMessageSignal, int, String>(
      ChatMessageSignal.new,
    );

/// Recharge le fil sur retour au premier plan et sur signal de message.
///
/// Enveloppe la liste des messages sans rien afficher de plus : le geste de
/// rafraîchissement et l'ouverture restent portés par l'écran.
class ConversationRefreshDriver extends ConsumerStatefulWidget {
  const ConversationRefreshDriver({
    required this.threadId,
    required this.child,
    super.key,
  });

  final String threadId;
  final Widget child;

  @override
  ConsumerState<ConversationRefreshDriver> createState() =>
      _ConversationRefreshDriverState();
}

class _ConversationRefreshDriverState
    extends ConsumerState<ConversationRefreshDriver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  /// Recharge la page des messages récents puis marque lu : ce qui vient
  /// d'arriver est sous les yeux du lecteur (FR-079).
  Future<void> _refresh() async {
    await ref.read(conversationProvider(widget.threadId).notifier).refresh();
    if (!mounted) {
      return;
    }
    await markThreadRead(ref, widget.threadId);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(chatMessageSignalProvider(widget.threadId), (
      int? previous,
      int next,
    ) {
      _refresh();
    });
    return widget.child;
  }
}
