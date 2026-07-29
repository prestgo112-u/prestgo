import { execSync } from "node:child_process";
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
 */
export async function setup(): Promise<void> {
  const databaseUrl = applyTestEnv();
  const env = { ...process.env, DATABASE_URL: databaseUrl };

  // Garde-fou : tout ce qui suit peut réinitialiser la base. On refuse de
  // continuer si l'URL ne désigne pas visiblement une base de test.
  if (!/_test(\?|$)/.test(databaseUrl)) {
    throw new Error(`Refus de préparer une base qui n'est pas de test : ${databaseUrl.replace(/:[^:@]*@/, ":***@")}`);
  }

  // On applique les MIGRATIONS VERSIONNÉES, pas `db push` (§15.1).
  //
  // C'est le même chemin qu'en production : les tests valident donc aussi que
  // la suite de migrations committée reconstruit bien une base fonctionnelle.
  // Avec `db push`, une migration cassée n'aurait été découverte qu'au
  // déploiement.
  //
  // Rien n'est vidé en régime normal : chaque test qui crée un compte utilise
  // un identifiant unique (voir `uniqueEmail` dans test-app.ts), les
  // exécutations sont donc indépendantes sans avoir à repartir de zéro.
  try {
    execSync("npx prisma migrate deploy", { env, stdio: "pipe" });
  } catch (error) {
    // Cas de bascule : la base de test avait été construite par `db push`, elle
    // contient donc les tables SANS historique de migrations. Prisma refuse
    // alors de déployer (P3005). Une base de test est reconstructible : on la
    // remet à plat une fois, puis on rejoue proprement les migrations.
    process.stdout.write(
      "Base de test incompatible avec l'historique de migrations : reconstruction complète.\n" +
        `(${error instanceof Error ? error.message.split("\n")[0] : String(error)})\n`
    );
    execSync("npx prisma migrate reset --force --skip-seed --skip-generate", { env, stdio: "pipe" });
  }

  execSync("npx tsx prisma/seed.ts", { env, stdio: "pipe" });
}

export async function teardown(): Promise<void> {
  // La base est conservée : la recréer coûterait du temps à chaque exécution,
  // et `migrate deploy` la remet d'aplomb au démarrage suivant.
}
