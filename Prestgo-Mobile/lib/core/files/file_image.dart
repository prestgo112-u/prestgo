// Affichage d'un contenu de fichier (opération 63).
//
// Deux chemins, choisis par la **visibilité** :
//   • `public`   — lisible sans jeton, mis en cache disque (avatars, portfolio) ;
//   • autre      — lisible avec jeton, **jamais** écrit sur le disque (FR-098).
//
// Un justificatif rouvert hors ligne ne doit rien restituer : c'est le scénario
// 10.4 de quickstart.md.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:prestgo_mobile/core/files/file_cache_policy.dart';
import 'package:prestgo_mobile/core/files/file_ref.dart';

class FileImage extends StatelessWidget {
  const FileImage({
    required this.fileId,
    required this.visibility,
    required this.baseUrl,
    super.key,
    this.accessToken,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  /// Construit l'affichage depuis une référence complète.
  FileImage.fromRef(
    FileRef ref, {
    required this.baseUrl,
    super.key,
    this.accessToken,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  }) : fileId = ref.id,
       visibility = ref.visibility;

  final String fileId;
  final FileVisibility visibility;

  /// Base d'API — contient déjà `/api/v1`.
  final String baseUrl;

  /// Requis pour tout contenu non public.
  final String? accessToken;

  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  String get _url => '$baseUrl/files/$fileId/content';

  @override
  Widget build(BuildContext context) {
    // Décoder à la taille d'affichage, pas à la taille du fichier : une photo de
    // portfolio décodée en pleine résolution derrière un avatar de 56 px coûte
    // des dizaines de Mo sur un appareil d'entrée de gamme (T241, budget 60 i/s).
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    final int? decodeWidth = _decodeSize(width, ratio);
    final int? decodeHeight = decodeWidth == null
        ? _decodeSize(height, ratio)
        : null;

    // La politique de persistance est UNIQUE (T236) : seul ce qu'elle autorise
    // passe par le moteur à cache disque.
    if (FileCachePolicy.mayPersistOnDisk(visibility)) {
      return CachedNetworkImage(
        imageUrl: _url,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: decodeWidth,
        memCacheHeight: decodeHeight,
        placeholder: (BuildContext context, String url) =>
            _placeholder(context),
        errorWidget: (BuildContext context, String url, Object error) =>
            _error(context),
      );
    }

    final String? token = accessToken;
    if (token == null) {
      // Un contenu protégé sans session ne s'affiche pas : ne pas tenter l'appel
      // évite un 401 inutile et une trace d'erreur trompeuse.
      return _error(context);
    }

    // `Image.network` conserve l'image en mémoire pour la durée de l'écran, sans
    // jamais l'écrire sur le disque — c'est exactement ce qu'exige FR-098.
    return Image.network(
      _url,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: decodeWidth,
      cacheHeight: decodeHeight,
      headers: <String, String>{'Authorization': 'Bearer $token'},
      loadingBuilder:
          (BuildContext context, Widget child, ImageChunkEvent? progress) =>
              progress == null ? child : _placeholder(context),
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) =>
              _error(context),
    );
  }

  /// Une seule dimension suffit : l'autre suit le rapport d'origine, ce qui
  /// évite toute déformation du décodage quel que soit `fit`.
  static int? _decodeSize(double? logical, double ratio) =>
      logical == null ? null : (logical * ratio).round();

  Widget _placeholder(BuildContext context) =>
      placeholder ??
      Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );

  Widget _error(BuildContext context) =>
      errorWidget ??
      Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.image_not_supported_outlined,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
}
