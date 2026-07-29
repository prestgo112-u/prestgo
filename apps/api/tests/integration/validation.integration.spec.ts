import type { INestApplication } from "@nestjs/common";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { api, createTestApp, login, SEED_USERS } from "../helpers/test-app.js";

/**
 * Validation des entrées et format des réponses.
 *
 * Jusqu'au Lot 1, aucune donnée envoyée à l'API n'était vérifiée : le
 * `ValidationPipe` était bien branché mais tournait à vide, faute de DTO.
 */
describe("validation et format des réponses", () => {
  let app: INestApplication;
  let token: string;

  beforeAll(async () => {
    app = await createTestApp();
    token = await login(app, SEED_USERS.admin);
  });

  afterAll(async () => {
    await app.close();
  });

  const bearer = (): [string, string] => ["Authorization", `Bearer ${token}`];

  describe("corps de requête", () => {
    it("refuse une latitude aberrante", async () => {
      const response = await api(app)
        .post("/admin/zones")
        .set(...bearer())
        .send({ name: "Zone test", latitude: 999, longitude: -4, radiusKm: 5 });

      expect(response.status).toBe(400);
      expect(response.body.message).toContain("latitude");
    });

    it("refuse un statut de mission inventé", async () => {
      const response = await api(app)
        .patch("/admin/missions/00000000-0000-0000-0000-000000000000/status")
        .set(...bearer())
        .send({ status: "n_importe_quoi" });

      expect(response.status).toBe(400);
      expect(response.body.message).toBe("Statut de mission inconnu");
    });

    it("exige un motif pour annuler une mission", async () => {
      const response = await api(app)
        .post("/admin/missions/00000000-0000-0000-0000-000000000000/cancel")
        .set(...bearer())
        .send({});

      expect(response.status).toBe(400);
    });

    it("refuse un identifiant qui n'est pas un UUID", async () => {
      const response = await api(app)
        .post("/admin/service-types")
        .set(...bearer())
        .send({ categoryId: "pas-un-uuid", name: "Test", slug: "test" });

      expect(response.status).toBe(400);
    });

    it("refuse un slug avec des majuscules ou des espaces", async () => {
      const response = await api(app)
        .post("/admin/categories")
        .set(...bearer())
        .send({ name: "Catégorie test", slug: "Slug Invalide" });

      expect(response.status).toBe(400);
      expect(response.body.message).toContain("minuscules");
    });

    it("liste toutes les erreurs, pas seulement la première", async () => {
      const response = await api(app).post("/auth/login").send({ email: "pas-un-email", password: "" });

      expect(response.status).toBe(400);
      expect(response.body.errors.length).toBeGreaterThanOrEqual(2);
    });
  });

  describe("paramètres d'URL", () => {
    it("plafonne la taille de page", async () => {
      const response = await api(app)
        .get("/admin/users?limit=5000")
        .set(...bearer());

      expect(response.status).toBe(400);
      expect(response.body.message).toContain("100");
    });

    it("refuse une page inférieure à 1", async () => {
      const response = await api(app)
        .get("/admin/users?page=0")
        .set(...bearer());

      expect(response.status).toBe(400);
    });

    it("convertit les nombres reçus en texte", async () => {
      const response = await api(app)
        .get("/admin/users?page=1&limit=5")
        .set(...bearer());

      expect(response.status).toBe(200);
      expect(response.body.meta.limit).toBe(5);
    });

    /**
     * Bug corrigé au Lot 2 : un formulaire dont le filtre est sur « Tous »
     * envoie `?status=`. `@IsOptional` ne saute que null et undefined, pas la
     * chaîne vide — la requête était donc rejetée.
     */
    it("traite un filtre vide comme absent", async () => {
      const response = await api(app)
        .get("/admin/providers?validationStatus=&search=")
        .set(...bearer());

      expect(response.status).toBe(200);
    });

    it("refuse quand même une valeur réellement invalide", async () => {
      const response = await api(app)
        .get("/admin/providers?validationStatus=inexistant")
        .set(...bearer());

      expect(response.status).toBe(400);
    });
  });

  describe("format standard des réponses", () => {
    it("respecte { success, message, data, meta } en cas de succès", async () => {
      const response = await api(app)
        .get("/admin/users")
        .set(...bearer());

      expect(response.body).toMatchObject({ success: true });
      expect(response.body.data).toBeInstanceOf(Array);
      expect(response.body.meta).toMatchObject({ page: expect.any(Number), total: expect.any(Number) });
    });

    it("respecte { success, message, errors, meta } en cas d'erreur", async () => {
      const response = await api(app).get("/admin/users");

      expect(response.body.success).toBe(false);
      expect(response.body.message).toBeTypeOf("string");
      expect(response.body.errors).toBeInstanceOf(Array);
      expect(response.body.meta.correlationId).toBeTypeOf("string");
    });

    it("ne laisse pas fuiter de détail technique sur une erreur interne", async () => {
      // Un identifiant au mauvais format fait échouer la requête en base.
      const response = await api(app)
        .get("/admin/users/ceci-nest-pas-un-uuid")
        .set(...bearer());

      // Peu importe le code : le message ne doit jamais exposer Prisma ni SQL.
      const message = String(response.body.message);
      expect(message.toLowerCase()).not.toContain("prisma");
      expect(message.toLowerCase()).not.toContain("select");
      expect(message).not.toContain("\n");
    });
  });
});
