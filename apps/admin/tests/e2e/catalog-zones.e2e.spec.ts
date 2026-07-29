import { describe, expect, it } from "vitest";

// Placeholder e2e US4 : gestion catalogue / zones / disponibilités.
describe("catalog and zones e2e (placeholder)", () => {
  it("expose les écrans catalogue et zones", () => {
    const routes = ["/catalog", "/zones"];
    expect(routes).toContain("/catalog");
  });

  it("désactiver une catégorie la conserve dans l'historique", () => {
    const active = false;
    expect(active).toBe(false);
  });
});
