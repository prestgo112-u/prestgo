// Choix d'une pièce jointe de message — la seule frontière de plateforme d'US6.
//
// Derrière une interface, comme le sélecteur de justificatif de P7 : les greffons
// (`file_picker`) n'existent ni dans un test de widget ni dans le parcours sans
// appareil — le harnais substitue un sélecteur factice. Les extensions proposées
// couvrent tous les MIME que le service accepte en messagerie (images, PDF, texte),
// et le refus définitif reste au contrôle local de `FileUploadService` (R7).

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/files/file_upload_service.dart';

/// Extensions proposées, alignées sur `FileLimits.acceptedMimeTypes`.
const List<String> kMessageAttachmentExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'webp',
  'pdf',
  'txt',
  'csv',
];

abstract interface class MessageAttachmentPicker {
  /// Rend le fichier choisi, ou `null` si l'utilisateur a renoncé.
  Future<UploadCandidate?> pick();
}

class FilePickerMessageAttachmentPicker implements MessageAttachmentPicker {
  const FilePickerMessageAttachmentPicker();

  @override
  Future<UploadCandidate?> pick() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kMessageAttachmentExtensions,
    );
    final PlatformFile? file = result?.files.firstOrNull;
    final String? path = file?.path;
    if (file == null || path == null) {
      return null;
    }
    return UploadCandidate(
      path: path,
      mimeType: _mimeFor(file.extension),
      fileName: file.name,
    );
  }

  static String _mimeFor(String? extension) =>
      switch (extension?.toLowerCase()) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        'pdf' => 'application/pdf',
        'txt' => 'text/plain',
        'csv' => 'text/csv',
        // Hors liste : le type réel est laissé au contrôle local, qui refusera
        // avec un message clair plutôt qu'un envoi voué au 400.
        final String ext? => 'application/$ext',
        null => 'application/octet-stream',
      };
}

final Provider<MessageAttachmentPicker> messageAttachmentPickerProvider =
    Provider<MessageAttachmentPicker>(
      (Ref ref) => const FilePickerMessageAttachmentPicker(),
    );
