import { BadRequestException } from "@nestjs/common";
import type { ValidationError } from "class-validator";
import type { ApiErrorDetail } from "../contracts/api-response.js";

/**
 * Traduit les erreurs de `class-validator` en `errors[]` du format standard,
 * AVEC le nom du champ fautif.
 *
 * Sans cette fabrique, le `ValidationPipe` ne produisait qu'un tableau de
 * messages : le filtre global le recopiait en
 * `{ code: "validation_error", message }`, sans `field`. Une application
 * cliente ne pouvait donc pas placer le message sous le bon champ de
 * formulaire, alors que `field` existe dans le contrat depuis l'origine et que
 * le filtre sait déjà le lire (voir `readErrors`). Seul
 * `POST /providers/me/submit`, qui pose son tableau `errors` à la main, en
 * bénéficiait.
 *
 * L'ordre des messages est celui de `class-validator`, inchangé : le `message`
 * de premier niveau de la réponse reste donc exactement le même qu'avant.
 */
export function validationExceptionFactory(errors: ValidationError[]): BadRequestException {
  const details = flatten(errors);

  return new BadRequestException({
    // Conserve le contrat historique : le message de tête est le premier de la
    // liste. C'est ce qu'affichent les clients qui ne lisent pas `errors[]`.
    message: details[0]?.message ?? "Requête invalide",
    errors: details
  });
}

/**
 * Aplatit l'arbre d'erreurs en une liste plate.
 *
 * `class-validator` imbrique : un tableau d'objets validés par
 * `@ValidateNested({ each: true })` produit un parent (`slots`), des enfants
 * indexés (`0`, `1`), puis les champs réels (`startTime`). On reconstruit le
 * chemin complet — `slots.0.startTime` — parce qu'un simple `startTime` ne
 * dirait pas QUEL créneau est en cause.
 */
function flatten(errors: ValidationError[], parentPath = ""): ApiErrorDetail[] {
  const details: ApiErrorDetail[] = [];

  for (const error of errors) {
    const path = parentPath ? `${parentPath}.${error.property}` : error.property;

    // Un nœud porte soit des contraintes, soit des enfants — parfois les deux
    // (ex. « doit être un tableau » ET une erreur sur un élément).
    for (const message of Object.values(error.constraints ?? {})) {
      details.push({ field: path, code: "validation_error", message });
    }

    if (error.children?.length) {
      details.push(...flatten(error.children, path));
    }
  }

  return details;
}
