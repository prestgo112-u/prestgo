import type { INestApplication } from "@nestjs/common";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { api, createTestApp, login, SEED_USERS, uniqueEmail, uniquePhone } from "../helpers/test-app.js";

/**
 * Contrôle d'accès : permissions du back-office et appartenance aux missions.
 *
 * C'est la suite la plus importante du projet. Chaque test correspond à une
 * façon de contourner les protections ; s'il passe au rouge, quelqu'un peut
 * voir ou modifier des données qui ne le concernent pas.
 */
describe("contrôle d'accès", () => {
  let app: INestApplication;
  let adminToken: string;
  let providerToken: string;
  let clientToken: string;
  let strangerToken: string;
  let missionId: string;
  let threadId: string;

  beforeAll(async () => {
    app = await createTestApp();

    // Les jetons sont récupérés UNE fois : /auth/login est limité en débit.
    adminToken = await login(app, SEED_USERS.admin);
    providerToken = await login(app, SEED_USERS.provider);
    clientToken = await login(app, SEED_USERS.client);

    // Un compte tiers, sans lien avec la mission de démonstration.
    const email = uniqueEmail("tiers-acces");
    const phone = uniquePhone(7);
    await api(app).post("/auth/register").send({ email, phone, password: "motdepasse1" });
    const otp = await api(app).post("/auth/otp/send").send({ target: phone });
    await api(app).post("/auth/otp/verify").send({ target: phone, code: otp.body.data.devCode });
    strangerToken = await login(app, { email, password: "motdepasse1" });

    // On cible la mission DU CLIENT DE DÉMONSTRATION, et non « la plus
    // récente » : d'autres suites créent des missions, et prendre la première
    // venue reviendrait à tester l'appartenance sur une mission dont le client
    // du seed n'est pas partie.
    const missions = await api(app)
      .get(`/admin/missions?search=${encodeURIComponent(SEED_USERS.client.email)}`)
      .set("Authorization", `Bearer ${adminToken}`);
    missionId = missions.body.data[0].id;

    // Même raisonnement pour le fil : c'est celui de CETTE mission.
    const thread = await api(app).get(`/missions/${missionId}/thread`).set("Authorization", `Bearer ${clientToken}`);
    threadId = thread.body.data.id;
  });

  afterAll(async () => {
    await app.close();
  });

  describe("permissions du back-office", () => {
    it("laisse passer le super admin", async () => {
      const response = await api(app).get("/admin/settings").set("Authorization", `Bearer ${adminToken}`);
      expect(response.status).toBe(200);
    });

    it("refuse un compte sans la permission requise", async () => {
      const response = await api(app).get("/admin/settings").set("Authorization", `Bearer ${clientToken}`);

      expect(response.status).toBe(403);
      expect(response.body.message).toBe("Permission denied");
    });

    it("protège toutes les routes d'administration testées", async () => {
      const routes = ["/admin/users", "/admin/providers", "/admin/missions", "/admin/disputes", "/admin/audit-logs"];

      for (const route of routes) {
        const sansJeton = await api(app).get(route);
        expect(sansJeton.status, `${route} sans jeton`).toBe(401);

        const sansDroit = await api(app).get(route).set("Authorization", `Bearer ${clientToken}`);
        expect(sansDroit.status, `${route} sans permission`).toBe(403);
      }
    });
  });

  describe("appartenance à une mission", () => {
    it("autorise le client et le prestataire de la mission", async () => {
      const client = await api(app).get(`/missions/${missionId}/history`).set("Authorization", `Bearer ${clientToken}`);
      const provider = await api(app)
        .get(`/missions/${missionId}/history`)
        .set("Authorization", `Bearer ${providerToken}`);

      expect(client.status).toBe(200);
      expect(provider.status).toBe(200);
    });

    it("autorise l'administrateur", async () => {
      const response = await api(app).get(`/missions/${missionId}/history`).set("Authorization", `Bearer ${adminToken}`);
      expect(response.status).toBe(200);
    });

    it("REFUSE un tiers connecté", async () => {
      const response = await api(app)
        .get(`/missions/${missionId}/history`)
        .set("Authorization", `Bearer ${strangerToken}`);

      expect(response.status).toBe(403);
      expect(response.body.message).toContain("pas partie à cette mission");
    });

    it("refuse sans aucun jeton", async () => {
      const response = await api(app).get(`/missions/${missionId}/history`);
      expect(response.status).toBe(401);
    });
  });

  describe("conversation d'une mission", () => {
    it("laisse les parties écrire", async () => {
      const response = await api(app)
        .post(`/messages/threads/${threadId}/messages`)
        .set("Authorization", `Bearer ${clientToken}`)
        .send({ message: "Bonjour, à quelle heure passez-vous ?" });

      expect(response.status).toBe(201);
    });

    it("REFUSE à un tiers d'écrire dans la conversation", async () => {
      const response = await api(app)
        .post(`/messages/threads/${threadId}/messages`)
        .set("Authorization", `Bearer ${strangerToken}`)
        .send({ message: "je m'introduis" });

      expect(response.status).toBe(403);
    });

    it("REFUSE à un tiers de lire la conversation", async () => {
      const response = await api(app)
        .get(`/messages/threads/${threadId}/messages`)
        .set("Authorization", `Bearer ${strangerToken}`);

      expect(response.status).toBe(403);
    });

    it("refuse un message vide", async () => {
      const response = await api(app)
        .post(`/messages/threads/${threadId}/messages`)
        .set("Authorization", `Bearer ${clientToken}`)
        .send({ message: "" });

      expect(response.status).toBe(400);
    });
  });

  describe("ouverture d'un litige", () => {
    it("laisse le client ouvrir un litige sur SA mission", async () => {
      const response = await api(app)
        .post("/disputes")
        .set("Authorization", `Bearer ${clientToken}`)
        .send({ missionId, reason: "Prestation incomplète", description: "Le problème persiste." });

      expect(response.status).toBe(201);
    });

    it("REFUSE à un tiers d'ouvrir un litige sur la mission d'autrui", async () => {
      const response = await api(app)
        .post("/disputes")
        .set("Authorization", `Bearer ${strangerToken}`)
        .send({ missionId, reason: "Je réclame" });

      expect(response.status).toBe(403);
    });
  });

  describe("espace prestataire", () => {
    it("refuse /providers/me à un compte sans profil prestataire", async () => {
      const response = await api(app)
        .put("/providers/me/availabilities")
        .set("Authorization", `Bearer ${clientToken}`)
        .send({ slots: [] });

      expect(response.status).toBe(403);
      expect(response.body.message).toContain("pas de profil prestataire");
    });

    it("laisse le prestataire gérer son propre agenda", async () => {
      const response = await api(app)
        .put("/providers/me/availabilities")
        .set("Authorization", `Bearer ${providerToken}`)
        .send({
          slots: [
            { weekday: 1, startTime: "08:00", endTime: "12:00" },
            { weekday: 3, startTime: "14:00", endTime: "18:00" }
          ]
        });

      // PUT renvoie 200 (seul POST vaut 201 par défaut dans NestJS).
      expect(response.status).toBe(200);
      expect(response.body.data).toHaveLength(2);
    });

    /**
     * Écart n°11 du cahier des charges mobile : l'écriture avait son PUT, la
     * lecture passait par la route PUBLIQUE `/providers/:id/availabilities`
     * avec son propre identifiant — un détour qui obligeait l'application à
     * connaître son `providerId` avant même d'afficher l'écran.
     */
    it("laisse le prestataire relire son propre agenda, sans passer par son providerId", async () => {
      // On réécrit VOLONTAIREMENT le même agenda que le test précédent : les
      // suites tournent en parallèle sur la même base et partagent ce
      // prestataire. Poser d'autres jours ici retirerait le lundi, dont
      // `mission-flow` a besoin pour sa recherche par créneau.
      await api(app)
        .put("/providers/me/availabilities")
        .set("Authorization", `Bearer ${providerToken}`)
        .send({
          slots: [
            { weekday: 1, startTime: "08:00", endTime: "12:00" },
            { weekday: 3, startTime: "14:00", endTime: "18:00" }
          ]
        });

      const relecture = await api(app)
        .get("/providers/me/availabilities")
        .set("Authorization", `Bearer ${providerToken}`);

      expect(relecture.status).toBe(200);
      // Miroir exact de ce que le PUT vient d'enregistrer.
      expect(relecture.body.data).toHaveLength(2);
      expect(relecture.body.data.map((s: { weekday: number }) => s.weekday)).toEqual([1, 3]);
      expect(relecture.body.data[0]).toMatchObject({ weekday: 1, startTime: "08:00", endTime: "12:00" });
    });

    it("refuse la relecture de l'agenda à un compte sans profil prestataire", async () => {
      const response = await api(app)
        .get("/providers/me/availabilities")
        .set("Authorization", `Bearer ${clientToken}`);

      expect(response.status).toBe(403);
      expect(response.body.message).toContain("pas de profil prestataire");
    });
  });

  describe("commentaire interne d'un litige", () => {
    it("n'expose pas les notes des agents au client", async () => {
      // On ouvre un litige, puis on y ajoute un message visible et une note interne.
      const created = await api(app)
        .post("/disputes")
        .set("Authorization", `Bearer ${clientToken}`)
        .send({ missionId, reason: "Test de confidentialité" });
      const disputeId = created.body.data.id;

      await api(app)
        .post(`/admin/disputes/${disputeId}/messages`)
        .set("Authorization", `Bearer ${adminToken}`)
        .send({ message: "Message visible des parties." });

      await api(app)
        .post(`/admin/disputes/${disputeId}/messages`)
        .set("Authorization", `Bearer ${adminToken}`)
        .send({ message: "NOTE INTERNE confidentielle.", internalOnly: true });

      const vuAdmin = await api(app).get(`/admin/disputes/${disputeId}`).set("Authorization", `Bearer ${adminToken}`);
      const vuClient = await api(app).get(`/disputes/${disputeId}`).set("Authorization", `Bearer ${clientToken}`);

      const messagesAdmin = vuAdmin.body.data.messages.map((m: { message: string }) => m.message);
      const messagesClient = vuClient.body.data.messages.map((m: { message: string }) => m.message);

      expect(messagesAdmin).toContain("NOTE INTERNE confidentielle.");
      expect(messagesClient).toContain("Message visible des parties.");
      expect(messagesClient).not.toContain("NOTE INTERNE confidentielle.");
    });
  });
});
