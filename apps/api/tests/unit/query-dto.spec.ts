import "reflect-metadata";
import { plainToInstance } from "class-transformer";
import { validateSync } from "class-validator";
import { describe, expect, it } from "vitest";
import { MissionListQueryDto } from "../../src/modules/missions/dto.js";

/**
 * Ces tests appellent réellement la validation, ils ne comparent pas des
 * littéraux entre eux.
 *
 * Attention si un jour ils échouent sans raison apparente : vitest compile avec
 * esbuild, qui n'applique pas le même mode de décorateurs que `tsc`. Le
 * comportement de référence reste celui du vrai build.
 */
function validate(query: Record<string, unknown>): string[] {
  const dto = plainToInstance(MissionListQueryDto, query);
  return validateSync(dto).flatMap((error) => Object.values(error.constraints ?? {}));
}

describe("filtres de liste des missions", () => {
  it("accepte une requête sans aucun filtre", () => {
    expect(validate({})).toEqual([]);
  });

  // C'est le bug corrigé au Lot 2 : un formulaire qui n'a rien sélectionné
  // envoie « ?status= », et la requête était refusée.
  it("traite un filtre vide comme absent", () => {
    expect(validate({ status: "", search: "", from: "", to: "" })).toEqual([]);
  });

  it("refuse quand même un statut réellement inconnu", () => {
    expect(validate({ status: "n_importe_quoi" })).toContain("Statut de mission inconnu");
  });

  it("accepte un statut valide", () => {
    expect(validate({ status: "confirmed" })).toEqual([]);
  });

  it("refuse une date mal formée", () => {
    expect(validate({ from: "01/08/2026" })).toContain("La date de début doit être au format AAAA-MM-JJ");
  });

  it("convertit page et limit reçus en texte puis les vérifie", () => {
    expect(validate({ page: "2", limit: "50" })).toEqual([]);
    expect(validate({ limit: "5000" })).toContain("limit ne peut pas dépasser 100");
    expect(validate({ page: "0" })).toContain("page doit être supérieur ou égal à 1");
  });
});
