import { SetMetadata } from "@nestjs/common";

export const IS_PUBLIC_KEY = "prestgo:public";

/**
 * Marque une route comme accessible SANS être connecté (ex : la page de login).
 *
 * Depuis le Lot 0, la garde JWT est branchée sur toute l'application :
 * par défaut, chaque route exige donc un token valide. Ce décorateur est la
 * seule façon d'ouvrir une route au public — ce qui rend l'exception visible
 * et volontaire, au lieu d'un oubli silencieux.
 */
export function Public() {
  return SetMetadata(IS_PUBLIC_KEY, true);
}
