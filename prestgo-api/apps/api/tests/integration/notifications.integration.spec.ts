import type { INestApplication } from "@nestjs/common";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { api, createTestApp, login, SEED_USERS } from "../helpers/test-app.js";

/**
 * Acheminement réel des notifications.
 *
 * Avant ce lot, `send()` créait une ligne au statut `queued` et s'arrêtait là.
 * Le statut ne changeait jamais et rien n'était acheminé, alors que l'interface
 * affichait la notification comme envoyée.
 */
describe("notifications", () => {
  let app: INestApplication;
  let token: string;
  let adminUserId: string;

  beforeAll(async () => {
    app = await createTestApp();
    token = await login(app, SEED_USERS.admin);

    const users = await api(app).get("/admin/users?search=admin@prestgo.test").set("Authorization", `Bearer ${token}`);
    adminUserId = users.body.data[0].id;
  });

  afterAll(async () => {
    await app.close();
  });

  const bearer = (): [string, string] => ["Authorization", `Bearer ${token}`];

  it("passe le statut à « sent » après traitement", async () => {
    const response = await api(app)
      .post("/admin/notifications/send")
      .set(...bearer())
      .send({ userId: adminUserId, type: "test", title: "Bienvenue", body: "Message de test." });

    expect(response.status).toBe(202);
    // C'est le cœur du correctif : le statut ne reste plus bloqué sur « queued ».
    expect(response.body.data.status).toBe("sent");
    expect(response.body.data.sentAt).not.toBeNull();
  });

  it("écrit réellement le message dans la boîte d'envoi pour un email", async () => {
    const titre = `Sujet ${Date.now()}`;

    const response = await api(app)
      .post("/admin/notifications/send")
      .set(...bearer())
      .send({ userId: adminUserId, type: "test", title: titre, body: "Corps du message.", channel: "email" });

    expect(response.body.data.status).toBe("sent");

    // Le transport de secours écrit un journal : on vérifie que le message y est.
    const outbox = resolve(process.env.NOTIFICATION_OUTBOX ?? "storage/outbox", "email.log");
    const contenu = await readFile(outbox, "utf8");
    expect(contenu).toContain(titre);
    expect(contenu).toContain(SEED_USERS.admin.email);
  });

  it("marque « failed » quand le destinataire est introuvable", async () => {
    // Notification SMS destinée au super admin, qui n'a pas de téléphone.
    const response = await api(app)
      .post("/admin/notifications/send")
      .set(...bearer())
      .send({ userId: adminUserId, type: "test", title: "SMS", body: "Test", channel: "sms" });

    expect(response.body.data.status).toBe("failed");
  });

  it("refuse un canal inconnu", async () => {
    const response = await api(app)
      .post("/admin/notifications/send")
      .set(...bearer())
      .send({ type: "test", title: "X", body: "Y", channel: "pigeon-voyageur" });

    expect(response.status).toBe(400);
  });

  it("refuse une notification sans titre", async () => {
    const response = await api(app)
      .post("/admin/notifications/send")
      .set(...bearer())
      .send({ type: "test", title: "", body: "Y" });

    expect(response.status).toBe(400);
  });

  describe("modèles", () => {
    it("liste les modèles sur le chemin du cahier des charges", async () => {
      const response = await api(app)
        .get("/admin/notification-templates")
        .set(...bearer());

      expect(response.status).toBe(200);
      expect(response.body.data.length).toBeGreaterThan(0);
    });

    it("modifie un modèle sans toucher à son code", async () => {
      const liste = await api(app)
        .get("/admin/notification-templates")
        .set(...bearer());
      const modele = liste.body.data[0];

      const response = await api(app)
        .patch(`/admin/notification-templates/${modele.id}`)
        .set(...bearer())
        .send({ titleTemplate: "Titre mis à jour" });

      expect(response.status).toBe(200);
      expect(response.body.data.titleTemplate).toBe("Titre mis à jour");
      // Le code sert de clé au code applicatif : il ne doit jamais changer.
      expect(response.body.data.code).toBe(modele.code);
    });
  });
});
