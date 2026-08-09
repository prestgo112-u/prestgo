// Fil de discussion (T180, data-model §7).
//
// `counterpartName` est **déjà résolu du bon côté** par le service : la même route
// sert au client et au prestataire, l'application n'a aucune logique conditionnelle
// par rôle. Un fil existe dès la création de la mission qui le porte.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

/// Ligne de l'onglet Messagerie — `GET /me/threads` (opération 48).
class Thread {
  const Thread({
    required this.id,
    required this.missionId,
    required this.missionStatus,
    required this.status,
    required this.counterpartName,
    required this.unreadCount,
    this.scheduledAt,
    this.counterpartAvatarFileId,
    this.lastMessage,
    this.createdAt,
  });

  factory Thread.fromJson(JsonMap json) => Thread(
    id: json['id'] as String? ?? '',
    missionId: json['missionId'] as String? ?? '',
    missionStatus: json['missionStatus'] as String? ?? '',
    scheduledAt: MissionDates.fromApiOrNull(json['scheduledAt'] as String?),
    status: json['status'] as String? ?? '',
    counterpartName: json['counterpartName'] as String? ?? '',
    counterpartAvatarFileId: json['counterpartAvatarFileId'] as String?,
    lastMessage: json['lastMessage'] is Map<Object?, Object?>
        ? ThreadLastMessage.fromJson(
            (json['lastMessage']! as Map<Object?, Object?>)
                .cast<String, Object?>(),
          )
        : null,
    unreadCount: switch (json['unreadCount']) {
      final int v => v,
      final num v => v.toInt(),
      _ => 0,
    },
    createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
  );

  final String id;
  final String missionId;

  /// Statut de la mission porteuse, tel que reçu — contexte d'affichage seulement.
  final String missionStatus;

  final DateTime? scheduledAt;

  /// Statut du fil, tel que reçu (`open`, `closed`…).
  final String status;

  final String counterpartName;
  final String? counterpartAvatarFileId;
  final ThreadLastMessage? lastMessage;

  /// Messages de l'autre partie non lus — les miens ne comptent jamais.
  final int unreadCount;

  final DateTime? createdAt;

  /// Vrai si la saisie est permise ; un fil non ouvert la masque (FR-078).
  bool get isOpen => status == 'open';

  @override
  bool operator ==(Object other) => other is Thread && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Thread($id, $status, non lus: $unreadCount)';
}

/// Aperçu du dernier message d'un fil, tel que la liste le porte.
class ThreadLastMessage {
  const ThreadLastMessage({
    required this.id,
    required this.message,
    this.senderId,
    this.createdAt,
  });

  factory ThreadLastMessage.fromJson(JsonMap json) => ThreadLastMessage(
    id: json['id'] as String? ?? '',
    message: json['message'] as String? ?? '',
    senderId: json['senderId'] as String?,
    createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
  );

  final String id;
  final String message;
  final String? senderId;
  final DateTime? createdAt;
}

/// Conversation d'une mission — `GET /missions/{id}/thread` (opération 50).
///
/// Le chemin d'entrée quand on arrive du détail d'une mission sans avoir chargé
/// `/me/threads` : il ne porte ni interlocuteur ni aperçu, seulement de quoi ouvrir
/// le fil et savoir si la saisie est permise.
class MissionThread {
  const MissionThread({
    required this.id,
    required this.missionId,
    required this.status,
    required this.messageCount,
    this.createdAt,
  });

  factory MissionThread.fromJson(JsonMap json) => MissionThread(
    id: json['id'] as String? ?? '',
    missionId: json['missionId'] as String? ?? '',
    status: json['status'] as String? ?? '',
    messageCount: switch (json['messageCount']) {
      final int v => v,
      final num v => v.toInt(),
      _ => 0,
    },
    createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
  );

  final String id;
  final String missionId;
  final String status;
  final int messageCount;
  final DateTime? createdAt;

  bool get isOpen => status == 'open';
}
