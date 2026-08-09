import type { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@prisma/client";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { api, auth, createTestApp, login, uniqueEmail } from "../helpers/test-app.js";

const PASSWORD = "trides1234";
const prisma = new PrismaClient();

/**
 * Prochaine occurrence d'un jour de la semaine, à une heure donnée (UTC).
 *
 * Les créneaux du prestataire sont hebdomadaires : une date fixe ferait
 * échouer le test selon le jour d'exécution.
 */
function nextWeekdayAt(weekday: number, hour: number, weeksAhead = 1): Date {
  const date = new Date();
  date.setUTCHours(hour, 0, 0, 0);
  const delta = (weekday - date.getUTCDay() + 7) % 7 || 7;
  date.setUTCDate(date.getUTCDate() + delta + 7 * (weeksAhead - 1));
  return date;
}

/**
 * `sort` sur les cinq listes mobiles (§15.4, corrigé après l'audit).
 *
 * Le paramètre était accepté et validé, mais IGNORÉ par ces cinq listes :
 * elles retombaient toujours sur leur ordre figé. Chaque bloc ci-dessous
 * vérifie deux choses :
 *   1. un tri valide change réellement l'ordre renvoyé ;
 *   2. un tri invalide (champ inconnu) ne fait PAS échouer la requête — elle
 *      retombe proprement sur l'ordre par défaut (comportement « tolérant »,
 *      propre aux listes mobiles — les listes du back-office, elles,
 *      continuent de refuser explicitement un champ inconnu).
 */
describe("tri des listes mobiles", () => {
  let app: INestApplication;
  let clientToken: string;
  let providerToken: string;
  let providerId: string;
  let missionEarlyId: string;
  let missionLateId: string;

  beforeAll(async () => {
    app = await createTestApp();

    // --- Client ---
    const clientEmail = uniqueEmail("sort-client");
    await api(app).post("/auth/register").send({ email: clientEmail, password: PASSWORD, firstName: "Client" });
    const clientOtp = await api(app).post("/auth/otp/send").send({ target: clientEmail, purpose: "email_verification" });
    await api(app)
      .post("/auth/otp/verify")
      .send({ target: clientEmail, code: clientOtp.body.data.devCode, purpose: "email_verification" });
    clientToken = await login(app, { email: clientEmail, password: PASSWORD });

    const address = await api(app)
      .post("/me/addresses")
      .set(...auth(clientToken))
      .send({ label: "Domicile", city: "Abidjan", latitude: 5.35, longitude: -3.98 });
    const addressId = address.body.data.id;

    // --- Prestataire, dossier complet et approuvé ---
    const providerEmail = uniqueEmail("sort-provider");
    await api(app).post("/auth/register").send({ email: providerEmail, password: PASSWORD, firstName: "Presta" });
    const providerOtp = await api(app)
      .post("/auth/otp/send")
      .send({ target: providerEmail, purpose: "email_verification" });
    await api(app)
      .post("/auth/otp/verify")
      .send({ target: providerEmail, code: providerOtp.body.data.devCode, purpose: "email_verification" });
    providerToken = await login(app, { email: providerEmail, password: PASSWORD });

    const profile = await api(app)
      .post("/providers/me")
      .set(...auth(providerToken))
      .send({ publicName: `Tri ${Date.now()}`, bio: "Prestataire de test pour le tri.", experienceYears: 3 });
    providerId = profile.body.data.id;

    const zones = await api(app).get("/zones");
    const zoneId = zones.body.data[0].id;
    await api(app).put("/providers/me/zones").set(...auth(providerToken)).send({ zoneIds: [zoneId] });
    await api(app)
      .put("/providers/me/availabilities")
      .set(...auth(providerToken))
      .send({ slots: [{ weekday: 3, startTime: "08:00", endTime: "18:00" }] });

    const categories = await api(app).get("/categories");
    const service = await api(app)
      .post("/providers/me/services")
      .set(...auth(providerToken))
      .send({ serviceTypeId: categories.body.data[0].serviceTypes[0].id, title: "Service de tri" });
    const pack = await api(app)
      .post("/providers/me/service-packs")
      .set(...auth(providerToken))
      .send({ providerServiceId: service.body.data.id, title: "Formule de tri", price: 10000, durationMinutes: 60 });
    const packId = pack.body.data.id;

    const upload = await api(app)
      .post("/files/upload")
      .set(...auth(providerToken))
      .attach("file", Buffer.from("PIECE"), "id.txt");
    await api(app)
      .post("/providers/me/documents")
      .set(...auth(providerToken))
      .send({ type: "id_card", fileId: upload.body.data.id });
    await api(app).post("/providers/me/submit").set(...auth(providerToken));

    // Approbation directe en base : ce fichier teste le tri, pas le circuit
    // d'approbation (déjà couvert par mission-flow.integration.spec.ts).
    await prisma.providerProfile.update({ where: { id: providerId }, data: { validationStatus: "approved" } });
    await api(app).patch("/providers/me").set(...auth(providerToken)).send({ availabilityStatus: "available" });

    // Deux missions à des horaires bien distincts, le même mercredi.
    const early = await api(app)
      .post("/missions")
      .set(...auth(clientToken))
      .send({ providerId, packId, scheduledAt: nextWeekdayAt(3, 9).toISOString(), addressId });
    missionEarlyId = early.body.data.id;

    const late = await api(app)
      .post("/missions")
      .set(...auth(clientToken))
      .send({ providerId, packId, scheduledAt: nextWeekdayAt(3, 14).toISOString(), addressId });
    missionLateId = late.body.data.id;
  });

  afterAll(async () => {
    await prisma.$disconnect();
    await app.close();
  });

  describe("GET /me/missions (client)", () => {
    it("trie par défaut sur scheduledAt décroissant (la plus tardive d'abord)", async () => {
      const response = await api(app).get("/me/missions").set(...auth(clientToken));
      const ids = response.body.data.map((m: { id: string }) => m.id);

      expect(response.status).toBe(200);
      expect(ids.indexOf(missionLateId)).toBeLessThan(ids.indexOf(missionEarlyId));
    });

    it("un tri valide change réellement l'ordre (scheduledAt croissant)", async () => {
      const response = await api(app).get("/me/missions?sort=scheduledAt:asc").set(...auth(clientToken));
      const ids = response.body.data.map((m: { id: string }) => m.id);

      expect(response.status).toBe(200);
      expect(ids.indexOf(missionEarlyId)).toBeLessThan(ids.indexOf(missionLateId));
    });

    it("un tri invalide retombe proprement sur le défaut (pas d'erreur)", async () => {
      const response = await api(app).get("/me/missions?sort=passwordHash").set(...auth(clientToken));
      const ids = response.body.data.map((m: { id: string }) => m.id);

      expect(response.status).toBe(200);
      expect(ids.indexOf(missionLateId)).toBeLessThan(ids.indexOf(missionEarlyId));
    });
  });

  describe("GET /providers/me/missions (prestataire)", () => {
    it("trie par défaut sur scheduledAt croissant (la plus proche d'abord)", async () => {
      const response = await api(app).get("/providers/me/missions").set(...auth(providerToken));
      const ids = response.body.data.map((m: { id: string }) => m.id);

      expect(response.status).toBe(200);
      expect(ids.indexOf(missionEarlyId)).toBeLessThan(ids.indexOf(missionLateId));
    });

    it("un tri valide change réellement l'ordre (scheduledAt décroissant)", async () => {
      const response = await api(app).get("/providers/me/missions?sort=scheduledAt:desc").set(...auth(providerToken));
      const ids = response.body.data.map((m: { id: string }) => m.id);

      expect(response.status).toBe(200);
      expect(ids.indexOf(missionLateId)).toBeLessThan(ids.indexOf(missionEarlyId));
    });

    it("un tri invalide retombe proprement sur le défaut (pas d'erreur)", async () => {
      const response = await api(app)
        .get("/providers/me/missions?sort=nimportequoi")
        .set(...auth(providerToken));
      const ids = response.body.data.map((m: { id: string }) => m.id);

      expect(response.status).toBe(200);
      expect(ids.indexOf(missionEarlyId)).toBeLessThan(ids.indexOf(missionLateId));
    });
  });

  describe("GET /me/reviews", () => {
    let reviewLowId: string;
    let reviewHighId: string;

    beforeAll(async () => {
      // Fait avancer les deux missions jusqu'à `completed`, sans retester le
      // cycle de vie lui-même (déjà couvert ailleurs).
      for (const missionId of [missionEarlyId, missionLateId]) {
        await prisma.mission.update({
          where: { id: missionId },
          data: { scheduledAt: new Date(Date.now() + 5 * 60_000) }
        });
        await api(app).post(`/missions/${missionId}/accept`).set(...auth(providerToken));
        await api(app).post(`/missions/${missionId}/start`).set(...auth(providerToken));
        await api(app).post(`/missions/${missionId}/complete`).set(...auth(providerToken));
      }

      // Avis avec des notes opposées, pour distinguer un tri par date d'un tri
      // par note.
      const low = await api(app)
        .post(`/missions/${missionEarlyId}/review`)
        .set(...auth(clientToken))
        .send({ rating: 1, comment: "Décevant" });
      reviewLowId = low.body.data.id;

      const high = await api(app)
        .post(`/missions/${missionLateId}/review`)
        .set(...auth(clientToken))
        .send({ rating: 5, comment: "Excellent" });
      reviewHighId = high.body.data.id;
    });

    it("trie par défaut sur createdAt décroissant (le plus récent d'abord)", async () => {
      const response = await api(app).get("/me/reviews").set(...auth(clientToken));
      const ids = response.body.data.map((r: { id: string }) => r.id);

      expect(response.status).toBe(200);
      expect(ids.indexOf(reviewHighId)).toBeLessThan(ids.indexOf(reviewLowId));
    });

    it("un tri valide change réellement l'ordre (rating croissant)", async () => {
      const response = await api(app).get("/me/reviews?sort=rating:asc").set(...auth(clientToken));
      const ids = response.body.data.map((r: { id: string }) => r.id);

      expect(response.status).toBe(200);
      expect(ids.indexOf(reviewLowId)).toBeLessThan(ids.indexOf(reviewHighId));
    });

    it("un tri invalide retombe proprement sur le défaut (pas d'erreur)", async () => {
      const response = await api(app).get("/me/reviews?sort=commentaire").set(...auth(clientToken));
      const ids = response.body.data.map((r: { id: string }) => r.id);

      expect(response.status).toBe(200);
      expect(ids.indexOf(reviewHighId)).toBeLessThan(ids.indexOf(reviewLowId));
    });
  });

  describe("GET /me/threads", () => {
    let threadEarlyMissionId: string;
    let threadLateMissionId: string;

    beforeAll(async () => {
      const threads = await api(app).get("/me/threads").set(...auth(clientToken));
      const byMission = new Map(threads.body.data.map((t: { missionId: string; id: string }) => [t.missionId, t.id]));
      threadEarlyMissionId = missionEarlyId;
      threadLateMissionId = missionLateId;

      // Le fil de la mission « early » est créé EN PREMIER (mission créée en
      // premier) : par date de création, il vient avant celui de « late ».
      // On y écrit un message MAINTENANT pour que son dernier message devienne
      // le plus récent des deux — l'inverse de l'ordre par date de création.
      const earlyThreadId = byMission.get(missionEarlyId) as string;
      await api(app)
        .post(`/messages/threads/${earlyThreadId}/messages`)
        .set(...auth(clientToken))
        .send({ message: "Message tardif dans le fil le plus ancien" });
    });

    it("trie par défaut sur la date de création du fil (le plus récent créé d'abord)", async () => {
      const response = await api(app).get("/me/threads").set(...auth(clientToken));
      const missionIds = response.body.data.map((t: { missionId: string }) => t.missionId);

      expect(response.status).toBe(200);
      // Le fil de « late » a été CRÉÉ après celui de « early ».
      expect(missionIds.indexOf(threadLateMissionId)).toBeLessThan(missionIds.indexOf(threadEarlyMissionId));
    });

    it("un tri par dernier message change réellement l'ordre (lastMessageAt)", async () => {
      const response = await api(app).get("/me/threads?sort=lastMessageAt").set(...auth(clientToken));
      const missionIds = response.body.data.map((t: { missionId: string }) => t.missionId);

      expect(response.status).toBe(200);
      // Le fil de « early » a reçu le message le plus RÉCENT : il doit
      // remonter en tête, alors qu'il est le plus ANCIEN par date de création.
      expect(missionIds.indexOf(threadEarlyMissionId)).toBeLessThan(missionIds.indexOf(threadLateMissionId));
    });

    it("un tri invalide retombe proprement sur le défaut (pas d'erreur)", async () => {
      const response = await api(app).get("/me/threads?sort=inconnu").set(...auth(clientToken));
      const missionIds = response.body.data.map((t: { missionId: string }) => t.missionId);

      expect(response.status).toBe(200);
      expect(missionIds.indexOf(threadLateMissionId)).toBeLessThan(missionIds.indexOf(threadEarlyMissionId));
    });
  });

  describe("GET /me/notifications", () => {
    it("trie par défaut sur createdAt décroissant (la plus récente d'abord)", async () => {
      const response = await api(app).get("/me/notifications").set(...auth(clientToken));

      expect(response.status).toBe(200);
      expect(response.body.data.length).toBeGreaterThan(1);
      const dates = response.body.data.map((n: { createdAt: string }) => new Date(n.createdAt).getTime());
      expect(dates).toEqual([...dates].sort((a: number, b: number) => b - a));
    });

    it("un tri valide change réellement l'ordre (createdAt croissant)", async () => {
      // `sort=createdAt:asc` plutôt que `sort=+createdAt` : dans une URL, un
      // `+` non encodé est interprété comme une espace par le transport HTTP,
      // pas comme un préfixe — la syntaxe `champ:asc` est sans ambiguïté.
      const response = await api(app).get("/me/notifications?sort=createdAt:asc").set(...auth(clientToken));

      expect(response.status).toBe(200);
      const dates = response.body.data.map((n: { createdAt: string }) => new Date(n.createdAt).getTime());
      expect(dates).toEqual([...dates].sort((a: number, b: number) => a - b));
    });

    it("un tri invalide retombe proprement sur le défaut (pas d'erreur)", async () => {
      const response = await api(app).get("/me/notifications?sort=body").set(...auth(clientToken));

      expect(response.status).toBe(200);
      const dates = response.body.data.map((n: { createdAt: string }) => new Date(n.createdAt).getTime());
      expect(dates).toEqual([...dates].sort((a: number, b: number) => b - a));
    });
  });
});
