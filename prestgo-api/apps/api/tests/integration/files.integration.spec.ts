import type { INestApplication } from "@nestjs/common";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { api, createTestApp, login, SEED_USERS } from "../helpers/test-app.js";

/**
 * Fichiers : envoi, contrôle d'accès et exports.
 *
 * Deux failles ont été corrigées au Lot 0 sur ce périmètre ; ces tests
 * garantissent qu'elles ne reviendront pas.
 */
describe("fichiers", () => {
  let app: INestApplication;
  let adminToken: string;
  let providerToken: string;

  beforeAll(async () => {
    app = await createTestApp();
    adminToken = await login(app, SEED_USERS.admin);
    providerToken = await login(app, SEED_USERS.provider);
  });

  afterAll(async () => {
    await app.close();
  });

  async function upload(token: string, name = "document.txt", contenu = "contenu de test"): Promise<string> {
    const response = await api(app)
      .post("/files/upload")
      .set("Authorization", `Bearer ${token}`)
      .attach("file", Buffer.from(contenu), { filename: name, contentType: "text/plain" });

    expect(response.status).toBe(201);
    return response.body.data.id as string;
  }

  describe("envoi", () => {
    it("enregistre un fichier et son contenu", async () => {
      const id = await upload(adminToken, "facture.txt", "Montant : 15000 F CFA");

      const contenu = await api(app).get(`/files/${id}/content`).set("Authorization", `Bearer ${adminToken}`);
      expect(contenu.status).toBe(200);
      expect(contenu.text).toContain("15000");
    });

    it("IGNORE la visibilité « public » demandée par le client", async () => {
      const response = await api(app)
        .post("/files/upload")
        .set("Authorization", `Bearer ${adminToken}`)
        .field("visibility", "public")
        .attach("file", Buffer.from("x"), { filename: "a.txt", contentType: "text/plain" });

      // Le serveur retombe sur « restricted » : un utilisateur ne peut pas
      // rendre son propre fichier lisible par tous.
      expect(response.body.data.visibility).toBe("restricted");
    });

    it("IGNORE le chemin de stockage proposé par le client", async () => {
      const response = await api(app)
        .post("/files/upload")
        .set("Authorization", `Bearer ${adminToken}`)
        .field("storageKey", "../../etc/passwd")
        .attach("file", Buffer.from("x"), { filename: "../../etc/passwd", contentType: "text/plain" });

      const key = response.body.data.storageKey as string;
      expect(key).toMatch(/^uploads\//);
      expect(key).not.toContain("..");
    });

    it("refuse un type de fichier non autorisé", async () => {
      const response = await api(app)
        .post("/files/upload")
        .set("Authorization", `Bearer ${adminToken}`)
        .attach("file", Buffer.from("MZ"), { filename: "virus.exe", contentType: "application/x-msdownload" });

      expect(response.status).toBe(400);
      expect(response.body.message).toContain("non autorisé");
    });

    it("refuse une requête sans fichier", async () => {
      const response = await api(app).post("/files/upload").set("Authorization", `Bearer ${adminToken}`);
      expect(response.status).toBe(400);
    });
  });

  describe("contrôle d'accès", () => {
    it("réserve un fichier restreint à son propriétaire", async () => {
      const id = await upload(adminToken, "prive.txt", "donnees confidentielles");

      const parLeProprietaire = await api(app).get(`/files/${id}`).set("Authorization", `Bearer ${adminToken}`);
      expect(parLeProprietaire.status).toBe(200);

      // C'est la faille corrigée au Lot 0 : avant, ceci renvoyait 200.
      const parUnAutre = await api(app).get(`/files/${id}`).set("Authorization", `Bearer ${providerToken}`);
      expect(parUnAutre.status).toBe(403);
    });

    it("protège aussi le CONTENU, pas seulement les métadonnées", async () => {
      const id = await upload(adminToken, "prive2.txt", "secret");

      const response = await api(app).get(`/files/${id}/content`).set("Authorization", `Bearer ${providerToken}`);
      expect(response.status).toBe(403);
    });

    it("refuse sans jeton", async () => {
      const id = await upload(adminToken);
      expect((await api(app).get(`/files/${id}`)).status).toBe(401);
    });

    /**
     * Écart n°5 du cahier des charges mobile.
     *
     * La recherche et les fiches publiques sont consultables sans compte et
     * renvoient `avatarFileId` ; tant que `/content` exigeait un jeton, ces
     * identifiants ne menaient à rien et l'écran d'accueil restait sans image.
     *
     * L'ouverture ne vaut QUE pour la visibilité `public` — celle qu'un
     * prestataire pose explicitement en publiant une réalisation.
     */
    describe("contenu d'un fichier public (sans compte)", () => {
      let fichierPublic: string;

      beforeAll(async () => {
        // Un fichier ne devient `public` que par une décision explicite du
        // prestataire : ici, la publication d'une réalisation de portfolio.
        const image = await api(app)
          .post("/files/upload")
          .set("Authorization", `Bearer ${providerToken}`)
          .attach("file", Buffer.from("image-de-realisation"), {
            filename: "chantier.png",
            contentType: "image/png"
          });

        fichierPublic = image.body.data.id as string;

        const publication = await api(app)
          .post("/providers/me/portfolio")
          .set("Authorization", `Bearer ${providerToken}`)
          .send({ fileId: fichierPublic, title: "Réfection salle de bain" });
        expect(publication.status).toBe(201);
      });

      it("sert le contenu d'un fichier public sans aucun jeton", async () => {
        const response = await api(app).get(`/files/${fichierPublic}/content`);

        expect(response.status).toBe(200);
        expect(response.headers["content-type"]).toContain("image/png");
      });

      it("sert toujours ce fichier à un utilisateur connecté", async () => {
        const response = await api(app)
          .get(`/files/${fichierPublic}/content`)
          .set("Authorization", `Bearer ${adminToken}`);
        expect(response.status).toBe(200);
      });

      it("tolère un jeton invalide et retombe sur l'accès anonyme", async () => {
        // Un jeton périmé en cours de défilement ne doit pas casser l'affichage
        // d'un avatar, qui est public de toute façon.
        const response = await api(app)
          .get(`/files/${fichierPublic}/content`)
          .set("Authorization", "Bearer jeton-totalement-invalide");
        expect(response.status).toBe(200);
      });

      it("refuse en 403 le contenu d'un fichier NON public sans jeton", async () => {
        const prive = await upload(adminToken, "confidentiel.txt", "secret");

        const response = await api(app).get(`/files/${prive}/content`);
        // 403 et non 401 : la route est publique, c'est la POLITIQUE d'accès
        // qui refuse, pas l'absence d'authentification.
        expect(response.status).toBe(403);
        expect(response.body.success).toBe(false);
      });

      it("laisse le propriétaire lire son propre fichier non public", async () => {
        const prive = await upload(adminToken, "a-moi.txt", "mon contenu");

        const response = await api(app)
          .get(`/files/${prive}/content`)
          .set("Authorization", `Bearer ${adminToken}`);
        expect(response.status).toBe(200);
        expect(response.text).toContain("mon contenu");
      });

      it("garde les MÉTADONNÉES protégées : /files/:id exige toujours un jeton", async () => {
        expect((await api(app).get(`/files/${fichierPublic}`)).status).toBe(401);
      });
    });

    it("renvoie 404 sur un fichier désactivé", async () => {
      const id = await upload(adminToken, "temporaire.txt");

      expect((await api(app).delete(`/files/${id}`).set("Authorization", `Bearer ${adminToken}`)).status).toBe(200);
      expect((await api(app).get(`/files/${id}`).set("Authorization", `Bearer ${adminToken}`)).status).toBe(404);
    });
  });

  describe("exports", () => {
    it("génère un CSV réellement rempli", async () => {
      const job = await api(app)
        .post("/admin/exports")
        .set("Authorization", `Bearer ${adminToken}`)
        .send({ type: "providers" });

      expect(job.status).toBe(202);
      expect(job.body.data.status).toBe("completed");

      const fileId = job.body.data.fileId as string;
      const contenu = await api(app).get(`/files/${fileId}/content`).set("Authorization", `Bearer ${adminToken}`);

      expect(contenu.status).toBe(200);
      // En-tête présent, séparateur point-virgule, et au moins un prestataire.
      expect(contenu.text).toContain("nom_public");
      expect(contenu.text).toContain(";");
      expect(contenu.text.split("\r\n").length).toBeGreaterThan(1);
    });

    it("refuse un type d'export inconnu", async () => {
      const response = await api(app)
        .post("/admin/exports")
        .set("Authorization", `Bearer ${adminToken}`)
        .send({ type: "n_importe_quoi" });

      expect(response.status).toBe(400);
      expect(response.body.message).toContain("Valeurs acceptées");
    });
  });
});
