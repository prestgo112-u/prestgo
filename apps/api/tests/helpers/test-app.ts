import { ValidationPipe, type INestApplication } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import request from "supertest";
import { AppModule } from "../../src/app.module.js";
import { HttpExceptionFilter } from "../../src/common/filters/http-exception.filter.js";
import { validationExceptionFactory } from "../../src/common/pipes/validation-exception.factory.js";

/**
 * Démarre la VRAIE application NestJS pour les tests.
 *
 * Toute la chaîne est en place : middleware de corrélation, gardes globales
 * (débit, JWT, permissions), pipe de validation, filtre d'exception. Un test
 * qui passe ici prouve donc que la route fonctionne réellement — contrairement
 * aux anciens tests qui comparaient des littéraux entre eux.
 *
 * La configuration reproduit exactement `main.ts` : si les deux divergeaient,
 * les tests vérifieraient une application différente de celle qui tourne.
 */
export async function createTestApp(): Promise<INestApplication> {
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();

  const app = moduleRef.createNestApplication();
  app.setGlobalPrefix("api/v1");
  app.useGlobalPipes(
    new ValidationPipe({
      forbidUnknownValues: true,
      transform: true,
      whitelist: true,
      // Doit rester identique à `main.ts` : sans cette fabrique, les tests
      // valideraient un format d'erreur que la production ne produit pas.
      exceptionFactory: validationExceptionFactory
    })
  );
  app.useGlobalFilters(new HttpExceptionFilter());

  await app.init();
  return app;
}

export type Api = ReturnType<typeof request>;

// Raccourci : `api(app).get("/admin/users")` au lieu de répéter le préfixe.
export function api(app: INestApplication) {
  const server = app.getHttpServer();
  return {
    get: (path: string) => request(server).get(`/api/v1${path}`),
    post: (path: string) => request(server).post(`/api/v1${path}`),
    patch: (path: string) => request(server).patch(`/api/v1${path}`),
    put: (path: string) => request(server).put(`/api/v1${path}`),
    delete: (path: string) => request(server).delete(`/api/v1${path}`)
  };
}

/**
 * Identifiants uniques à chaque exécution.
 *
 * Pourquoi : la base de test n'est pas vidée entre deux `pnpm test` (vider une
 * base est une opération destructrice qu'on ne veut pas dans une commande
 * courante). Un test qui crée toujours `nouveau@test.ci` échouerait donc au
 * deuxième passage avec « email déjà utilisé ».
 *
 * En dérivant les identifiants de l'horodatage, chaque exécution travaille sur
 * ses propres comptes et reste indépendante des précédentes.
 */
const RUN_ID = Date.now().toString().slice(-9);

export function uniqueEmail(prefix: string): string {
  return `${prefix}-${RUN_ID}@test.ci`;
}

export function uniquePhone(offset = 0): string {
  // Numéro ivoirien plausible, unique par exécution.
  const suffix = (Number(RUN_ID) + offset).toString().slice(-8);
  return `+22507${suffix}`;
}

// Identifiants du jeu de démonstration créé par le seed.
export const SEED_USERS = {
  admin: { email: "admin@prestgo.test", password: "prestgo123!" },
  provider: { email: "kofi.plombier@prestgo.test", password: "prestgo123!" },
  client: { email: "client.demo@prestgo.test", password: "prestgo123!" }
} as const;

/**
 * Récupère un jeton d'accès.
 *
 * Attention : `/auth/login` est limité à 10 appels par minute et par IP. Les
 * suites de tests doivent donc récupérer leurs jetons UNE fois dans un
 * `beforeAll`, jamais dans chaque test.
 */
export async function login(app: INestApplication, user: { email: string; password: string }): Promise<string> {
  const response = await api(app).post("/auth/login").send(user);
  if (response.status !== 200) {
    throw new Error(`Connexion échouée pour ${user.email} : ${response.status} ${JSON.stringify(response.body)}`);
  }
  return response.body.data.accessToken as string;
}

// En-tête d'autorisation prêt à l'emploi.
export function auth(token: string): [string, string] {
  return ["Authorization", `Bearer ${token}`];
}
