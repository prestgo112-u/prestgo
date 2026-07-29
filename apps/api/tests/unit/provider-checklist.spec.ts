import { describe, expect, it } from "vitest";
import {
  buildChecklist,
  checklistErrors,
  isChecklistComplete
} from "../../src/modules/providers/provider-checklist.js";

const COMPLETE = {
  publicName: "Kouassi Plomberie",
  bio: "Plombier depuis 8 ans.",
  bookableServices: 2,
  zones: 1,
  availabilities: 3,
  requiredDocumentTypes: ["id_card"],
  providedDocumentTypes: ["id_card"]
};

/**
 * Checklist de complétude du dossier prestataire (§5).
 *
 * Elle sert à deux endroits — l'affichage et le refus de soumission. Les tests
 * ci-dessous verrouillent le fait qu'ils voient la même chose : une checklist
 * verte avec un bouton qui refuse serait le pire des défauts.
 */
describe("checklist du dossier prestataire", () => {
  it("est complète quand tout est renseigné", () => {
    const checklist = buildChecklist(COMPLETE);

    expect(checklist).toEqual({
      profile: true,
      services: true,
      zones: true,
      availabilities: true,
      documents: true
    });
    expect(isChecklistComplete(checklist)).toBe(true);
    expect(checklistErrors(checklist)).toHaveLength(0);
  });

  it("refuse un profil sans présentation", () => {
    const checklist = buildChecklist({ ...COMPLETE, bio: "   " });

    expect(checklist.profile).toBe(false);
    expect(isChecklistComplete(checklist)).toBe(false);
  });

  /**
   * Un service sans formule active n'a ni prix ni durée : il n'est pas
   * réservable. La case ne doit donc pas être verte, sinon le dossier serait
   * validé pour aboutir à une fiche sans bouton de réservation.
   */
  it("refuse un service qui n'est pas réservable", () => {
    expect(buildChecklist({ ...COMPLETE, bookableServices: 0 }).services).toBe(false);
  });

  it("refuse un dossier sans zone ni disponibilité", () => {
    expect(buildChecklist({ ...COMPLETE, zones: 0 }).zones).toBe(false);
    expect(buildChecklist({ ...COMPLETE, availabilities: 0 }).availabilities).toBe(false);
  });

  it("exige TOUS les types de justificatifs demandés", () => {
    const checklist = buildChecklist({
      ...COMPLETE,
      requiredDocumentTypes: ["id_card", "insurance"],
      providedDocumentTypes: ["id_card"]
    });

    expect(checklist.documents).toBe(false);
  });

  it("n'exige aucun justificatif si le réglage est vide", () => {
    const checklist = buildChecklist({ ...COMPLETE, requiredDocumentTypes: [], providedDocumentTypes: [] });
    expect(checklist.documents).toBe(true);
  });

  it("explique CE QUI manque, pas seulement que le dossier est incomplet", () => {
    const checklist = buildChecklist({ ...COMPLETE, zones: 0, availabilities: 0 });
    const errors = checklistErrors(checklist);

    expect(errors.map((error) => error.field).sort()).toEqual(["availabilities", "zones"]);
    expect(errors.every((error) => error.message.length > 10)).toBe(true);
  });
});
