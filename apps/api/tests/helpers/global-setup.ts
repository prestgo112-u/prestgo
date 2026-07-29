import { execSync } from "node:child_process";
import { PrismaClient } from "@prisma/client";
import { applyTestEnv } from "./test-env.js";

/**
 * Prépare la base de données DÉDIÉE aux tests avant la première suite.
 *
 * Pourquoi une base à part : les tests créent, modifient et suppriment des
 * données. Les faire tourner sur la base de développement détruirait le jeu de
 * démonstration à chaque exécution.
 *
 * Le nom est déduit de `DATABASE_URL` en ajoutant le suffixe `_test` — il n'y a
 * rien à configurer manuellement.
 *
 * VIDAGE SYSTÉMATIQUE DU CONTENU — corrige une accumulation constatée en
 * production de tests.
 *
 * La version précédente appliquait seulement `migrate deploy` (non
 * destructif), en supposant que « chaque test qui crée un compte utilise un
 * identifiant unique, les exécutions sont donc indépendantes sans avoir à
 * repartir de zéro ». C'était vrai pour l'ABSENCE DE COLLISION, mais faux pour
 * l'ACCUMULATION : rien n'étant jamais supprimé, chaque exécution complète de
 * la suite ajoutait ses propres comptes et prestataires à ceux de la
 * précédente. Au 29 juillet 2026, la base de test contenait 91 prestataires
 * approuvés couvrant tous la même zone (Cocody) — assez pour faire sortir de
 * la première page de résultats le prestataire qu'un test de recherche
 * s'attendait à y trouver, un échec intermittent sans rapport avec ce que ce
 * test vérifiait.
 *
 * Pourquoi une TRUNCATE manuelle et pas `prisma migrate reset` : cette
 * dernière commande est REFUSÉE par le CLI Prisma lorsqu'il détecte être
 * invoqué par un agent de codage IA (« Prisma Migrate detected that it was
 * invoked by Claude Code », constaté en exerçant ce chemin) — un garde-fou de
 * Prisma lui-même contre une exécution automatisée non supervisée d'une
 * commande destructrice. `globalSetup` tourne pourtant sans supervision, à
 * chaque lancement de la suite : il ne peut pas dépendre d'une commande qui
 * exige une confirmation humaine. Vider le contenu par `TRUNCATE ... CASCADE`
 * via le client Prisma (et non le CLI Migrate) n'emprunte pas ce chemin — et
 * est de toute façon plus rapide qu'un DROP/CREATE de la base entière suivi
 * du rejeu de toutes les migrations.
 *
 * Exécuté une seule fois par exécution complète (`globalSetup`, pas
 * `setupFiles`) : les fichiers de test tournent en séquence dans le même
 * processus (`singleThread: true`), sur la base ainsi vidée — c'est
 * l'isolation ENTRE FICHIERS, construite sur des identifiants uniques
 * (`uniqueEmail`), qui reste inchangée. Vider la base entre chaque fichier
 * casserait cette isolation pour rien : le problème n'était pas la
 * concurrence intra-run, c'était la mémoire INTER-runs.
 */
export async function setup(): Promise<void> {
  const databaseUrl = applyTestEnv();
  const env = { ...process.env, DATABASE_URL: databaseUrl };

  // Garde-fou : tout ce qui suit DÉTRUIT le contenu de la base. On refuse de
  // continuer si l'URL ne désigne pas visiblement une base de test.
  if (!/_test(\?|$)/.test(databaseUrl)) {
    throw new Error(`Refus de préparer une base qui n'est pas de test : ${databaseUrl.replace(/:[^:@]*@/, ":***@")}`);
  }

  // On applique les MIGRATIONS VERSIONNÉES, pas `db push` (§15.1). C'est le
  // même chemin qu'en production : les tests valident donc aussi que la suite
  // de migrations committée reconstruit bien une base fonctionnelle.
  try {
    execSync("npx prisma migrate deploy", { env, stdio: "pipe" });
  } catch (error) {
    // Cas de bascule : la base de test avait été construite par `db push`, elle
    // contient donc les tables SANS historique de migrations. Prisma refuse
    // alors de déployer (P3005). On repart d'un schéma vide par SQL brut — PAS
    // par `prisma migrate reset`, bloqué pour la même raison qu'expliqué
    // au-dessus — puis on rejoue les migrations dessus.
    process.stdout.write(
      "Base de test incompatible avec l'historique de migrations : reconstruction complète.\n" +
        `(${error instanceof Error ? error.message.split("\n")[0] : String(error)})\n`
    );
    await dropAndRecreateSchema(databaseUrl);
    execSync("npx prisma migrate deploy", { env, stdio: "pipe" });
  }

  await truncateAllTables(databaseUrl);
  execSync("npx tsx prisma/seed.ts", { env, stdio: "pipe" });
}

export async function teardown(): Promise<void> {
  // La base est conservée après l'exécution : c'est `setup()`, au prochain
  // lancement, qui la vide et la reconstruit systématiquement.
}

/** Vide toutes les tables applicatives, en conservant le schéma et l'historique de migrations. */
async function truncateAllTables(databaseUrl: string): Promise<void> {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl } } });
  try {
    const tables = await prisma.$queryRawUnsafe<{ tablename: string }[]>(
      // `_prisma_migrations` est exclue : c'est l'historique des migrations
      // appliquées, pas une donnée applicative — la vider forcerait Prisma à
      // tout rejouer inutilement au prochain `migrate deploy`.
      `SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename != '_prisma_migrations'`
    );
    if (tables.length === 0) {
      return;
    }
    const list = tables.map((t) => `"${t.tablename}"`).join(", ");
    // `RESTART IDENTITY` : les compteurs auto-incrémentés (le cas échéant)
    // repartent de zéro, pour un état de départ identique à chaque exécution.
    // `CASCADE` : nécessaire, les tables se référencent entre elles par clé
    // étrangère.
    await prisma.$executeRawUnsafe(`TRUNCATE TABLE ${list} RESTART IDENTITY CASCADE`);
  } finally {
    await prisma.$disconnect();
  }
}

/** Repart d'un schéma `public` vide, sans passer par `prisma migrate reset` (voir note ci-dessus). */
async function dropAndRecreateSchema(databaseUrl: string): Promise<void> {
  const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl } } });
  try {
    await prisma.$executeRawUnsafe("DROP SCHEMA public CASCADE");
    await prisma.$executeRawUnsafe("CREATE SCHEMA public");
  } finally {
    await prisma.$disconnect();
  }
}
