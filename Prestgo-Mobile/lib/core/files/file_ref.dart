// Référence de fichier (data-model §9).
//
// La **visibilité** commande la mise en cache : les contenus `public` (avatars,
// portfolio) peuvent atterrir sur le disque, les contenus `sensitive`
// (justificatifs) **jamais** (FR-098, porte G6).

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

/// Visibilité arbitrée par le service.
///
/// Un justificatif rattaché passe en `sensitive` ; un avatar ou une réalisation
/// passe en `public` ; le retrait d'une réalisation la ramène en `restricted`.
enum FileVisibility {
  public,
  restricted,
  sensitive;

  static FileVisibility parse(String? raw) => switch (raw) {
    'public' => FileVisibility.public,
    'sensitive' => FileVisibility.sensitive,
    // Valeur par défaut prudente : en cas de doute, le contenu n'est ni public ni
    // mis en cache sur disque.
    _ => FileVisibility.restricted,
  };

  /// Vrai si le contenu est lisible sans jeton d'autorisation.
  bool get isPubliclyReadable => this == FileVisibility.public;

  /// Vrai si le contenu peut être conservé sur le disque de l'appareil.
  bool get isDiskCacheable => this == FileVisibility.public;
}

class FileRef {
  const FileRef({
    required this.id,
    required this.originalName,
    required this.mimeType,
    required this.size,
    required this.visibility,
  });

  factory FileRef.fromJson(JsonMap json) => FileRef(
    id: json['id'] as String? ?? '',
    originalName: json['originalName'] as String? ?? '',
    mimeType: json['mimeType'] as String? ?? '',
    size: switch (json['size']) {
      final int v => v,
      final num v => v.toInt(),
      _ => 0,
    },
    visibility: FileVisibility.parse(json['visibility'] as String?),
  );

  final String id;
  final String originalName;
  final String mimeType;
  final int size;
  final FileVisibility visibility;

  bool get isImage => FileLimits.imageOnlyMimeTypes.contains(mimeType);

  /// Chemin de la ressource binaire, relatif à la base d'API.
  String get contentPath => '/files/$id/content';

  @override
  bool operator ==(Object other) =>
      other is FileRef &&
      other.id == id &&
      other.originalName == originalName &&
      other.mimeType == mimeType &&
      other.size == size &&
      other.visibility == visibility;

  @override
  int get hashCode => Object.hash(id, originalName, mimeType, size, visibility);

  @override
  String toString() => 'FileRef($id, $mimeType, ${visibility.name})';
}
