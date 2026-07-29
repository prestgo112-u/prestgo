import type { INestApplication } from "@nestjs/common";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { api, createTestApp, login, SEED_USERS, uniqueEmail, uniquePhone } from "../helpers/test-app.js";

/**
 * Parcours d'authentification, testé contre la vraie application.
 *
 * Chaque compte de test a un email unique : les suites tournent sur une base
 * partagée, deux tests ne doivent pas se disputer la même adresse.
 */
describe("authentification", () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp();
  });

  afterAll(async () => {
    await app.close();
  });

  describe("connexion", () => {
    it("délivre un jeton avec les bons identifiants", async () => {
      const response = await api(app).post("/auth/login").send(SEED_USERS.admin);

      expect(response.status).toBe(200);
      expect(response.body.success).toBe(true);
      expect(response.body.data.accessToken).toBeTypeOf("string");
      expect(response.body.data.refreshToken).toBeTypeOf("string");
    });

    it("refuse un mauvais mot de passe", async () => {
      const response = await api(app)
        .post("/auth/login")
        .send({ email: SEED_USERS.admin.email, password: "mauvais-mot-de-passe" });

      expect(response.status).toBe(401);
      expect(response.body.success).toBe(false);
    });

    it("ne dit pas si l'échec vient de l'email ou du mot de passe", async () => {
      const inconnu = await api(app).post("/auth/login").send({ email: "inconnu@nulle.part", password: "quelquechose1" });
      const mauvaisMdp = await api(app)
        .post("/auth/login")
        .send({ email: SEED_USERS.admin.email, password: "quelquechose1" });

      // Même statut ET même message : impossible de deviner quels comptes existent.
      expect(inconnu.status).toBe(mauvaisMdp.status);
      expect(inconnu.body.message).toBe(mauvaisMdp.body.message);
    });

    it("valide le format de l'email", async () => {
      const response = await api(app).post("/auth/login").send({ email: "pas-un-email", password: "x" });

      expect(response.status).toBe(400);
      expect(response.body.errors.length).toBeGreaterThan(0);
    });

    it("place un identifiant de corrélation sur chaque réponse", async () => {
      const response = await api(app).post("/auth/login").send(SEED_USERS.admin);
      expect(response.headers["x-correlation-id"]).toBeTypeOf("string");
    });
  });

  describe("inscription et activation", () => {
    const email = uniqueEmail("nouveau");
    const phone = uniquePhone(1);

    it("crée un compte au statut « pending »", async () => {
      const response = await api(app)
        .post("/auth/register")
        .send({ email, phone, password: "motdepasse1", firstName: "Yao" });

      expect(response.status).toBe(201);
      expect(response.body.data.status).toBe("pending");
      // L'empreinte du mot de passe ne doit jamais sortir de l'API.
      expect(response.body.data.passwordHash).toBeUndefined();
    });

    it("refuse un mot de passe sans chiffre", async () => {
      const response = await api(app)
        .post("/auth/register")
        .send({ email: uniqueEmail("faible"), password: "seulementdeslettres" });

      expect(response.status).toBe(400);
    });

    it("refuse un email déjà utilisé", async () => {
      const response = await api(app).post("/auth/register").send({ email, password: "motdepasse1" });
      expect(response.status).toBe(409);
    });

    it("empêche la connexion tant que le compte n'est pas activé", async () => {
      const response = await api(app).post("/auth/login").send({ email, password: "motdepasse1" });
      expect(response.status).toBe(401);
    });

    it("active le compte après vérification du code", async () => {
      const envoi = await api(app).post("/auth/otp/send").send({ target: phone });
      expect(envoi.status).toBe(200);
      const code = envoi.body.data.devCode as string;
      expect(code).toMatch(/^\d{6}$/);

      // Un mauvais code est refusé...
      const mauvais = await api(app).post("/auth/otp/verify").send({ target: phone, code: "000000" });
      expect(mauvais.status).toBe(400);

      // ...le bon active le compte.
      const bon = await api(app).post("/auth/otp/verify").send({ target: phone, code });
      expect(bon.status).toBe(200);
      expect(bon.body.data.activated).toBe(true);

      const connexion = await api(app).post("/auth/login").send({ email, password: "motdepasse1" });
      expect(connexion.status).toBe(200);
    });

    it("refuse de réutiliser un code déjà consommé", async () => {
      const envoi = await api(app).post("/auth/otp/send").send({ target: phone });
      const code = envoi.body.data.devCode as string;

      expect((await api(app).post("/auth/otp/verify").send({ target: phone, code })).status).toBe(200);
      expect((await api(app).post("/auth/otp/verify").send({ target: phone, code })).status).toBe(400);
    });
  });

  describe("mot de passe oublié", () => {
    const email = uniqueEmail("oubli");

    beforeAll(async () => {
      await api(app).post("/auth/register").send({ email, password: "premierpass1" });
    });

    it("répond la même chose pour un email connu et un email inconnu", async () => {
      const connu = await api(app).post("/auth/forgot-password").send({ email });
      const inconnu = await api(app).post("/auth/forgot-password").send({ email: "personne@nulle.part" });

      expect(connu.status).toBe(inconnu.status);
      expect(connu.body.message).toBe(inconnu.body.message);
    });

    it("change le mot de passe, une seule fois, et invalide l'ancien", async () => {
      const demande = await api(app).post("/auth/forgot-password").send({ email });
      const token = demande.body.data.devToken as string;
      expect(token).toBeTypeOf("string");

      // Un jeton inventé ne marche pas.
      const bidon = await api(app)
        .post("/auth/reset-password")
        .send({ token: "0".repeat(64), password: "nouveaupass1" });
      expect(bidon.status).toBe(400);

      // Le vrai jeton fonctionne.
      expect((await api(app).post("/auth/reset-password").send({ token, password: "nouveaupass1" })).status).toBe(200);

      // Mais une seule fois.
      expect((await api(app).post("/auth/reset-password").send({ token, password: "encoreautre1" })).status).toBe(400);

      // L'ancien mot de passe ne fonctionne plus, le nouveau oui.
      // (le compte n'étant pas activé, la connexion échoue quand même : on
      //  vérifie donc le message, qui distingue les deux causes)
      const ancien = await api(app).post("/auth/login").send({ email, password: "premierpass1" });
      expect(ancien.body.message).toBe("Invalid credentials");

      const nouveau = await api(app).post("/auth/login").send({ email, password: "nouveaupass1" });
      expect(nouveau.body.message).toBe("Account is not active");
    });
  });

  describe("jeton d'accès", () => {
    it("refuse une route protégée sans jeton", async () => {
      const response = await api(app).get("/admin/users");
      expect(response.status).toBe(401);
      expect(response.body.meta.correlationId).toBeTypeOf("string");
    });

    it("refuse un jeton invalide sans détail technique", async () => {
      const response = await api(app).get("/admin/users").set("Authorization", "Bearer nimportequoi");

      expect(response.status).toBe(401);
      // Le message reste générique : pas de trace de la librairie JWT.
      expect(response.body.message).not.toContain("jwt");
      expect(response.body.message).not.toContain("malformed");
    });

    it("accepte un jeton valide", async () => {
      const token = await login(app, SEED_USERS.admin);
      const response = await api(app).get("/admin/users").set("Authorization", `Bearer ${token}`);
      expect(response.status).toBe(200);
    });
  });
});
