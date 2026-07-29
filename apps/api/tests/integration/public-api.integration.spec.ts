import type { INestApplication } from "@nestjs/common";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { api, createTestApp, login, SEED_USERS } from "../helpers/test-app.js";

/**
 * Surface publique : ce que voit une application cliente sans compte.
 *
 * L'enjeu principal est le filtrage : ne doivent sortir que les éléments
 * ACTIFS et PUBLIÉS. Une catégorie désactivée reste en base pour l'historique,
 * mais ne doit plus apparaître dans la vitrine.
 */
describe("API publique", () => {
  let app: INestApplication;
  let adminToken: string;
  let providerId: string;

  beforeAll(async () => {
    app = await createTestApp();
    adminToken = await login(app, SEED_USERS.admin);

    const providers = await api(app).get("/admin/providers?search=Kofi").set("Authorization", `Bearer ${adminToken}`);
    providerId = providers.body.data[0].id;
  });

  afterAll(async () => {
    await app.close();
  });

  describe("accessible sans compte", () => {
    it("expose les catégories", async () => {
      const response = await api(app).get("/categories");

      expect(response.status).toBe(200);
      expect(response.body.data.length).toBeGreaterThan(0);
    });

    it("expose les zones", async () => {
      const response = await api(app).get("/zones");
      expect(response.status).toBe(200);
    });

    /**
     * Écart n°6 du cahier des charges mobile : les six réglages qui pilotent
     * des règles visibles par l'utilisateur ne se lisaient que par
     * `/admin/settings`. L'application devait les coder en dur, et mentait dès
     * que l'exploitation en modifiait un.
     */
    it("expose les réglages métier que l'application doit refléter", async () => {
      const response = await api(app).get("/settings/public");

      expect(response.status).toBe(200);
      expect(response.body.data).toEqual({
        missionMinLeadTimeMinutes: expect.any(Number),
        missionCancellationNoticeHours: expect.any(Number),
        missionStartWindowMinutes: expect.any(Number),
        missionPendingExpiryHours: expect.any(Number),
        missionAutoCloseDays: expect.any(Number),
        reviewsWindowDays: expect.any(Number)
      });
    });

    it("n'expose QUE ces six réglages, jamais la table complète", async () => {
      const publics = await api(app).get("/settings/public");
      const complets = await api(app).get("/admin/settings").set("Authorization", `Bearer ${adminToken}`);

      expect(Object.keys(publics.body.data)).toHaveLength(6);
      // La table d'administration en contient davantage : la route publique est
      // une liste fermée, pas un miroir.
      expect(complets.body.data.length).toBeGreaterThan(6);
      expect(JSON.stringify(publics.body.data)).not.toContain("required_document_types");
    });

    it("reflète un réglage modifié dans le back-office", async () => {
      const initial = await api(app).get("/settings/public");
      const avant = initial.body.data.reviewsWindowDays as number;
      const nouveau = avant + 3;

      const miseAJour = await api(app)
        .patch("/admin/settings/reviews.window_days")
        .set("Authorization", `Bearer ${adminToken}`)
        .send({ value: String(nouveau) });
      expect(miseAJour.status).toBe(200);

      // Le cache est vidé à l'écriture : la nouvelle valeur sort tout de suite.
      const apres = await api(app).get("/settings/public");
      expect(apres.body.data.reviewsWindowDays).toBe(nouveau);

      // On remet la valeur d'origine pour ne pas polluer les autres suites.
      await api(app)
        .patch("/admin/settings/reviews.window_days")
        .set("Authorization", `Bearer ${adminToken}`)
        .send({ value: String(avant) });
    });

    it("expose la vitrine d'un prestataire", async () => {
      const packs = await api(app).get(`/providers/${providerId}/service-packs`);
      const agenda = await api(app).get(`/providers/${providerId}/availabilities`);
      const avis = await api(app).get(`/providers/${providerId}/reviews`);

      expect(packs.status).toBe(200);
      expect(agenda.status).toBe(200);
      expect(avis.status).toBe(200);
      expect(avis.body.data).toHaveProperty("averageRating");
      expect(avis.body.data).toHaveProperty("totalReviews");
    });
  });

  describe("ne montre que ce qui est actif", () => {
    it("retire une catégorie désactivée de la vitrine mais la garde en admin", async () => {
      const avant = await api(app).get("/categories");
      const categorie = avant.body.data[0];

      await api(app).delete(`/admin/categories/${categorie.id}`).set("Authorization", `Bearer ${adminToken}`);

      const apres = await api(app).get("/categories");
      const idsPublics = apres.body.data.map((c: { id: string }) => c.id);
      expect(idsPublics).not.toContain(categorie.id);

      const cotéAdmin = await api(app).get("/admin/categories").set("Authorization", `Bearer ${adminToken}`);
      const idsAdmin = cotéAdmin.body.data.map((c: { id: string }) => c.id);
      expect(idsAdmin).toContain(categorie.id);

      // On remet en état pour ne pas perturber les autres suites.
      await api(app)
        .patch(`/admin/categories/${categorie.id}`)
        .set("Authorization", `Bearer ${adminToken}`)
        .send({ active: true });
    });
  });

  describe("recherche géographique", () => {
    it("trouve une zone proche et écarte les lointaines", async () => {
      // Cocody est à environ 5,4 km du Plateau.
      const proche = await api(app).get("/zones/nearby?latitude=5.325&longitude=-4.022&radiusKm=10");
      const loin = await api(app).get("/zones/nearby?latitude=5.325&longitude=-4.022&radiusKm=3");

      expect(proche.status).toBe(200);
      expect(proche.body.data.length).toBeGreaterThan(0);
      expect(proche.body.data[0].distanceKm).toBeGreaterThan(4);
      expect(proche.body.data[0].distanceKm).toBeLessThan(7);

      expect(loin.body.data).toHaveLength(0);
    });

    it("trie du plus proche au plus lointain", async () => {
      const response = await api(app).get("/zones/nearby?latitude=5.35&longitude=-3.98&radiusKm=200");
      const distances = response.body.data.map((z: { distanceKm: number }) => z.distanceKm);

      expect(distances).toEqual([...distances].sort((a: number, b: number) => a - b));
    });

    it("refuse des coordonnées invalides", async () => {
      const response = await api(app).get("/zones/nearby?latitude=999&longitude=-4");
      expect(response.status).toBe(400);
    });
  });

  describe("documentation", () => {
    it("expose le contrat OpenAPI", async () => {
      const response = await api(app).get("/../docs-json").redirects(0);
      // Swagger est monté hors du préfixe /api/v1 ; on vérifie surtout que le
      // serveur répond sans erreur serveur.
      expect(response.status).toBeLessThan(500);
    });
  });
});
