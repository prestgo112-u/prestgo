import { describe, expect, it } from "vitest";
import { buildCsv } from "../../src/modules/reports/csv.js";

// Vrais tests : ils appellent la fonction et vérifient sa sortie.
describe("génération CSV", () => {
  it("écrit l'en-tête et les lignes séparés par des point-virgules", () => {
    const csv = buildCsv(["id", "nom"], [["1", "Kofi"]]);
    // On retire le BOM pour comparer le texte lisible.
    expect(csv.replace(/^﻿/, "")).toBe("id;nom\r\n1;Kofi\r\n");
  });

  it("commence par un BOM UTF-8 (sinon Excel casse les accents)", () => {
    expect(buildCsv(["a"], [])).toMatch(/^﻿/);
  });

  it("entoure de guillemets les valeurs contenant le séparateur", () => {
    const csv = buildCsv(["adresse"], [["Rue des Jardins; villa 12"]]);
    expect(csv).toContain('"Rue des Jardins; villa 12"');
  });

  it("double les guillemets présents dans une valeur", () => {
    const csv = buildCsv(["commentaire"], [['Il a dit "bonjour"']]);
    expect(csv).toContain('"Il a dit ""bonjour"""');
  });

  it("protège aussi les valeurs contenant un saut de ligne", () => {
    const csv = buildCsv(["note"], [["ligne 1\nligne 2"]]);
    expect(csv).toContain('"ligne 1\nligne 2"');
  });

  it("transforme null et undefined en cellule vide", () => {
    const csv = buildCsv(["a", "b", "c"], [[null, undefined, "x"]]);
    expect(csv.replace(/^﻿/, "")).toBe("a;b;c\r\n;;x\r\n");
  });

  it("écrit les dates au format ISO", () => {
    const csv = buildCsv(["date"], [[new Date("2026-08-03T14:00:00Z")]]);
    expect(csv).toContain("2026-08-03T14:00:00.000Z");
  });

  it("accepte une liste de lignes vide", () => {
    expect(buildCsv(["id"], []).replace(/^﻿/, "")).toBe("id\r\n");
  });
});
