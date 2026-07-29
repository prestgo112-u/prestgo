import type { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@prisma/client";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { api, auth, createTestApp, login, SEED_USERS, uniqueEmail } from "../helpers/test-app.js";

const PASSWORD = "parcours1234";
// Accès direct à la base pour vérifier ce qui n'a pas de route : les lignes de
// notification par canal, notamment.
const prisma = new PrismaClient();

/**
 * Prochaine occurrence d'un jour de la semaine, à une heure donnée (UTC).
 *
 * Les créneaux du prestataire sont hebdomadaires : un test qui réserverait une
 * date fixe passerait ou échouerait selon le jour où on l'exécute.
 */
function nextWeekdayAt(weekday: number, hour: number, weeksAhead = 1): Date {
  const date = new Date();
  date.setUTCHours(hour, 0, 0, 0);
  const delta = (weekday - date.getUTCDay() + 7) % 7 || 7;
  date.setUTCDate(date.getUTCDate() + delta + 7 * (weeksAhead - 1));
  return date;
}

/**
 * Parcours complet : recherche → réservation → exécution → avis.
 *
 * C'est le jalon 6.4 du cahier de finalisation — « la boucle de valeur
 * complète ». Ces tests couvrent les critères d'acceptation du §17 : filtres
 * de recherche non contournables, transitions refusées avec le même message
 * que côté admin, idempotence, avis unique, recalcul de la note.
 */
describe("boucle de valeur mission", () => {
  let app: INestApplication;
  let adminToken: string;
  let clientToken: string;
  let providerToken: string;

  let providerId: string;
  let packId: string;
  let optionId: string;
  let addressId: string;
  let zoneId: string;

  const scheduledAt = nextWeekdayAt(1, 9); // lundi 09:00 UTC

  beforeAll(async () => {
    app = await createTestApp();
    adminToken = await login(app, SEED_USERS.admin);

    // --- Un client tout neuf, activé ---
    const clientEmail = uniqueEmail("flow-client");
    await api(app).post("/auth/register").send({ email: clientEmail, password: PASSWORD, firstName: "Awa" });
    const clientOtp = await api(app)
      .post("/auth/otp/send")
      .send({ target: clientEmail, purpose: "email_verification" });
    await api(app)
      .post("/auth/otp/verify")
      .send({ target: clientEmail, code: clientOtp.body.data.devCode, purpose: "email_verification" });
    clientToken = await login(app, { email: clientEmail, password: PASSWORD });

    const address = await api(app)
      .post("/me/addresses")
      .set(...auth(clientToken))
      .send({ label: "Maison", city: "Abidjan", commune: "Cocody", latitude: 5.35, longitude: -3.98 });
    addressId = address.body.data.id;

    // --- Un prestataire qui construit SEUL son dossier (§5, §6) ---
    const providerEmail = uniqueEmail("flow-provider");
    await api(app).post("/auth/register").send({ email: providerEmail, password: PASSWORD, firstName: "Kofi" });
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
      .send({ publicName: `Plomberie ${Date.now()}`, bio: "Interventions rapides à Cocody.", experienceYears: 6 });
    providerId = profile.body.data.id;

    // Zone existante du jeu de démonstration (Cocody, rayon 5 km).
    const zones = await api(app).get("/zones");
    zoneId = zones.body.data.find((zone: { name: string }) => zone.name === "Cocody")?.id ?? zones.body.data[0].id;
    await api(app)
      .put("/providers/me/zones")
      .set(...auth(providerToken))
      .send({ zoneIds: [zoneId] });

    // Agenda : lundi 08:00–18:00, assez large pour contenir la prestation.
    await api(app)
      .put("/providers/me/availabilities")
      .set(...auth(providerToken))
      .send({ slots: [{ weekday: 1, startTime: "08:00", endTime: "18:00" }] });

    // Service + formule + option.
    const categories = await api(app).get("/categories");
    const serviceTypeId = categories.body.data[0].serviceTypes[0].id;
    const service = await api(app)
      .post("/providers/me/services")
      .set(...auth(providerToken))
      .send({ serviceTypeId, title: "Dépannage plomberie", description: "Diagnostic et réparation." });

    const pack = await api(app)
      .post("/providers/me/service-packs")
      .set(...auth(providerToken))
      .send({
        providerServiceId: service.body.data.id,
        title: "Réparation de fuite",
        price: 15000,
        durationMinutes: 60
      });
    packId = pack.body.data.id;

    const option = await api(app)
      .post(`/providers/me/service-packs/${packId}/options`)
      .set(...auth(providerToken))
      .send({ title: "Déplacement hors zone", price: 3000, durationMinutes: 15 });
    optionId = option.body.data.id;

    // Justificatif déposé PAR LE PRESTATAIRE (§6 : correction de l'inversion).
    const upload = await api(app)
      .post("/files/upload")
      .set(...auth(providerToken))
      .attach("file", Buffer.from("PIECE IDENTITE DE TEST"), "id.txt");
    await api(app)
      .post("/providers/me/documents")
      .set(...auth(providerToken))
      .send({ type: "id_card", fileId: upload.body.data.id });

    // Soumission puis validation par l'agent.
    await api(app).post("/providers/me/submit").set(...auth(providerToken));
    await api(app)
      .patch(`/admin/providers/${providerId}/status`)
      .set("Authorization", `Bearer ${adminToken}`)
      .send({ status: "approved" });

    // Un prestataire approuvé mais « unavailable » n'apparaît pas en recherche
    // (§7, filtre appliqué d'office) : il se déclare disponible lui-même.
    await api(app)
      .patch("/providers/me")
      .set(...auth(providerToken))
      .send({ availabilityStatus: "available" });
  });

  afterAll(async () => {
    await prisma.$disconnect();
    await app.close();
  });

  describe("dossier prestataire en libre-service (§5)", () => {
    it("expose une checklist complète et un dossier validé", async () => {
      const response = await api(app).get("/providers/me").set(...auth(providerToken));

      expect(response.status).toBe(200);
      expect(response.body.data.checklist).toEqual({
        profile: true,
        services: true,
        zones: true,
        availabilities: true,
        documents: true
      });
      expect(response.body.data.validationStatus).toBe("approved");
    });

    it("refuse une soumission depuis un dossier déjà approuvé", async () => {
      const response = await api(app).post("/providers/me/submit").set(...auth(providerToken));
      expect(response.status).toBe(400);
    });

    it("refuse la soumission d'un dossier vide, avec le détail de ce qui manque", async () => {
      const email = uniqueEmail("flow-incomplet");
      await api(app).post("/auth/register").send({ email, password: PASSWORD });
      const otp = await api(app).post("/auth/otp/send").send({ target: email, purpose: "email_verification" });
      await api(app)
        .post("/auth/otp/verify")
        .send({ target: email, code: otp.body.data.devCode, purpose: "email_verification" });
      const token = await login(app, { email, password: PASSWORD });

      await api(app).post("/providers/me").set(...auth(token)).send({ publicName: "Dossier vide" });
      const apercu = await api(app).get("/providers/me").set(...auth(token));
      expect(apercu.body.data.canSubmit).toBe(false);

      const soumission = await api(app).post("/providers/me/submit").set(...auth(token));
      expect(soumission.status).toBe(400);
      expect(soumission.body.errors.map((error: { field: string }) => error.field)).toEqual(
        expect.arrayContaining(["services", "zones", "availabilities", "documents"])
      );
    });
  });

  describe("recherche de prestataires (§7)", () => {
    it("trouve le prestataire par position et créneau", async () => {
      const date = scheduledAt.toISOString().slice(0, 10);
      const response = await api(app).get(
        `/providers/search?latitude=5.35&longitude=-3.98&radiusKm=10&date=${date}&startTime=09:00`
      );

      expect(response.status).toBe(200);
      const trouve = response.body.data.find((item: { id: string }) => item.id === providerId);
      expect(trouve).toBeDefined();
      expect(trouve.startingPrice).toBe(15000);
      expect(typeof trouve.distanceKm).toBe("number");
    });

    it("est accessible sans compte et n'expose aucune donnée interne", async () => {
      const response = await api(app).get("/providers/search");

      expect(response.status).toBe(200);
      const serialise = JSON.stringify(response.body);
      expect(serialise).not.toContain("email");
      expect(serialise).not.toContain("phone");
      expect(serialise).not.toContain("validationStatus");
    });

    it("écarte le prestataire quand aucune zone ne couvre la position", async () => {
      // Yamoussoukro, à plus de 200 km de la zone déclarée.
      const response = await api(app).get("/providers/search?latitude=6.82&longitude=-5.28&radiusKm=10");

      expect(response.status).toBe(200);
      expect(response.body.data.find((item: { id: string }) => item.id === providerId)).toBeUndefined();
    });

    it("refuse un tri inconnu au lieu de l'ignorer silencieusement", async () => {
      const response = await api(app).get("/providers/search?sort=nimportequoi");
      expect(response.status).toBe(400);
    });

    it("exige la géoposition pour un tri par distance", async () => {
      const response = await api(app).get("/providers/search?sort=distance");
      expect(response.status).toBe(400);
    });

    it("agrège la fiche publique en un seul appel", async () => {
      const response = await api(app).get(`/providers/${providerId}/public`);

      expect(response.status).toBe(200);
      expect(response.body.data).toMatchObject({ id: providerId });
      expect(response.body.data.services.length).toBeGreaterThan(0);
      expect(response.body.data.availability.length).toBeGreaterThan(0);
      expect(response.body.data).toHaveProperty("ratingDistribution");
      expect(response.body.data).toHaveProperty("latestReviews");
      expect(JSON.stringify(response.body)).not.toContain("id_card");
    });
  });

  describe("favoris (§4)", () => {
    it("ajoute, liste et retire un favori de façon idempotente", async () => {
      const premier = await api(app).post(`/me/favorites/${providerId}`).set(...auth(clientToken));
      const second = await api(app).post(`/me/favorites/${providerId}`).set(...auth(clientToken));
      expect(premier.status).toBe(200);
      expect(second.status).toBe(200);

      const liste = await api(app).get("/me/favorites").set(...auth(clientToken));
      expect(liste.body.data).toHaveLength(1);
      expect(liste.body.data[0].id).toBe(providerId);

      await api(app).delete(`/me/favorites/${providerId}`).set(...auth(clientToken));
      const apres = await api(app).get("/me/favorites").set(...auth(clientToken));
      expect(apres.body.data).toHaveLength(0);
    });
  });

  describe("réservation et cycle de vie (§8, §9)", () => {
    let missionId: string;

    it("crée une mission au statut pending_provider avec un montant figé", async () => {
      const response = await api(app)
        .post("/missions")
        .set(...auth(clientToken))
        .send({
          providerId,
          packId,
          optionIds: optionId ? [optionId] : [],
          scheduledAt: scheduledAt.toISOString(),
          addressId,
          instructions: "Portail vert, sonner deux fois"
        });

      expect(response.status).toBe(201);
      expect(response.body.data.status).toBe("pending_provider");
      // Le montant est la somme figée de la formule et des options retenues.
      expect(response.body.data.quotedAmount).toBe(optionId ? 18000 : 15000);
      // Le fil de discussion existe dès la demande : le prestataire doit
      // pouvoir poser une question avant d'accepter.
      expect(response.body.data.thread).not.toBeNull();

      missionId = response.body.data.id;
    });

    it("refuse une réservation trop proche dans le temps", async () => {
      const response = await api(app)
        .post("/missions")
        .set(...auth(clientToken))
        .send({
          providerId,
          packId,
          scheduledAt: new Date(Date.now() + 5 * 60_000).toISOString(),
          addressId
        });

      expect(response.status).toBe(400);
      expect(response.body.message).toMatch(/à l'avance/);
    });

    it("refuse une adresse qui n'appartient pas au client", async () => {
      const autreEmail = uniqueEmail("flow-autre-client");
      await api(app).post("/auth/register").send({ email: autreEmail, password: PASSWORD });
      const otp = await api(app).post("/auth/otp/send").send({ target: autreEmail, purpose: "email_verification" });
      await api(app)
        .post("/auth/otp/verify")
        .send({ target: autreEmail, code: otp.body.data.devCode, purpose: "email_verification" });
      const autreToken = await login(app, { email: autreEmail, password: PASSWORD });

      const response = await api(app)
        .post("/missions")
        .set(...auth(autreToken))
        .send({
          providerId,
          packId,
          scheduledAt: nextWeekdayAt(1, 14, 2).toISOString(),
          addressId // adresse d'un AUTRE compte
        });

      expect(response.status).toBe(404);
    });

    it("refuse un créneau hors de l'agenda du prestataire", async () => {
      const response = await api(app)
        .post("/missions")
        .set(...auth(clientToken))
        .send({
          providerId,
          packId,
          // Mardi : le prestataire ne travaille que le lundi.
          scheduledAt: nextWeekdayAt(2, 10, 2).toISOString(),
          addressId
        });

      expect(response.status).toBe(400);
      expect(response.body.message).toMatch(/disponible/);
    });

    /** §14.6 : la même clé ne crée jamais deux missions. */
    it("est idempotent avec Idempotency-Key", async () => {
      const key = `test-${Date.now()}`;
      const payload = {
        providerId,
        packId,
        scheduledAt: nextWeekdayAt(1, 14, 3).toISOString(),
        addressId
      };

      const premier = await api(app)
        .post("/missions")
        .set(...auth(clientToken))
        .set("Idempotency-Key", key)
        .send(payload);
      const second = await api(app)
        .post("/missions")
        .set(...auth(clientToken))
        .set("Idempotency-Key", key)
        .send(payload);

      expect(premier.status).toBe(201);
      expect(second.status).toBe(201);
      expect(second.body.data.id).toBe(premier.body.data.id);
    });

    it("liste la mission côté client et côté prestataire", async () => {
      const cote_client = await api(app).get("/me/missions").set(...auth(clientToken));
      const cote_prestataire = await api(app).get("/providers/me/missions").set(...auth(providerToken));

      expect(cote_client.body.data.some((mission: { id: string }) => mission.id === missionId)).toBe(true);
      expect(cote_prestataire.body.data.some((mission: { id: string }) => mission.id === missionId)).toBe(true);
    });

    it("interdit à un tiers de lire la mission (403, pas un 404 menteur)", async () => {
      const intrusEmail = uniqueEmail("flow-intrus");
      await api(app).post("/auth/register").send({ email: intrusEmail, password: PASSWORD });
      const otp = await api(app).post("/auth/otp/send").send({ target: intrusEmail, purpose: "email_verification" });
      await api(app)
        .post("/auth/otp/verify")
        .send({ target: intrusEmail, code: otp.body.data.devCode, purpose: "email_verification" });
      const intrusToken = await login(app, { email: intrusEmail, password: PASSWORD });

      const response = await api(app).get(`/missions/${missionId}`).set(...auth(intrusToken));
      expect(response.status).toBe(403);
    });

    it("refuse au client de démarrer une mission à la place du prestataire", async () => {
      const response = await api(app).post(`/missions/${missionId}/start`).set(...auth(clientToken));
      expect(response.status).toBe(403);
    });

    it("refuse une transition interdite : démarrer avant d'accepter", async () => {
      const response = await api(app).post(`/missions/${missionId}/start`).set(...auth(providerToken));

      expect(response.status).toBe(400);
      expect(response.body.message).toMatch(/pending_provider/);
    });

    it("accepte, démarre puis termine la mission", async () => {
      const acceptation = await api(app).post(`/missions/${missionId}/accept`).set(...auth(providerToken));
      expect(acceptation.status).toBe(200);
      expect(acceptation.body.data.status).toBe("confirmed");

      const demarrage = await api(app).post(`/missions/${missionId}/start`).set(...auth(providerToken));
      // La fenêtre de démarrage est de 120 minutes : une mission prévue la
      // semaine prochaine ne peut pas encore démarrer.
      expect(demarrage.status).toBe(400);
      expect(demarrage.body.message).toMatch(/minutes avant/);

      // On rapproche la date en la reprogrammant côté admin (outil de support).
      await api(app)
        .post(`/admin/missions/${missionId}/reschedule`)
        .set("Authorization", `Bearer ${adminToken}`)
        .send({ scheduledAt: new Date(Date.now() + 30 * 60_000).toISOString(), reason: "Test de démarrage" });

      const demarrage2 = await api(app).post(`/missions/${missionId}/start`).set(...auth(providerToken));
      expect(demarrage2.status).toBe(200);
      expect(demarrage2.body.data.status).toBe("in_progress");

      const fin = await api(app).post(`/missions/${missionId}/complete`).set(...auth(providerToken));
      expect(fin.status).toBe(200);
      expect(fin.body.data.status).toBe("completed");
    });

    it("écrit l'historique avec l'acteur réel à chaque transition", async () => {
      const response = await api(app).get(`/missions/${missionId}/history`).set(...auth(clientToken));

      expect(response.status).toBe(200);
      const statuts = response.body.data.statusHistory.map((entry: { newStatus: string }) => entry.newStatus);
      expect(statuts).toEqual(
        expect.arrayContaining(["pending_provider", "confirmed", "in_progress", "completed"])
      );
    });

    describe("avis (§11)", () => {
      it("accepte un avis unique et recalcule la note du prestataire", async () => {
        const avant = await api(app).get(`/providers/${providerId}/public`);
        expect(avant.body.data.reviewsCount).toBe(0);

        const depot = await api(app)
          .post(`/missions/${missionId}/review`)
          .set(...auth(clientToken))
          .send({ rating: 5, comment: "Travail impeccable et ponctuel." });

        expect(depot.status).toBe(201);
        expect(depot.body.data.status).toBe("published");

        const apres = await api(app).get(`/providers/${providerId}/public`);
        expect(apres.body.data.score).toBe(5);
        expect(apres.body.data.reviewsCount).toBe(1);
        expect(apres.body.data.latestReviews).toHaveLength(1);
      });

      it("refuse un second avis sur la même mission", async () => {
        const response = await api(app)
          .post(`/missions/${missionId}/review`)
          .set(...auth(clientToken))
          .send({ rating: 1, comment: "Je change d'avis." });

        expect(response.status).toBe(409);
      });

      it("liste mes avis déposés", async () => {
        const response = await api(app).get("/me/reviews").set(...auth(clientToken));

        expect(response.status).toBe(200);
        expect(response.body.data).toHaveLength(1);
        expect(response.body.data[0].mission.id).toBe(missionId);
      });

      /**
       * Un avis signalé reste VISIBLE tant qu'un modérateur n'a pas tranché :
       * sinon signaler suffirait à faire disparaître une critique légitime.
       */
      it("signale un avis sans le masquer", async () => {
        const mesAvis = await api(app).get("/me/reviews").set(...auth(clientToken));
        const reviewId = mesAvis.body.data[0].id;

        const signalement = await api(app)
          .post(`/reviews/${reviewId}/report`)
          .set(...auth(providerToken))
          .send({ reason: "Commentaire jugé injuste" });
        expect(signalement.status).toBe(200);

        const doublon = await api(app)
          .post(`/reviews/${reviewId}/report`)
          .set(...auth(providerToken))
          .send({ reason: "Encore" });
        expect(doublon.status).toBe(409);
      });

      it("recalcule la note à la baisse quand un modérateur masque l'avis", async () => {
        const mesAvis = await api(app).get("/me/reviews").set(...auth(clientToken));
        const reviewId = mesAvis.body.data[0].id;

        await api(app)
          .patch(`/admin/reviews/${reviewId}/status`)
          .set("Authorization", `Bearer ${adminToken}`)
          .send({ status: "hidden", reason: "Contenu inapproprié" });

        const apres = await api(app).get(`/providers/${providerId}/public`);
        expect(apres.body.data.reviewsCount).toBe(0);
        expect(apres.body.data.score).toBe(0);
      });
    });
  });

  describe("annulation (§8)", () => {
    it("exige un motif et marque l'annulation tardive", async () => {
      const creation = await api(app)
        .post("/missions")
        .set(...auth(clientToken))
        .send({
          providerId,
          packId,
          scheduledAt: nextWeekdayAt(1, 16, 4).toISOString(),
          addressId
        });
      const missionId = creation.body.data.id;

      const sansMotif = await api(app).post(`/missions/${missionId}/cancel`).set(...auth(clientToken)).send({});
      expect(sansMotif.status).toBe(400);

      const avecMotif = await api(app)
        .post(`/missions/${missionId}/cancel`)
        .set(...auth(clientToken))
        .send({ reason: "Imprévu de dernière minute" });

      expect(avecMotif.status).toBe(200);
      expect(avecMotif.body.data.status).toBe("cancelled");
      // Mission dans plusieurs semaines : l'annulation n'est PAS tardive.
      expect(avecMotif.body.data.late).toBe(false);
    });
  });

  describe("reprogrammation à deux parties (§10)", () => {
    let missionId: string;

    beforeAll(async () => {
      const creation = await api(app)
        .post("/missions")
        .set(...auth(clientToken))
        .send({
          providerId,
          packId,
          scheduledAt: nextWeekdayAt(1, 11, 5).toISOString(),
          addressId
        });
      missionId = creation.body.data.id;
      await api(app).post(`/missions/${missionId}/accept`).set(...auth(providerToken));
    });

    it("n'applique pas le report tant que l'autre partie n'a pas accepté", async () => {
      const nouvelleDate = nextWeekdayAt(1, 15, 6);

      const demande = await api(app)
        .post(`/missions/${missionId}/reschedule`)
        .set(...auth(clientToken))
        .send({ newDate: nouvelleDate.toISOString(), reason: "Empêchement" });
      expect(demande.status).toBe(200);
      expect(demande.body.data.status).toBe("requested");

      const mission = await api(app).get(`/missions/${missionId}`).set(...auth(clientToken));
      expect(new Date(mission.body.data.scheduledAt).getTime()).not.toBe(nouvelleDate.getTime());
    });

    it("interdit à l'auteur d'accepter sa propre demande", async () => {
      const demandes = await api(app).get(`/missions/${missionId}/reschedules`).set(...auth(clientToken));
      const rid = demandes.body.data[0].id;

      const response = await api(app)
        .post(`/missions/${missionId}/reschedule/${rid}/accept`)
        .set(...auth(clientToken));

      expect(response.status).toBe(403);
    });

    it("refuse une seconde demande tant que la première est en attente", async () => {
      const response = await api(app)
        .post(`/missions/${missionId}/reschedule`)
        .set(...auth(clientToken))
        .send({ newDate: nextWeekdayAt(1, 17, 7).toISOString() });

      expect(response.status).toBe(400);
      expect(response.body.message).toMatch(/déjà en attente/);
    });

    it("applique le report une fois l'autre partie d'accord", async () => {
      const demandes = await api(app).get(`/missions/${missionId}/reschedules`).set(...auth(providerToken));
      const demande = demandes.body.data[0];

      const acceptation = await api(app)
        .post(`/missions/${missionId}/reschedule/${demande.id}/accept`)
        .set(...auth(providerToken));

      expect(acceptation.status).toBe(200);

      const mission = await api(app).get(`/missions/${missionId}`).set(...auth(clientToken));
      expect(new Date(mission.body.data.scheduledAt).getTime()).toBe(
        new Date(demande.newScheduledAt).getTime()
      );
    });
  });

  describe("notifications et conversations (§12)", () => {
    it("dépose des notifications lisibles et comptabilisées", async () => {
      const liste = await api(app).get("/me/notifications").set(...auth(providerToken));
      expect(liste.status).toBe(200);
      expect(liste.body.data.length).toBeGreaterThan(0);
      expect(liste.body.data[0]).toHaveProperty("type");

      const compteur = await api(app).get("/me/notifications/unread-count").set(...auth(providerToken));
      expect(compteur.body.data.unread).toBeGreaterThan(0);

      const marquage = await api(app)
        .patch(`/me/notifications/${liste.body.data[0].id}/read`)
        .set(...auth(providerToken));
      expect(marquage.body.data.updated).toBe(1);

      const toutLu = await api(app).post("/me/notifications/read-all").set(...auth(providerToken));
      expect(toutLu.status).toBe(200);

      const apres = await api(app).get("/me/notifications/unread-count").set(...auth(providerToken));
      expect(apres.body.data.unread).toBe(0);
    });

    it("ne laisse pas marquer lue la notification d'un autre compte", async () => {
      const duPrestataire = await api(app).get("/me/notifications").set(...auth(providerToken));
      const id = duPrestataire.body.data[0].id;

      const response = await api(app).patch(`/me/notifications/${id}/read`).set(...auth(clientToken));
      expect(response.body.data.updated).toBe(0);
    });

    it("enregistre puis désenregistre un jeton d'appareil", async () => {
      const token = `token-de-test-${Date.now()}`;

      const enregistrement = await api(app)
        .post("/me/devices")
        .set(...auth(clientToken))
        .send({ platform: "android", token });
      expect(enregistrement.status).toBe(200);

      // Idempotent : le même jeton ne crée pas de doublon.
      await api(app).post("/me/devices").set(...auth(clientToken)).send({ platform: "android", token });
      const liste = await api(app).get("/me/devices").set(...auth(clientToken));
      expect(liste.body.data).toHaveLength(1);
      // Le jeton lui-même n'est jamais renvoyé : c'est un secret d'envoi.
      expect(JSON.stringify(liste.body)).not.toContain(token);

      const retrait = await api(app).delete(`/me/devices/${token}`).set(...auth(clientToken));
      expect(retrait.body.data.unregistered).toBe(true);
    });

    it("liste mes conversations avec leur dernier message", async () => {
      const response = await api(app).get("/me/threads").set(...auth(clientToken));

      expect(response.status).toBe(200);
      expect(response.body.data.length).toBeGreaterThan(0);
      expect(response.body.data[0]).toHaveProperty("unreadCount");
      expect(response.body.data[0]).toHaveProperty("counterpartName");
    });

    /**
     * Écart n°4 du cahier des charges mobile : la pastille de l'onglet
     * messagerie n'avait pas de compteur global, seulement un `unreadCount` par
     * fil. Sommer la première page donnait un total faux dès qu'un utilisateur
     * dépassait la taille de page.
     */
    it("compte mes messages non lus tous fils confondus, sans compter les miens", async () => {
      const threads = await api(app).get("/me/threads").set(...auth(clientToken));
      const threadId = threads.body.data[0].id;

      // On part d'un état propre des deux côtés.
      await api(app).patch(`/messages/threads/${threadId}/read`).set(...auth(providerToken));
      await api(app).patch(`/messages/threads/${threadId}/read`).set(...auth(clientToken));

      const départ = await api(app).get("/me/threads/unread-count").set(...auth(providerToken));
      expect(départ.status).toBe(200);
      expect(départ.body.data.unread).toBe(0);

      await api(app)
        .post(`/messages/threads/${threadId}/messages`)
        .set(...auth(clientToken))
        .send({ message: "Première question" });
      await api(app)
        .post(`/messages/threads/${threadId}/messages`)
        .set(...auth(clientToken))
        .send({ message: "Deuxième question" });

      // Le destinataire voit les deux messages en attente.
      const cotePrestataire = await api(app).get("/me/threads/unread-count").set(...auth(providerToken));
      expect(cotePrestataire.body.data.unread).toBe(2);

      // L'expéditeur, lui, n'a rien à lire : ses propres messages ne comptent pas.
      const coteClient = await api(app).get("/me/threads/unread-count").set(...auth(clientToken));
      expect(coteClient.body.data.unread).toBe(0);

      // Le compteur global coïncide avec la somme des compteurs par fil.
      const filsPrestataire = await api(app).get("/me/threads").set(...auth(providerToken));
      const sommeParFil = filsPrestataire.body.data.reduce(
        (total: number, fil: { unreadCount: number }) => total + fil.unreadCount,
        0
      );
      expect(cotePrestataire.body.data.unread).toBe(sommeParFil);

      // Après lecture, la pastille retombe à zéro.
      await api(app).patch(`/messages/threads/${threadId}/read`).set(...auth(providerToken));
      const apresLecture = await api(app).get("/me/threads/unread-count").set(...auth(providerToken));
      expect(apresLecture.body.data.unread).toBe(0);
    });

    it("refuse le compteur de messages non lus sans authentification", async () => {
      const response = await api(app).get("/me/threads/unread-count");
      expect(response.status).toBe(401);
    });

    /**
     * Un message envoyé sans notification n'est lu que si le destinataire
     * pense à ouvrir l'application : le §12 prévoit un modèle `chat.message`.
     */
    it("prévient l'interlocuteur d'un nouveau message, et lui seul", async () => {
      const threads = await api(app).get("/me/threads").set(...auth(clientToken));
      const threadId = threads.body.data[0].id;

      await api(app).post("/me/notifications/read-all").set(...auth(providerToken));
      await api(app).post("/me/notifications/read-all").set(...auth(clientToken));

      const envoi = await api(app)
        .post(`/messages/threads/${threadId}/messages`)
        .set(...auth(clientToken))
        .send({ message: "Bonjour, à quelle heure passez-vous ?" });
      expect(envoi.status).toBe(201);

      const cotePrestataire = await api(app)
        .get("/me/notifications?unread=true")
        .set(...auth(providerToken));
      expect(cotePrestataire.body.data.some((item: { type: string }) => item.type === "chat.message")).toBe(true);

      // L'expéditeur n'est jamais notifié de son propre message.
      const coteClient = await api(app).get("/me/notifications?unread=true").set(...auth(clientToken));
      expect(coteClient.body.data.some((item: { type: string }) => item.type === "chat.message")).toBe(false);
    });

    /**
     * §12 : une pièce jointe passe en `restricted`. Une photo de dégât des eaux
     * ne doit pas devenir lisible par simple identifiant.
     */
    it("accepte une pièce jointe et refuse le fichier d'autrui", async () => {
      const threads = await api(app).get("/me/threads").set(...auth(clientToken));
      const threadId = threads.body.data[0].id;

      const monFichier = await api(app)
        .post("/files/upload")
        .set(...auth(clientToken))
        .attach("file", Buffer.from("photo de la fuite"), "fuite.txt");

      const envoi = await api(app)
        .post(`/messages/threads/${threadId}/messages`)
        .set(...auth(clientToken))
        .send({ message: "Voici la photo", fileIds: [monFichier.body.data.id] });

      expect(envoi.status).toBe(201);
      expect(envoi.body.data.files).toHaveLength(1);
      expect(envoi.body.data.files[0].file.originalName).toBe("fuite.txt");

      // Le fichier d'un autre compte est refusé.
      const fichierDuPrestataire = await api(app)
        .post("/files/upload")
        .set(...auth(providerToken))
        .attach("file", Buffer.from("document interne"), "interne.txt");

      const refus = await api(app)
        .post(`/messages/threads/${threadId}/messages`)
        .set(...auth(clientToken))
        .send({ message: "Tentative", fileIds: [fichierDuPrestataire.body.data.id] });

      expect(refus.status).toBe(400);
    });

    /**
     * §12 : « regroupement des push (max 1 par fil et par minute) ».
     *
     * Sans ce garde-fou, une conversation animée déclencherait une vibration
     * par message — l'utilisateur couperait les notifications, et manquerait
     * ensuite celles qui comptent.
     */
    it("ne pousse qu'une fois par fil et par minute", async () => {
      const threads = await api(app).get("/me/threads").set(...auth(clientToken));
      const threadId = threads.body.data[0].id;

      // Le prestataire enregistre un appareil : sans jeton, aucun push n'est
      // même tenté et le regroupement n'aurait rien à démontrer.
      await api(app)
        .post("/me/devices")
        .set(...auth(providerToken))
        .send({ platform: "android", token: `push-groupage-${Date.now()}` });

      for (let index = 0; index < 3; index += 1) {
        await api(app)
          .post(`/messages/threads/${threadId}/messages`)
          .set(...auth(clientToken))
          .send({ message: `Message ${index}` });
      }

      const toutes = await api(app).get("/me/notifications?limit=100").set(...auth(providerToken));
      // Les trois messages produisent trois notifications in-app…
      const inApp = toutes.body.data.filter((item: { type: string }) => item.type === "chat.message");
      expect(inApp.length).toBeGreaterThanOrEqual(3);

      // …mais un seul push, regroupé sur la minute.
      const pushs = await prisma.notification.count({
        where: { type: "chat.message", channel: "push", createdAt: { gte: new Date(Date.now() - 60_000) } }
      });
      expect(pushs).toBe(1);
    });
  });
});
