import { Transform } from "class-transformer";

/**
 * Convertit une chaîne vide en « valeur absente ».
 *
 * Pourquoi c'est nécessaire : dans un formulaire, un filtre laissé vide part
 * dans l'URL sous la forme `?status=`. Or `@IsOptional()` ne saute la
 * validation que pour `null` et `undefined`, PAS pour la chaîne vide — la
 * requête était donc refusée avec « statut inconnu » alors que l'utilisateur
 * demandait simplement « tous les statuts ».
 *
 * À poser sur tout filtre facultatif de type texte ou énumération.
 */
export function EmptyToUndefined() {
  return Transform(({ value }) => (typeof value === "string" && value.trim() === "" ? undefined : value));
}
