// Affichage d'un fichier, câblé sur les providers.
//
// `FileImage` est volontairement un widget pur : il reçoit la base d'API et le jeton
// en paramètres, ce qui le rend testable sans conteneur. Mais tous les écrans qui
// affichent un avatar ou une réalisation devraient alors répéter la même résolution.
// C'est ce que fait ce fichier, une fois.
//
// La visibilité n'est pas un détail : un contenu public est mis en cache disque, un
// contenu protégé ne l'est **jamais** (FR-098). L'appelant doit donc la déclarer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/files/file_image.dart' as files;
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';

class RemoteFileImage extends ConsumerWidget {
  const RemoteFileImage({
    required this.fileId,
    required this.visibility,
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  /// Raccourci pour les contenus publics — avatars, réalisations.
  const RemoteFileImage.public({
    required this.fileId,
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  }) : visibility = FileVisibility.public;

  final String fileId;
  final FileVisibility visibility;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context, WidgetRef ref) => files.FileImage(
    fileId: fileId,
    visibility: visibility,
    baseUrl: ref.watch(appEnvironmentProvider).apiBaseUrl,
    // Un contenu public s'affiche sans session : c'est la condition d'une fiche
    // consultable sans compte (FR-022).
    accessToken: visibility.isDiskCacheable
        ? null
        : ref.watch(sessionControllerProvider).tokens?.accessToken,
    width: width,
    height: height,
    fit: fit,
    placeholder: placeholder,
    errorWidget: errorWidget,
  );
}

/// Avatar rond, avec l'initiale en repli.
class ProviderAvatar extends StatelessWidget {
  const ProviderAvatar({
    required this.name,
    this.fileId,
    this.radius = 28,
    super.key,
  });

  final String? fileId;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String trimmed = name.trim();
    final String initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final String? fileId = this.fileId;

    if (fileId == null) {
      return CircleAvatar(radius: radius, child: Text(initial));
    }
    return ClipOval(
      child: SizedBox.square(
        dimension: radius * 2,
        child: RemoteFileImage.public(
          fileId: fileId,
          // Taille explicite : l'image est décodée à la taille de l'avatar, pas
          // à celle du fichier (T241).
          width: radius * 2,
          height: radius * 2,
          errorWidget: CircleAvatar(radius: radius, child: Text(initial)),
        ),
      ),
    );
  }
}
