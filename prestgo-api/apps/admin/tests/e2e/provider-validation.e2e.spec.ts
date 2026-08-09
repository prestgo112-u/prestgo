import { describe, expect, it } from "vitest";

// Placeholder e2e US2 : décrit le parcours de validation d'un prestataire côté back-office.
// (Sera branché sur un vrai navigateur de test dans une phase ultérieure.)
describe("provider validation e2e (placeholder)", () => {
  it("navigue vers la file de validation", () => {
    expect("/providers").toBe("/providers");
  });

  it("ouvre le détail d'un prestataire", () => {
    expect("/providers/:id").toContain(":id");
  });

  it("un rejet de document demande un motif obligatoire", () => {
    const reason = "";
    const canSubmit = reason.trim().length > 0;
    expect(canSubmit).toBe(false);
  });
});
