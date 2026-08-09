// Charge utile de notification — la MÊME en push et en interne (T195, FR-083).
//
// Ce modèle vit dans le socle : le routage (`core/push/notification_router.dart`)
// ne peut dépendre d'aucune fonctionnalité (règle « le socle ne dépend d'aucune
// feature »). `features/notifications/domain/notification_payload.dart` le
// réexporte pour la surface applicative.
//
// Deux règles d'analyse, imposées par le transport :
//   • un push FCM livre des **chaînes** (`Map<String, String>`) : aucune valeur
//     n'est présumée typée, tout passe par `toString()` ;
//   • un type inconnu, absent, ou une charge mutilée retombe sur
//     [UnknownPayload] — jamais sur une erreur (contracts/push-payloads.md §1).

sealed class NotificationPayload {
  const NotificationPayload();

  /// Analyse tolérante d'une charge utile, quelle qu'en soit l'origine.
  static NotificationPayload parse(Map<Object?, Object?>? data) {
    if (data == null) {
      return const UnknownPayload();
    }

    String? id(String key) {
      final Object? value = data[key];
      if (value == null) {
        return null;
      }
      final String text = value.toString();
      return text.isEmpty ? null : text;
    }

    switch (data['type']?.toString()) {
      case 'mission':
        final String? missionId = id('missionId');
        return missionId == null
            ? const UnknownPayload()
            : MissionPayload(missionId);

      case 'chat':
        final String? threadId = id('threadId');
        return threadId == null
            ? const UnknownPayload()
            : ChatPayload(threadId: threadId, missionId: id('missionId'));

      case 'reschedule':
        final String? missionId = id('missionId');
        return missionId == null
            ? const UnknownPayload()
            : ReschedulePayload(
                missionId: missionId,
                rescheduleId: id('rescheduleId'),
              );

      case 'review':
        final String? missionId = id('missionId');
        return missionId == null
            ? const UnknownPayload()
            : ReviewPayload(missionId: missionId, reviewId: id('reviewId'));

      default:
        return const UnknownPayload();
    }
  }
}

/// Cycle de vie d'une mission — `{ missionId, type: "mission" }`.
final class MissionPayload extends NotificationPayload {
  const MissionPayload(this.missionId);

  final String missionId;
}

/// Message de conversation — `{ missionId, threadId, type: "chat" }`.
final class ChatPayload extends NotificationPayload {
  const ChatPayload({required this.threadId, this.missionId});

  final String threadId;

  /// Mission porteuse du fil : jointe à la destination quand elle est connue,
  /// pour que la conversation lise son statut sans dépendre de `/me/threads`.
  final String? missionId;
}

/// Demande de report — `{ missionId, rescheduleId, type: "reschedule" }`.
final class ReschedulePayload extends NotificationPayload {
  const ReschedulePayload({required this.missionId, this.rescheduleId});

  final String missionId;
  final String? rescheduleId;
}

/// Avis reçu — `{ missionId, reviewId, type: "review" }`.
final class ReviewPayload extends NotificationPayload {
  const ReviewPayload({required this.missionId, this.reviewId});

  final String missionId;
  final String? reviewId;
}

/// Type inconnu, absent, ou charge mutilée → centre de notifications.
final class UnknownPayload extends NotificationPayload {
  const UnknownPayload();
}
