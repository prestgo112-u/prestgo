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

    /**
     * Écart n°13 du cahier des charges mobile.
     *
     * `errors[]` sortait sans `field` : l'application ne pouvait pas placer le
     * message sous le bon champ de formulaire, alors que `field` fait partie du
     * contrat depuis l'origine et que le filtre global sait déjà le lire.
     */
    describe("nom du champ fautif dans errors[] (§5.1)", () => {
      it("le renseigne sur POST /auth/register", async () => {
        const response = await api(app)
          .post("/auth/register")
          .send({ email: "pas-un-email", password: "court" });

        expect(response.status).toBe(400);
        const champs = response.body.errors.map((e: { field: string }) => e.field);
        expect(champs).toContain("email");
        expect(champs).toContain("password");

        const surEmail = response.body.errors.find((e: { field: string }) => e.field === "email");
        expect(surEmail.code).toBe("validation_error");
        expect(surEmail.message).toBe("Adresse email invalide");
      });

      it("le renseigne sur POST /me/addresses", async () => {
        const response = await api(app)
          .post("/me/addresses")
          .set(...bearer())
          .send({ label: "", city: "Abidjan", latitude: 999, longitude: -4 });

        expect(response.status).toBe(400);
        const champs = response.body.errors.map((e: { field: string }) => e.field);
        expect(champs).toContain("label");
        expect(champs).toContain("latitude");
        // Les champs valides ne produisent aucune entrée.
        expect(champs).not.toContain("city");
        expect(champs).not.toContain("longitude");
      });

      it("le renseigne sur POST /missions", async () => {
        const response = await api(app)
          .post("/missions")
          .set(...bearer())
          .send({
            providerId: "pas-un-uuid",
            packId: "pas-un-uuid-non-plus",
            scheduledAt: "pas-une-date",
            addressId: "toujours-pas"
          });

        expect(response.status).toBe(400);
        const champs = response.body.errors.map((e: { field: string }) => e.field);
        expect(champs).toEqual(
          expect.arrayContaining(["providerId", "packId", "scheduledAt", "addressId"])
        );
      });

      /**
       * Un tableau d'objets imbriqués doit dire QUEL élément est en cause :
       * « startTime invalide » sans indice de position serait inutilisable sur
       * une grille de sept jours.
       */
      it("construit un chemin complet pour un champ imbriqué", async () => {
        const providerToken = await login(app, SEED_USERS.provider);

        const response = await api(app)
          .put("/providers/me/availabilities")
          .set("Authorization", `Bearer ${providerToken}`)
          .send({
            slots: [
              { weekday: 1, startTime: "08:00", endTime: "12:00" },
              { weekday: 9, startTime: "pas-une-heure", endTime: "18:00" }
            ]
          });

        expect(response.status).toBe(400);
        const champs = response.body.errors.map((e: { field: string }) => e.field);
        // Le deuxième créneau (index 1) est le fautif, sur deux champs.
        expect(champs).toContain("slots.1.weekday");
        expect(champs).toContain("slots.1.startTime");
        // Le premier créneau est valide : il n'apparaît pas.
        expect(champs.some((c: string) => c.startsWith("slots.0."))).toBe(false);
      });

      it("garde le message de tête identique au premier de errors[]", async () => {
        const response = await api(app).post("/auth/register").send({ email: "pas-un-email", password: "court" });

        // Contrat historique préservé : les clients qui ne lisent que `message`
        // voient exactement ce qu'ils voyaient avant.
        expect(response.body.message).toBe(response.body.errors[0].message);
      });
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
