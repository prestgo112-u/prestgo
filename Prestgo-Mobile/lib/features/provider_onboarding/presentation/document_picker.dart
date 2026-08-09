// Choix d'un fichier justificatif — la seule frontière de plateforme de P7.
//
// Derrière une interface pour deux raisons :
//   • les greffons (`file_picker`) n'existent ni dans un test de widget ni dans
//     le parcours d'intégration sans appareil — le harnais substitue un
//     sélecteur factice ;
//   • la restriction de types se décide ICI, à la source : le service refuse
//     tout MIME hors liste, et filtrer après coup ferait faire un aller-retour
//     inutile (R7 — le refus doit être local et préalable).

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/files/file_upload_service.dart';

/// Extensions proposées par le sélecteur, alignées sur les MIME acceptés par le
/// service (`FileLimits.acceptedMimeTypes`).
const List<String> kDocumentExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'webp',
  'pdf',
];

abstract interface class DocumentPicker {
  /// Rend le fichier choisi, ou `null` si l'utilisateur a renoncé.
  Future<UploadCandidate?> pick();
}

class FilePickerDocumentPicker implements DocumentPicker {
  const FilePickerDocumentPicker();

  @override
  Future<UploadCandidate?> pick() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: kDocumentExtensions,
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
        // Hors liste : le type réel est laissé au contrôle local, qui refusera
        // avec un message clair plutôt qu'un envoi voué au 400.
        final String ext? => 'application/$ext',
        null => 'application/octet-stream',
      };
}

final Provider<DocumentPicker> documentPickerProvider =
    Provider<DocumentPicker>((Ref ref) => const FilePickerDocumentPicker());
