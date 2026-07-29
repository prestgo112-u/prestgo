import type { INestApplication } from "@nestjs/common";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { api, auth, createTestApp, login, uniqueEmail, uniquePhone } from "../helpers/test-app.js";

/**
 * Espace personnel (§3 et §4).
 *
 * Ce que ces tests protègent avant tout : l'identité vient TOUJOURS du jeton.
 * Aucune de ces routes n'a d'identifiant d'utilisateur dans son adresse, il ne
 * doit donc exister aucun moyen de lire ou modifier le profil d'un autre.
 */
describe("espace personnel /me", () => {
  let app: INestApplication;
  let token: string;
  let email: string;
  const password = "monmotdepasse1";

  beforeAll(async () => {
    app = await createTestApp();

    email = uniqueEmail("me-user");
    const registration = await api(app)
      .post("/auth/register")
      .send({ email, password, firstName: "Awa", lastName: "Koné" });
    expect(registration.status).toBe(201);

    // Activation par OTP : un compte `pending` ne peut pas se connecter.
    const otp = await api(app).post("/auth/otp/send").send({ target: email, purpose: "email_verification" });
    await api(app)
      .post("/auth/otp/verify")
      .send({ target: email, code: otp.body.data.devCode, purpose: "email_verification" });

    token = await login(app, { email, password });
  });

  afterAll(async () => {
    await app.close();
  });

  describe("profil", () => {
    it("renvoie mon profil sans jamais exposer l'empreinte du mot de passe", async () => {
      const response = await api(app).get("/me").set(...auth(token));

      expect(response.status).toBe(200);
      expect(response.body.data.email).toBe(email);
      expect(response.body.data).toHaveProperty("hasClientProfile");
      expect(response.body.data).toHaveProperty("hasProviderProfile");
      expect(response.body.data).toHaveProperty("providerValidationStatus");
      expect(JSON.stringify(response.body)).not.toContain("passwordHash");
    });

    it("refuse l'accès sans jeton", async () => {
      expect((await api(app).get("/me")).status).toBe(401);
    });

    it("met à jour le nom sans toucher à la vérification", async () => {
      const response = await api(app).patch("/me").set(...auth(token)).send({ firstName: "Awa-Marie" });

      expect(response.status).toBe(200);
      expect(response.body.data.firstName).toBe("Awa-Marie");
      expect(response.body.data.emailVerified).toBe(true);
    });

    /**
     * Règle du §3 : changer son téléphone le remet en NON vérifié. Sans cela,
     * il suffirait de vérifier un numéro puis d'en mettre un autre pour se
     * retrouver « vérifié » sur un numéro qu'on ne possède pas.
     */
    it("remet le téléphone en non vérifié et déclenche un code", async () => {
      const response = await api(app)
        .patch("/me")
        .set(...auth(token))
        .send({ phone: uniquePhone(7) });

      expect(response.status).toBe(200);
      expect(response.body.data.phoneVerified).toBe(false);
      expect(response.body.data.pendingVerifications).toEqual([
        expect.objectContaining({ channel: "sms" })
      ]);
    });

    it("refuse un email déjà pris par un autre compte", async () => {
      const other = uniqueEmail("me-other");
      await api(app).post("/auth/register").send({ email: other, password });

      const response = await api(app).patch("/me").set(...auth(token)).send({ email: other });
      expect(response.status).toBe(409);
    });
  });

  describe("changement de mot de passe", () => {
    it("exige l'ancien mot de passe", async () => {
      const response = await api(app)
        .post("/me/password")
        .set(...auth(token))
        .send({ currentPassword: "mauvais123", newPassword: "nouveaupass1" });

      expect(response.status).toBe(401);
    });

    /**
     * Le cœur du §3 : les AUTRES sessions tombent, la session courante
     * survit. C'est ce qu'on attend après avoir perdu un téléphone — sans quoi
     * l'utilisateur serait puni d'avoir fait le bon geste.
     */
    it("révoque les autres sessions et garde la session courante", async () => {
      const autreSession = await api(app).post("/auth/login").send({ email, password });
      const autreRefresh = autreSession.body.data.refreshToken as string;

      const changement = await api(app)
        .post("/me/password")
        .set(...auth(token))
        .send({ currentPassword: password, newPassword: "nouveaupass1" });

      expect(changement.status).toBe(200);
      expect(changement.body.data.revokedSessions).toBeGreaterThanOrEqual(1);

      // L'autre appareil ne peut plus renouveler son jeton…
      const refus = await api(app).post("/auth/refresh").send({ refreshToken: autreRefresh });
      expect(refus.status).toBe(401);

      // …alors que la session courante fonctionne toujours.
      expect((await api(app).get("/me").set(...auth(token))).status).toBe(200);

      // L'ancien mot de passe ne vaut plus rien.
      const ancienne = await api(app).post("/auth/login").send({ email, password });
      expect(ancienne.status).toBe(401);

      token = await login(app, { email, password: "nouveaupass1" });
    });
  });

  describe("carnet d'adresses", () => {
    let addressId: string;

    it("crée une adresse et la marque par défaut si c'est la première", async () => {
      const response = await api(app)
        .post("/me/addresses")
        .set(...auth(token))
        .send({
          label: "Maison",
          city: "Abidjan",
          commune: "Cocody",
          details: "Rue des Jardins, portail vert",
          latitude: 5.35,
          longitude: -3.98
        });

      expect(response.status).toBe(201);
      expect(response.body.data.isDefault).toBe(true);
      addressId = response.body.data.id;
    });

    it("exige des coordonnées géographiques", async () => {
      const response = await api(app)
        .post("/me/addresses")
        .set(...auth(token))
        .send({ label: "Bureau", city: "Abidjan" });

      // Sans coordonnées, impossible de vérifier qu'un prestataire couvre
      // l'adresse : la réservation serait bloquée plus tard, sans explication.
      expect(response.status).toBe(400);
    });

    it("n'a qu'une seule adresse par défaut à la fois", async () => {
      const seconde = await api(app)
        .post("/me/addresses")
        .set(...auth(token))
        .send({ label: "Bureau", city: "Abidjan", latitude: 5.34, longitude: -3.99, isDefault: true });

      expect(seconde.status).toBe(201);

      const liste = await api(app).get("/me/addresses").set(...auth(token));
      expect(liste.body.data.filter((address: { isDefault: boolean }) => address.isDefault)).toHaveLength(1);
      expect(liste.body.data.find((address: { id: string }) => address.id === addressId).isDefault).toBe(false);
    });

    it("bascule l'adresse par défaut", async () => {
      const response = await api(app).post(`/me/addresses/${addressId}/default`).set(...auth(token));

      expect(response.status).toBe(200);
      expect(response.body.data.filter((address: { isDefault: boolean }) => address.isDefault)).toHaveLength(1);
      expect(response.body.data.find((address: { id: string }) => address.id === addressId).isDefault).toBe(true);
    });

    it("plafonne le carnet à dix adresses", async () => {
      for (let index = 0; index < 8; index += 1) {
        await api(app)
          .post("/me/addresses")
          .set(...auth(token))
          .send({ label: `Adresse ${index}`, city: "Abidjan", latitude: 5.3 + index / 100, longitude: -4 });
      }

      const onzieme = await api(app)
        .post("/me/addresses")
        .set(...auth(token))
        .send({ label: "De trop", city: "Abidjan", latitude: 5.3, longitude: -4 });

      expect(onzieme.status).toBe(400);
      expect(onzieme.body.message).toMatch(/10 adresses/);
    });

    it("ne laisse pas toucher à l'adresse d'un autre compte", async () => {
      const autreEmail = uniqueEmail("me-intrus");
      await api(app).post("/auth/register").send({ email: autreEmail, password });
      const otp = await api(app)
        .post("/auth/otp/send")
        .send({ target: autreEmail, purpose: "email_verification" });
      await api(app)
        .post("/auth/otp/verify")
        .send({ target: autreEmail, code: otp.body.data.devCode, purpose: "email_verification" });
      const autreToken = await login(app, { email: autreEmail, password });

      const lecture = await api(app).get("/me/addresses").set(...auth(autreToken));
      expect(lecture.body.data).toHaveLength(0);

      const modification = await api(app)
        .patch(`/me/addresses/${addressId}`)
        .set(...auth(autreToken))
        .send({ label: "Détournée" });
      expect(modification.status).toBe(404);
    });
  });
});
