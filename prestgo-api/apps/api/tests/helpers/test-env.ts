import { readFileSync } from "node:fs";
import { resolve } from "node:path";

/**
 * Variables d'environnement des tests.
 *
 * Ce fichier est appelé DEUX fois, et c'est volontaire :
 *   - par `globalSetup`, dans le processus principal, pour créer la base ;
 *   - par `setupFiles`, dans CHAQUE worker, parce que Vitest isole les tests
 *     dans des threads séparés où les variables du processus principal ne sont
 *     pas visibles.
 *
 * Sans le second appel, l'application testée se connecterait à la base de
 * développement — ce qu'on veut absolument éviter.
 */
export function applyTestEnv(): string {
  const databaseUrl = toTestUrl(readDatabaseUrl());

  process.env.DATABASE_URL = databaseUrl;
  process.env.FILE_STORAGE_DIR = resolve(process.cwd(), "storage-test");
  process.env.NOTIFICATION_OUTBOX = resolve(process.cwd(), "storage-test", "outbox");
  // Nécessaire pour lire les codes OTP et jetons dans les tests.
  process.env.AUTH_EXPOSE_DEV_CODES = "true";
  // Traitement immédiat : un test ne doit pas attendre un worker de fond.
  process.env.QUEUE_DRIVER = "inline";
  // Les limites de production bloqueraient les tests, qui enchaînent des
  // dizaines d'appels par seconde. Un test dédié rabaisse sa propre limite
  // pour vérifier que le limiteur fonctionne bien.
  process.env.THROTTLE_LIMIT = "100000";
  process.env.THROTTLE_AUTH_LIMIT = "100000";
  process.env.THROTTLE_SENSITIVE_LIMIT = "100000";
  process.env.THROTTLE_MODERATE_LIMIT = "100000";
  // Limites de la surface mobile (§14.5). Elles s'expriment à l'heure ou au
  // jour : sans relèvement, la fenêtre ne se rouvrirait pas entre deux suites,
  // et les tests se bloqueraient eux-mêmes — le limiteur compte par adresse IP,
  // que toutes les suites partagent.
  process.env.THROTTLE_BOOKING_LIMIT = "100000";
  process.env.THROTTLE_REPORT_LIMIT = "100000";
  process.env.THROTTLE_DEVICE_LIMIT = "100000";

  return databaseUrl;
}

function readDatabaseUrl(): string {
  const fromEnv = process.env.DATABASE_URL;
  // Si la variable pointe déjà vers la base de test, on ne la retransforme pas.
  if (fromEnv && !fromEnv.includes("_test")) {
    return fromEnv;
  }
  if (fromEnv) {
    return fromEnv;
  }

  const envFile = readFileSync(resolve(process.cwd(), ".env"), "utf8");
  const match = envFile.match(/^DATABASE_URL="?([^"\n\r]+)"?/m);
  if (!match?.[1]) {
    throw new Error("DATABASE_URL introuvable (ni en variable d'environnement, ni dans .env)");
  }
  return match[1];
}

// postgresql://…/prestgo?schema=public  ->  postgresql://…/prestgo_test?schema=public
function toTestUrl(url: string): string {
  if (/\/[^/?]*_test(\?|$)/.test(url)) {
    return url; // déjà transformée
  }
  return url.replace(/\/([^/?]+)(\?|$)/, "/$1_test$2");
}
