// Message d'un fil (T180, data-model §7).
//
// Trois auteurs possibles, distingués par `senderId` seul :
//   • `null`            → message système (« Mission confirmée. ») ;
//   • l'identifiant de `GET /me` → moi ;
//   • tout autre        → l'interlocuteur.
//
// Les pièces jointes arrivent **imbriquées** — `files: [ { file: {...} } ]` — et
// sont dépliées ici en références plates ; aucun écran ne connaît cette enveloppe.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

class Message {
  const Message({
    required this.id,
    required this.message,
    required this.createdAt,
    this.senderId,
    this.readAt,
    this.files = const <FileRef>[],
  });

  factory Message.fromJson(JsonMap json) => Message(
    id: json['id'] as String? ?? '',
    senderId: json['senderId'] as String?,
    message: json['message'] as String? ?? '',
    createdAt:
        MissionDates.fromApiOrNull(json['createdAt'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0),
    readAt: MissionDates.fromApiOrNull(json['readAt'] as String?),
    files: json['files'] is List
        ? (json['files']! as List<Object?>)
              .whereType<Map<Object?, Object?>>()
              .map(_unwrapFile)
              .toList(growable: false)
        : const <FileRef>[],
  );

  /// Déplie `{ file: {...} }` — et tolère une référence déjà plate.
  ///
  /// Les entrées de fil ne portent pas de `visibility` : le repli est
  /// `restricted` (`FileVisibility.parse`), donc lisible avec jeton et **jamais**
  /// écrit sur disque — le choix prudent pour un échange privé (porte G6).
  static FileRef _unwrapFile(Map<Object?, Object?> entry) {
    final Object? nested = entry['file'];
    return FileRef.fromJson(
      (nested is Map<Object?, Object?> ? nested : entry)
          .cast<String, Object?>(),
    );
  }

  final String id;

  /// `null` pour un message système.
  final String? senderId;

  final String message;
  final DateTime createdAt;
  final DateTime? readAt;
  final List<FileRef> files;

  bool get isSystem => senderId == null;

  bool isMine(String meId) => senderId == meId;

  @override
  bool operator ==(Object other) => other is Message && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Message($id, ${isSystem ? 'système' : senderId})';
}
