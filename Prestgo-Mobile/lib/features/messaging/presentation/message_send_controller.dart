// Envoi optimiste, état d'échec et renvoi MANUEL (T185, FR-077).
//
// `POST /messages/threads/{id}/messages` n'a pas de clé d'idempotence : la
// politique de rejeu du socle l'exclut nommément (retry-and-idempotency.md), un
// rejeu créerait des doublons. D'où ce cycle :
//
//   envoi → bulle « en cours » → 201 : la bulle devient un message ordinaire ;
//                              → échec : bulle « échec » + bouton « Renvoyer »,
//                                et RIEN ne repart tout seul (scénario 6.3).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/messaging/data/messaging_repository.dart';
import 'package:prestgo_mobile/features/messaging/domain/message.dart';
import 'package:prestgo_mobile/features/messaging/presentation/messaging_providers.dart';

enum OutgoingStatus { sending, failed }

/// Message en cours d'acheminement — affiché en bulle avant la confirmation.
class OutgoingMessage {
  const OutgoingMessage({
    required this.localId,
    required this.text,
    required this.fileIds,
    required this.status,
    this.error,
  });

  final String localId;
  final String text;
  final List<String> fileIds;
  final OutgoingStatus status;

  /// Message du service ou de repli, affiché sous la bulle en échec.
  final String? error;

  bool get isFailed => status == OutgoingStatus.failed;

  OutgoingMessage copyWith({required OutgoingStatus status, String? error}) =>
      OutgoingMessage(
        localId: localId,
        text: text,
        fileIds: fileIds,
        status: status,
        error: error,
      );
}

class MessageSendController extends Notifier<List<OutgoingMessage>> {
  MessageSendController(this.threadId);

  final String threadId;

  /// Distingue les bulles d'une même session d'écran ; jamais envoyé au service.
  int _sequence = 0;

  @override
  List<OutgoingMessage> build() => const <OutgoingMessage>[];

  /// Part une première fois — la bulle apparaît immédiatement (optimiste).
  Future<void> send({
    required String text,
    List<String> fileIds = const <String>[],
  }) {
    final OutgoingMessage outgoing = OutgoingMessage(
      localId: 'sortant-${_sequence++}',
      text: text,
      fileIds: fileIds,
      status: OutgoingStatus.sending,
    );
    state = <OutgoingMessage>[...state, outgoing];
    return _deliver(outgoing.localId);
  }

  /// Renvoi **manuel** d'une bulle en échec — le seul rejeu permis (FR-077).
  Future<void> resend(String localId) {
    state = <OutgoingMessage>[
      for (final OutgoingMessage m in state)
        m.localId == localId ? m.copyWith(status: OutgoingStatus.sending) : m,
    ];
    return _deliver(localId);
  }

  /// Abandonne une bulle en échec sans l'envoyer.
  void discard(String localId) {
    state = <OutgoingMessage>[
      for (final OutgoingMessage m in state)
        if (m.localId != localId) m,
    ];
  }

  Future<void> _deliver(String localId) async {
    final OutgoingMessage outgoing = state.firstWhere(
      (OutgoingMessage m) => m.localId == localId,
    );
    try {
      final Message sent = await ref
          .read(messagingRepositoryProvider)
          .send(threadId, text: outgoing.text, fileIds: outgoing.fileIds);
      // La bulle devient un message ordinaire, à sa place dans le fil.
      state = <OutgoingMessage>[
        for (final OutgoingMessage m in state)
          if (m.localId != localId) m,
      ];
      ref.read(conversationProvider(threadId).notifier).deliver(sent);
      // Le dernier message de la liste des fils vient de changer.
      ref.invalidate(threadsProvider);
    } on ApiException catch (error) {
      state = <OutgoingMessage>[
        for (final OutgoingMessage m in state)
          m.localId == localId
              ? m.copyWith(status: OutgoingStatus.failed, error: error.message)
              : m,
      ];
    }
  }
}

final messageSendControllerProvider =
    NotifierProvider.family<
      MessageSendController,
      List<OutgoingMessage>,
      String
    >(MessageSendController.new);
