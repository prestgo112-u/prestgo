import { describe, expect, it } from "vitest";
import {
  CURRENT_SCRYPT_PARAMS,
  hashPassword,
  needsRehash,
  verifyPassword
} from "../../src/common/security/password.js";

/**
 * Format du hash de mot de passe (§15.2).
 *
 * L'enjeu : les paramètres de coût doivent VOYAGER AVEC l'empreinte. Sans eux,
 * durcir scrypt invaliderait tous les mots de passe existants — chaque
 * vérification recalculerait l'empreinte avec des réglages différents de ceux
 * qui ont servi à la produire.
 */
describe("empreinte de mot de passe", () => {
  it("écrit les paramètres de coût dans l'empreinte", async () => {
    const stored = await hashPassword("motdepasse123");
    const parts = stored.split("$");

    expect(parts[0]).toBe("scrypt");
    expect(Number(parts[1])).toBe(CURRENT_SCRYPT_PARAMS.N);
    expect(Number(parts[2])).toBe(CURRENT_SCRYPT_PARAMS.r);
    expect(Number(parts[3])).toBe(CURRENT_SCRYPT_PARAMS.p);
    expect(parts).toHaveLength(6);
  });

  it("vérifie un mot de passe correct et refuse un mauvais", async () => {
    const stored = await hashPassword("motdepasse123");

    await expect(verifyPassword("motdepasse123", stored)).resolves.toBe(true);
    await expect(verifyPassword("motdepasse124", stored)).resolves.toBe(false);
  });

  it("produit une empreinte différente à chaque fois (sel aléatoire)", async () => {
    const a = await hashPassword("motdepasse123");
    const b = await hashPassword("motdepasse123");

    expect(a).not.toBe(b);
  });

  /**
   * Le point décisif de la bascule : les comptes créés avant le Lot 7 portent
   * une empreinte à trois segments. Ils doivent continuer à se connecter.
   */
  it("vérifie encore les empreintes de l'ancien format", async () => {
    // Empreinte produite comme avant le Lot 7 : paramètres implicites de Node.
    const { randomBytes, scryptSync } = await import("node:crypto");
    const salt = randomBytes(16);
    const derived = scryptSync("ancienmotdepasse1", salt, 64);
    const legacy = `scrypt$${salt.toString("hex")}$${derived.toString("hex")}`;

    await expect(verifyPassword("ancienmotdepasse1", legacy)).resolves.toBe(true);
    await expect(verifyPassword("autre", legacy)).resolves.toBe(false);
    // …et elle est signalée comme à ré-encoder.
    expect(needsRehash(legacy)).toBe(true);
  });

  it("ne demande pas de ré-encodage pour une empreinte au coût courant", async () => {
    expect(needsRehash(await hashPassword("motdepasse123"))).toBe(false);
  });

  it("refuse proprement une empreinte illisible au lieu de planter", async () => {
    await expect(verifyPassword("x", "")).resolves.toBe(false);
    await expect(verifyPassword("x", "bcrypt$abc$def")).resolves.toBe(false);
    // `N` non puissance de deux : scrypt refuserait de calculer.
    await expect(verifyPassword("x", "scrypt$1000$8$1$aa$bb")).resolves.toBe(false);
  });
});
