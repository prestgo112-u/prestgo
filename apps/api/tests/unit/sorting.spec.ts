import { BadRequestException } from "@nestjs/common";
import { describe, expect, it } from "vitest";
import { buildOrderBy, parseSort, type SortAllowList } from "../../src/common/dto/sorting.js";

const ALLOWED: SortAllowList = {
  createdAt: { path: ["createdAt"], defaultDirection: "desc" },
  price: ["pack", "price"],
  name: ["publicName"]
};

/**
 * Paramètre `sort` (§15.4).
 *
 * Il était jusqu'ici validé puis IGNORÉ : l'API acceptait le paramètre sans
 * jamais changer l'ordre des résultats. Deux exigences ici — qu'il soit
 * réellement appliqué, et qu'il ne permette pas de trier sur n'importe quelle
 * colonne.
 */
describe("paramètre de tri", () => {
  it("renvoie le tri par défaut quand rien n'est demandé", () => {
    expect(parseSort(undefined, ALLOWED)).toBeNull();
    expect(parseSort("  ", ALLOWED)).toBeNull();
    expect(buildOrderBy(undefined, ALLOWED, { createdAt: "desc" })).toEqual({ createdAt: "desc" });
  });

  it("comprend les deux écritures du sens de tri", () => {
    expect(parseSort("-name", ALLOWED)).toEqual({ field: "name", direction: "desc" });
    expect(parseSort("name:desc", ALLOWED)).toEqual({ field: "name", direction: "desc" });
    expect(parseSort("name", ALLOWED)).toEqual({ field: "name", direction: "asc" });
  });

  it("applique le sens par défaut propre à chaque champ", () => {
    // `createdAt` est déclaré « décroissant par défaut » : les plus récents
    // d'abord, ce qu'attend un utilisateur qui trie par date.
    expect(parseSort("createdAt", ALLOWED)).toEqual({ field: "createdAt", direction: "desc" });
  });

  it("construit une clause imbriquée pour un champ de relation", () => {
    expect(buildOrderBy("price", ALLOWED, { createdAt: "desc" })).toEqual({ pack: { price: "asc" } });
  });

  it("refuse un champ hors de la liste blanche", () => {
    // C'est la protection essentielle : sans elle, `sort=passwordHash`
    // permettrait de deviner une empreinte par comparaisons successives.
    expect(() => parseSort("passwordHash", ALLOWED)).toThrow(BadRequestException);
    expect(() => parseSort("passwordHash", ALLOWED)).toThrow(/Champs triables/);
  });

  it("refuse un sens de tri inconnu", () => {
    expect(() => parseSort("name:sideways", ALLOWED)).toThrow(BadRequestException);
  });
});
