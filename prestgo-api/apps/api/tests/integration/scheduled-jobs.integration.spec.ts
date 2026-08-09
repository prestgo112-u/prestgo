import type { INestApplication } from "@nestjs/common";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { PrismaClient } from "@prisma/client";
import { api, auth, createTestApp, login, SEED_USERS, uniqueEmail } from "../helpers/test-app.js";
import { ScheduledJobsService } from "../../src/modules/jobs/scheduled-jobs.service.js";

const PASSWORD = "jobsdetest12";
const prisma = new PrismaClient();

function nextWeekdayAt(weekday: number, hour: number, weeksAhead = 1): Date {
  const date = new Date();
  date.setUTCHours(hour, 0, 0, 0);
  const delta = (weekday - date.getUTCDay() + 7) % 7 || 7;
  date.setUTCDate(date.getUTCDate() + delta + 7 * (weeksAhead - 1));
  return date;
}

/**
 * Jobs planifiés (§14, Lot 7.1).
 *
 * Ils sont déclenchés explicitement plutôt qu'attendus : un test qui attend une
 * minuterie de quinze minutes n'est pas un test. Ce qui est vérifié ici, c'est
 * l'EFFET du job — pas sa planification, qui relève de la file BullMQ.
 */
describe("jobs planifiés", () => {
  let app: INestApplication;
  let jobs: ScheduledJobsService;
  let adminToken: string;
  let clientToken: string;
  let providerToken: string;
  let providerId: string;
  let packId: string;
  let addressId: string;

  beforeAll(async () => {
    app = await createTestApp();
    jobs = app.get(ScheduledJobsService);
    adminToken = await login(app, SEED_USERS.admin);

    const clientEmail = uniqueEmail("jobs-client");
    await api(app).post("/auth/register").send({ email: clientEmail, password: PASSWORD });
    const clientOtp = await api(app)
      .post("/auth/otp/send")
      .send({ target: clientEmail, purpose: "email_verification" });
    await api(app)
      .post("/auth/otp/verify")
      .send({ target: clientEmail, code: clientOtp.body.data.devCode, purpose: "email_verification" });
    clientToken = await login(app, { email: clientEmail, password: PASSWORD });

    addressId = (
      await api(app)
        .post("/me/addresses")
        .set(...auth(clientToken))
        .send({ label: "Maison", city: "Abidjan", latitude: 5.35, longitude: -3.98 })
    ).body.data.id;

    const providerEmail = uniqueEmail("jobs-provider");
    await api(app).post("/auth/register").send({ email: providerEmail, password: PASSWORD });
    const providerOtp = await api(app)
      .post("/auth/otp/send")
      .send({ target: providerEmail, purpose: "email_verification" });
    await api(app)
      .post("/auth/otp/verify")
      .send({ target: providerEmail, code: providerOtp.body.data.devCode, purpose: "email_verification" });
    providerToken = await login(app, { email: providerEmail, password: PASSWORD });

    providerId = (
      await api(app)
        .post("/providers/me")
        .set(...auth(providerToken))
        .send({ publicName: `Jobs ${Date.now()}`, bio: "Prestataire de test." })
    ).body.data.id;

    const zones = await api(app).get("/zones");
    const zoneId = zones.body.data.find((zone: { name: string }) => zone.name === "Cocody")?.id ?? zones.body.data[0].id;
    await api(app).put("/providers/me/zones").set(...auth(providerToken)).send({ zoneIds: [zoneId] });
    await api(app)
      .put("/providers/me/availabilities")
      .set(...auth(providerToken))
      .send({ slots: [{ weekday: 3, startTime: "08:00", endTime: "18:00" }] });

    const categories = await api(app).get("/categories");
    const service = await api(app)
      .post("/providers/me/services")
      .set(...auth(providerToken))
      .send({ serviceTypeId: categories.body.data[0].serviceTypes[0].id, title: "Service de test" });
    packId = (
      await api(app)
        .post("/providers/me/service-packs")
        .set(...auth(providerToken))
        .send({ providerServiceId: service.body.data.id, title: "Formule", price: 10000, durationMinutes: 60 })
    ).body.data.id;

    const upload = await api(app)
      .post("/files/upload")
      .set(...auth(providerToken))
      .attach("file", Buffer.from("PIECE"), "id.txt");
    await api(app)
      .post("/providers/me/documents")
      .set(...auth(providerToken))
      .send({ type: "id_card", fileId: upload.body.data.id });

    await api(app).post("/providers/me/submit").set(...auth(providerToken));
    await api(app)
      .patch(`/admin/providers/${providerId}/status`)
      .set("Authorization", `Bearer ${adminToken}`)
      .send({ status: "approved" });
    await api(app)
      .patch("/providers/me")
      .set(...auth(providerToken))
      .send({ availabilityStatus: "available" });
  });

  afterAll(async () => {
    await prisma.$disconnect();
    await app.close();
  });

  /**
   * Sans ce job, une mission jamais acceptée reste `pending_provider` pour
   * toujours : elle bloque un créneau et pollue les listes des deux parties.
   */
  it("expire une mission restée sans réponse au-delà du délai", async () => {
    const creation = await api(app)
      .post("/missions")
      .set(...auth(clientToken))
      .send({ providerId, packId, scheduledAt: nextWeekdayAt(3, 10, 2).toISOString(), addressId });
    const missionId = creation.body.data.id;
    expect(creation.body.data.status).toBe("pending_provider");

    // On vieillit artificiellement la demande : le réglage est de 24 h.
    await prisma.mission.update({
      where: { id: missionId },
      data: { createdAt: new Date(Date.now() - 48 * 60 * 60_000) }
    });

    const result = await jobs.run("expireMissions");
    expect(result.expired).toBeGreaterThanOrEqual(1);

    const apres = await api(app).get(`/missions/${missionId}`).set(...auth(clientToken));
    expect(apres.body.data.status).toBe("cancelled");
    expect(apres.body.data.cancellation.reason).toMatch(/expirée/);

    // Les deux parties sont prévenues.
    const notifications = await api(app).get("/me/notifications").set(...auth(clientToken));
    expect(notifications.body.data.some((item: { type: string }) => item.type === "mission.expired")).toBe(true);
  });

  it("laisse tranquille une demande encore dans les temps", async () => {
    const creation = await api(app)
      .post("/missions")
      .set(...auth(clientToken))
      .send({ providerId, packId, scheduledAt: nextWeekdayAt(3, 12, 3).toISOString(), addressId });

    await jobs.run("expireMissions");

    const apres = await api(app).get(`/missions/${creation.body.data.id}`).set(...auth(clientToken));
    expect(apres.body.data.status).toBe("pending_provider");
  });

  it("clôture automatiquement une mission terminée et sans litige", async () => {
    const creation = await api(app)
      .post("/missions")
      .set(...auth(clientToken))
      .send({ providerId, packId, scheduledAt: nextWeekdayAt(3, 14, 4).toISOString(), addressId });
    const missionId = creation.body.data.id;

    await api(app).post(`/missions/${missionId}/accept`).set(...auth(providerToken));
    await prisma.mission.update({
      where: { id: missionId },
      data: { scheduledAt: new Date(Date.now() + 10 * 60_000) }
    });
    await api(app).post(`/missions/${missionId}/start`).set(...auth(providerToken));
    await api(app).post(`/missions/${missionId}/complete`).set(...auth(providerToken));

    // On vieillit la fin de mission : le réglage est de 7 jours.
    await prisma.mission.update({
      where: { id: missionId },
      data: { updatedAt: new Date(Date.now() - 10 * 24 * 60 * 60_000) }
    });

    const result = await jobs.run("autoCloseMissions");
    expect(result.closed).toBeGreaterThanOrEqual(1);

    const apres = await api(app).get(`/missions/${missionId}`).set(...auth(clientToken));
    expect(apres.body.data.status).toBe("closed");
  });

  it("trace chaque exécution de job avec l'acteur système", async () => {
    await jobs.run("cleanupTokens");

    const audit = await api(app)
      .get("/admin/audit-logs?entity=ScheduledJob")
      .set("Authorization", `Bearer ${adminToken}`);

    expect(audit.status).toBe(200);
    expect(audit.body.data.length).toBeGreaterThan(0);
    expect(audit.body.data[0].action).toMatch(/^system\.jobs\./);
    // « system » n'est pas un utilisateur : la colonne actorId reste vide.
    expect(audit.body.data[0].actorId).toBeUndefined();
  });

  it("expose le déclenchement manuel aux seuls administrateurs", async () => {
    const sansDroit = await api(app).post("/admin/jobs/cleanupTokens/run").set(...auth(clientToken));
    expect(sansDroit.status).toBe(403);

    const inconnu = await api(app)
      .post("/admin/jobs/nimportequoi/run")
      .set("Authorization", `Bearer ${adminToken}`);
    expect(inconnu.status).toBe(400);

    const valide = await api(app)
      .post("/admin/jobs/cleanupTokens/run")
      .set("Authorization", `Bearer ${adminToken}`);
    expect(valide.status).toBe(200);
    expect(valide.body.data.job).toBe("cleanupTokens");
  });
});
