// Politique de persistance des contenus de fichiers (T236, FR-098, porte G6).
//
// LA règle, en un seul endroit :
//   • `public`     (avatars, réalisations) — cache disque autorisé, lisible
//     sans jeton ;
//   • `restricted` — pas de cache disque (une réalisation retirée y redescend :
//     sa copie locale ne correspond plus à rien de servi) ;
//   • `sensitive`  (justificatifs) — **jamais** écrit sur le disque, sous
//     aucune forme : un justificatif rouvert hors ligne ne restitue RIEN
//     (scénario 10.4).
//
// `FileImage` (l'unique point d'affichage) choisit son moteur d'après cette
// politique : cache disque pour ce qu'elle autorise, mémoire seule pour le
// reste.

import 'package:prestgo_mobile/core/files/file_ref.dart';

abstract final class FileCachePolicy {
  /// Vrai si le contenu peut être conservé sur le disque de l'appareil.
  static bool mayPersistOnDisk(FileVisibility visibility) =>
      visibility == FileVisibility.public;

  /// Vrai si la lecture exige un jeton d'autorisation.
  static bool requiresAccessToken(FileVisibility visibility) =>
      !visibility.isPubliclyReadable;
}
