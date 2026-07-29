import { describe, expect, it } from "vitest";
import { assertTestDatabaseUrl, TEST_DATABASE_SUFFIX } from "../helpers/global-setup.js";

/**
 * Garde de sécurité de la réinitialisation de la base de test.
 *
 * `global-setup.ts` exécute un `TRUNCATE ... CASCADE` sur toutes les tables, et
 * dans sa branche de secours un `DROP SCHEMA public CASCADE`. Ces deux
 * opérations sont irréversibles. `assertTestDatabaseUrl` est le SEUL contrôle
 * qui les empêche de s'exécuter contre une base de développement ou de
 * production : ces tests vérifient qu'elle refuse effectivement.
 *
 * Aucune connexion n'est ouverte ici — on teste la fonction de garde seule.
 */
describe("garde de la base de test (assertTestDatabaseUrl)", () => {
  describe("accepte une base de test légitime", () => {
    it("accepte l'URL de test nominale du projet et renvoie le nom de base", () => {
      const url = "postgresql://postgres:29122003@localhost:5432/prestgo_test?schema=public";
      expect(assertTestDatabaseUrl(url)).toBe("prestgo_test");
    });

    it("accepte une URL sans paramètres de requête", () => {
      expect(assertTestDatabaseUrl("postgresql://u:p@localhost:5432/prestgo_test")).toBe("prestgo_test");
    });

    it("accepte le schéma d'URL « postgres:// » comme « postgresql:// »", () => {
      expect(assertTestDatabaseUrl("postgres://u:p@localhost:5432/autre_projet_test")).toBe("autre_projet_test");
    });
  });

  describe("refuse ce qui n'est pas une base de test", () => {
    it("refuse la base de DÉVELOPPEMENT du projet", () => {
      // C'est exactement le DATABASE_URL présent dans apps/api/.env.
      const dev = "postgresql://postgres:29122003@localhost:5432/prestgo?schema=public";
      expect(() => assertTestDatabaseUrl(dev)).toThrow(/ne se termine pas par/);
      expect(() => assertTestDatabaseUrl(dev)).toThrow(/prestgo/);
    });

    it("refuse une base de production", () => {
      expect(() =>
        assertTestDatabaseUrl("postgresql://u:p@prod.rds.amazonaws.com:5432/prestgo_prod?schema=public")
      ).toThrow(/Refus d'opérer sur la base « prestgo_prod »/);
    });

    /**
     * RÉGRESSION — la faille que ce correctif referme.
     *
     * L'ancienne garde testait `/_test(\?|$)/` sur la chaîne ENTIÈRE. Sur cette
     * URL, `toTestUrl` (`test-env.ts`) voit le segment `/x_test` en fin de
     * chaîne, croit l'URL « déjà transformée » et la renvoie inchangée ; puis
     * l'ancienne garde trouvait `_test` en fin de chaîne et laissait passer.
     * La base réellement ciblée est `prestgo_prod`.
     */
    it("refuse une base de production dont la QUERY contient un segment « /..._test »", () => {
      const piege = "postgresql://u:p@prod-host:5432/prestgo_prod?opt=/x_test";

      // Preuve que l'ancienne heuristique laissait effectivement passer.
      expect(/_test(\?|$)/.test(piege)).toBe(true);

      // La garde actuelle, qui lit le nom de base, refuse.
      expect(() => assertTestDatabaseUrl(piege)).toThrow(/Refus d'opérer sur la base « prestgo_prod »/);
    });

    it("refuse une base dont le nom CONTIENT « test » sans finir par le suffixe", () => {
      // `_testing` n'est pas `_test` : une base nommée ainsi peut très bien être
      // un environnement réel qu'on ne doit pas vider.
      expect(() => assertTestDatabaseUrl("postgresql://u:p@h:5432/prestgo_testing")).toThrow(
        /ne se termine pas par/
      );
      expect(() => assertTestDatabaseUrl("postgresql://u:p@h:5432/test_prestgo")).toThrow(
        /ne se termine pas par/
      );
    });
  });

  describe("refuse toute entrée qui ne permet pas de prouver la cible", () => {
    it("refuse une URL absente, vide ou blanche — jamais de défaut implicite", () => {
      expect(() => assertTestDatabaseUrl(undefined)).toThrow(/absente ou vide/);
      expect(() => assertTestDatabaseUrl(null)).toThrow(/absente ou vide/);
      expect(() => assertTestDatabaseUrl("")).toThrow(/absente ou vide/);
      expect(() => assertTestDatabaseUrl("   ")).toThrow(/absente ou vide/);
    });

    it("refuse une URL non analysable", () => {
      expect(() => assertTestDatabaseUrl("ceci-nest-pas-une-url_test")).toThrow(/pas une URL analysable/);
    });

    it("refuse une URL sans nom de base", () => {
      expect(() => assertTestDatabaseUrl("postgresql://u:p@localhost:5432")).toThrow(/aucune base nommée/);
      expect(() => assertTestDatabaseUrl("postgresql://u:p@localhost:5432/")).toThrow(/aucune base nommée/);
    });
  });

  describe("ne divulgue pas le mot de passe dans ses messages d'erreur", () => {
    it("masque le mot de passe de l'URL refusée", () => {
      const secret = "MotDePasseTresSecret123";
      let message = "";
      try {
        assertTestDatabaseUrl(`postgresql://postgres:${secret}@prod-host:5432/prestgo_prod?schema=public`);
      } catch (error) {
        message = error instanceof Error ? error.message : String(error);
      }

      expect(message).not.toBe("");
      expect(message).not.toContain(secret);
      expect(message).toContain(":***@");
      // Le nom de la base, lui, doit rester lisible : c'est l'information utile.
      expect(message).toContain("prestgo_prod");
    });
  });

  it("expose le suffixe attendu, pour que la convention reste vérifiable", () => {
    expect(TEST_DATABASE_SUFFIX).toBe("_test");
  });
});
