// Assemblage des notifications poussées (T199 à T203).
//
// Le socle `core/push/` fournit les pièces — transport, cycle de vie du jeton,
// points d'entrée, bannière, routeur — mais n'a le droit de connaître ni la
// table des routes, ni les dépôts, ni le profil : c'est ICI, dans la couche
// applicative, que tout se relie.
//
//   • [destinationPathFor] — la correspondance charge utile → chemin
//     (contracts/push-payloads.md §1), vérifiée par T194 ;
//   • [pushServiceProvider] — le cycle de vie du jeton, branché sur le dépôt
//     des appareils de `features/notifications` ;
//   • [notificationRouterProvider] — le routage unique, branché sur go_router
//     et différé tant que le profil n'est pas chargé ;
//   • [PushDriver] — le pilote monté au-dessus du routeur : enregistrement à
//     chaque connexion, rotation du jeton, trois points d'entrée, bannière au
//     premier plan sans navigation forcée.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/app/router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/push/foreground_presenter.dart';
import 'package:prestgo_mobile/core/push/notification_payload.dart';
import 'package:prestgo_mobile/core/push/notification_router.dart';
import 'package:prestgo_mobile/core/push/push_entry_points.dart';
import 'package:prestgo_mobile/core/push/push_service.dart';
import 'package:prestgo_mobile/core/session/routing_profile.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/features/messaging/presentation/conversation_refresh.dart';
import 'package:prestgo_mobile/features/messaging/presentation/messaging_providers.dart';
import 'package:prestgo_mobile/features/notifications/data/device_repository.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';

/// Charge utile → chemin — la table du contrat (push-payloads.md §1).
///
/// Une notification `chat` emporte la mission porteuse quand elle est connue :
/// la conversation lira son statut sans dépendre de `/me/threads`.
String destinationPathFor(NotificationPayload payload) => switch (payload) {
  final ChatPayload p => Routes.conversationFor(
    p.threadId,
    missionId: p.missionId,
  ),
  final ReschedulePayload p =>
    '${Routes.missionDetailFor(p.missionId)}'
        '?${Routes.missionTabQueryParameter}=reschedule',
  final ReviewPayload p =>
    '${Routes.missionDetailFor(p.missionId)}'
        '?${Routes.missionTabQueryParameter}=review',
  final MissionPayload p => Routes.missionDetailFor(p.missionId),
  UnknownPayload() => Routes.notifications,
};

/// Le dépôt des appareils, vu par le socle sous son contrat.
final Provider<DeviceRegistrar> deviceRegistrarProvider =
    Provider<DeviceRegistrar>((Ref ref) => ref.watch(deviceRepositoryProvider));

final Provider<PushService> pushServiceProvider = Provider<PushService>(
  (Ref ref) => PushService(
    messenger: ref.watch(pushMessengerProvider),
    registrar: ref.watch(deviceRegistrarProvider),
    tokenStore: ref.watch(secureTokenStoreProvider),
  ),
);

/// Routage unique des notifications — internes et poussées (FR-083).
///
/// La navigation attend le profil : une application tuée, ouverte par une
/// notification, route **après** l'aiguillage (destination différée de T203).
final Provider<NotificationRouter> notificationRouterProvider =
    Provider<NotificationRouter>(
      (Ref ref) => NotificationRouter(
        resolvePath: destinationPathFor,
        navigate: (String location) =>
            unawaited(ref.read(goRouterProvider).push<Object?>(location)),
        isReady: () => ref.read(routingProfileProvider) != null,
      ),
    );

/// Pilote des notifications poussées, monté au-dessus du routeur.
class PushDriver extends ConsumerStatefulWidget {
  const PushDriver({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PushDriver> createState() => _PushDriverState();
}

class _PushDriverState extends ConsumerState<PushDriver> {
  PushEntryPoints? _entryPoints;
  StreamSubscription<String>? _tokenSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_start());
      }
    });
  }

  @override
  void dispose() {
    _entryPoints?.dispose();
    unawaited(_tokenSubscription?.cancel());
    super.dispose();
  }

  Future<void> _start() async {
    final NotificationRouter router = ref.read(notificationRouterProvider);

    // Le tap sur la bannière locale passe par le MÊME routage que tout le reste.
    await ref
        .read(foregroundPresenterProvider)
        .initialize(onSelect: router.open);
    if (!mounted) {
      return;
    }

    final PushMessenger messenger = ref.read(pushMessengerProvider);
    _entryPoints = PushEntryPoints(messenger)
      ..bind(
        onForeground: _onForegroundMessage,
        // Arrière-plan, notification touchée : routage immédiat.
        onOpened: (PushMessage message) => router.open(message.data),
      );

    // Rotation du jeton décidée par le transport : l'ancien part, le nouveau
    // arrive — sans attendre une reconnexion (T200).
    _tokenSubscription = messenger.tokenChanges.listen(
      (String token) =>
          unawaited(ref.read(pushServiceProvider).rotateToken(token)),
    );

    // Application tuée, ouverte par une notification : le message initial est
    // routé — ou mis en attente d'aiguillage si la session n'est pas restaurée.
    final PushMessage? initial = await _entryPoints!.takeInitialMessage();
    if (initial != null && mounted) {
      router.open(initial.data);
    }
  }

  /// Premier plan : bannière + compteurs — **jamais** de navigation forcée.
  void _onForegroundMessage(PushMessage message) {
    unawaited(ref.read(foregroundPresenterProvider).show(message));

    // Les pastilles écoutent ce signal (badge du centre, FR-082).
    ref.read(receivedPushSignalProvider.notifier).publish(message);

    // Un message de conversation rafraîchit aussi le fil affiché et la
    // pastille de la messagerie — le signal promis à T188.
    final NotificationPayload payload = NotificationPayload.parse(message.data);
    if (payload is ChatPayload) {
      ref.read(chatMessageSignalProvider(payload.threadId).notifier).notify();
      ref.invalidate(threadsUnreadCountProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    // L'enregistrement part À CHAQUE connexion — le jeton identifie une
    // installation, pas un compte (scénario 7.4) — et au démarrage sur session
    // restaurée (la restauration produit la même transition d'état).
    ref.listen<SessionState>(sessionControllerProvider, (
      SessionState? previous,
      SessionState next,
    ) {
      if (next.isAuthenticated && previous?.isAuthenticated != true) {
        unawaited(ref.read(pushServiceProvider).registerForCurrentSession());
      }
    });

    // Le profil vient d'arriver : la destination différée peut partir.
    ref.listen<RoutingProfile?>(routingProfileProvider, (
      RoutingProfile? previous,
      RoutingProfile? next,
    ) {
      if (next != null) {
        ref.read(notificationRouterProvider).flushPending();
      }
    });

    return widget.child;
  }
}
