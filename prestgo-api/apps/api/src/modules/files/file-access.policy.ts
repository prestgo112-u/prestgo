export type FileVisibility = "public" | "authenticated" | "restricted" | "sensitive";

// Permission donnant le droit de lire un fichier restreint appartenant à
// QUELQU'UN D'AUTRE (usage : supervision par un administrateur).
export const READ_ANY_FILE_PERMISSION = "files.any.read";

// Permission donnant le droit de lire un fichier sensible (pièce d'identité,
// justificatif...) appartenant à quelqu'un d'autre.
export const READ_SENSITIVE_FILE_PERMISSION = "files.sensitive.read";

// Le fichier auquel on veut accéder.
export interface FileAccessTarget {
  visibility: FileVisibility;
  ownerId?: string | null;
}

// La personne qui demande l'accès (issue du token JWT).
export interface FileAccessActor {
  id?: string | null;
  permissions?: string[];
}

/**
 * Décide si un utilisateur peut accéder à un fichier. Fonction pure = facile à tester.
 *
 * Les quatre niveaux de visibilité :
 *   - `public`        : tout le monde, même sans compte.
 *   - `authenticated` : n'importe quel utilisateur connecté.
 *   - `restricted`    : son propriétaire, ou un admin ayant `files.any.read`.
 *   - `sensitive`     : son propriétaire, ou un admin ayant `files.sensitive.read`.
 *
 * Avant le Lot 0, `restricted` était traité comme `authenticated` : n'importe
 * quel compte connecté pouvait donc lire les fichiers d'export d'un autre
 * administrateur. Le contrôle d'appartenance ci-dessous ferme cette faille.
 */
export function canAccessFile(file: FileAccessTarget, actor?: FileAccessActor | null): boolean {
  if (file.visibility === "public") {
    return true;
  }

  // Tout le reste exige d'être connecté.
  if (!actor?.id) {
    return false;
  }

  if (file.visibility === "authenticated") {
    return true;
  }

  // Le propriétaire garde toujours accès à ses propres fichiers.
  if (file.ownerId && file.ownerId === actor.id) {
    return true;
  }

  const permissions = actor.permissions ?? [];

  if (file.visibility === "sensitive") {
    return permissions.includes(READ_SENSITIVE_FILE_PERMISSION);
  }

  // `restricted` : un droit de lecture large suffit, et la permission
  // "sensible" (plus forte) donne évidemment aussi ce droit.
  return permissions.includes(READ_ANY_FILE_PERMISSION) || permissions.includes(READ_SENSITIVE_FILE_PERMISSION);
}
