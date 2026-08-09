// Envoi de fichier (opération 61, R7).
//
// Trois règles, dans cet ordre :
//   1. **filtrer le type et la taille avant tout appel réseau** — le service rejette
//      un dépassement après avoir reçu le fichier entier, ce qui est inacceptable
//      sur connexion mobile ;
//   2. **compresser les images** — une photo de téléphone récent dépasse souvent
//      5 Mo, donc chaque justificatif serait un envoi long et faillible ;
//   3. **exclure du rejeu automatique** — le corps multipart est un flux à usage
//      unique : un rejeu enverrait un corps vide.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/retry_policy.dart';
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/validation/validators.dart';

/// Refus prononcé **localement**, avant tout appel réseau.
class FileRejected implements Exception {
  const FileRejected(this.message);

  final String message;

  @override
  String toString() => 'FileRejected($message)';
}

/// Fichier candidat à l'envoi.
class UploadCandidate {
  const UploadCandidate({
    required this.path,
    required this.mimeType,
    this.fileName,
  });

  final String path;
  final String mimeType;

  /// Nom transmis au service ; le nom du fichier local par défaut.
  final String? fileName;

  bool get isImage => FileLimits.imageOnlyMimeTypes.contains(mimeType);
}

class FileUploadService {
  const FileUploadService(this._client);

  static const String uploadPath = '/files/upload';

  final ApiClient _client;

  /// Envoie [candidate] et renvoie sa référence.
  ///
  /// [acceptedMimeTypes] restreint le contrôle local : l'avatar, le portfolio et
  /// les réalisations n'acceptent que des images, le service refusant le reste.
  ///
  /// Lève [FileRejected] si le fichier est refusé localement, [ApiException] si le
  /// service refuse. Cette méthode n'est **jamais** rejouée automatiquement : un
  /// échec remonte à l'écran, qui propose une reprise explicite.
  Future<FileRef> upload(
    UploadCandidate candidate, {
    Set<String> acceptedMimeTypes = FileLimits.acceptedMimeTypes,
    FileVisibility? visibility,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final File source = File(candidate.path);
    if (!source.existsSync()) {
      throw const FileRejected('Fichier introuvable.');
    }

    // 1. Filtrage local, avant compression comme avant envoi.
    final int originalSize = source.lengthSync();
    final String? rejection = Validators.file(
      mimeType: candidate.mimeType,
      sizeBytes: originalSize,
      acceptedMimeTypes: acceptedMimeTypes,
    );
    if (rejection != null) {
      throw FileRejected(rejection);
    }

    // 2. Compression des images trop lourdes.
    final File payload = candidate.isImage
        ? await _compressIfNeeded(source, candidate.mimeType)
        : source;

    // Le fichier compressé doit lui aussi tenir dans le plafond : une image très
    // détaillée peut rester volumineuse malgré la réduction.
    final int payloadSize = payload.lengthSync();
    if (payloadSize > FileLimits.maxSizeBytes) {
      throw FileRejected(
        Validators.file(
              mimeType: candidate.mimeType,
              sizeBytes: payloadSize,
              acceptedMimeTypes: acceptedMimeTypes,
            ) ??
            'Fichier trop volumineux.',
      );
    }

    final FormData form = FormData.fromMap(<String, Object?>{
      FileLimits.multipartFieldName: await MultipartFile.fromFile(
        payload.path,
        filename: candidate.fileName ?? p.basename(candidate.path),
      ),
      if (visibility != null) 'visibility': visibility.name,
    });

    final ApiEnvelope<FileRef> envelope = await _client.send<FileRef>(
      'POST',
      uploadPath,
      parse: parseObject<FileRef>(FileRef.fromJson),
      body: form,
      cancelToken: cancelToken,
      // 3. Hors rejeu automatique : le corps est un flux à usage unique.
      extra: <String, Object?>{kNoRetryExtra: true},
    );
    return envelope.requireData;
  }

  /// Réduit une image au-delà de la cible ; renvoie la source inchangée sinon.
  ///
  /// L'échec de la compression n'est pas fatal : mieux vaut envoyer l'original que
  /// bloquer le dépôt d'un justificatif.
  Future<File> _compressIfNeeded(File source, String mimeType) async {
    if (source.lengthSync() <= FileLimits.compressionTargetBytes) {
      return source;
    }

    final Directory directory = source.parent;
    final String target = p.join(
      directory.path,
      'prestgo_compressed_${p.basename(source.path)}',
    );

    try {
      final XFile? compressed = await FlutterImageCompress.compressAndGetFile(
        source.path,
        target,
        quality: 82,
        minWidth: FileLimits.compressionMaxDimension,
        minHeight: FileLimits.compressionMaxDimension,
        format: mimeType == 'image/png'
            ? CompressFormat.png
            : CompressFormat.jpeg,
      );
      if (compressed == null) {
        return source;
      }
      final File result = File(compressed.path);
      // Une compression qui alourdit le fichier n'a aucun intérêt.
      return result.lengthSync() < source.lengthSync() ? result : source;
    } on Object {
      return source;
    }
  }
}
