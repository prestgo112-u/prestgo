import swc from "unplugin-swc";
import { defineConfig } from "vitest/config";

/**
 * Configuration des tests.
 *
 * Les tests d'intégration démarrent la VRAIE application NestJS et
 * l'interrogent en HTTP. `globalSetup` prépare une base dédiée avant la
 * première suite.
 *
 * ⚠️ Point de blocage rencontré : le compilateur par défaut de Vitest (esbuild)
 * ne sait PAS produire `emitDecoratorMetadata`. Sans cette métadonnée, NestJS
 * ne peut pas deviner les types du constructeur et l'injection de dépendances
 * échoue (« Cannot read properties of undefined »). SWC, lui, le fait — d'où ce
 * plugin. C'est la configuration recommandée pour NestJS + Vitest.
 */
export default defineConfig({
  plugins: [
    swc.vite({
      module: { type: "es6" },
      jsc: {
        target: "es2022",
        parser: { syntax: "typescript", decorators: true },
        transform: { legacyDecorator: true, decoratorMetadata: true }
      }
    })
  ],
  test: {
    globalSetup: ["./tests/helpers/global-setup.ts"],
    // Rejoué dans chaque worker : Vitest isole les tests dans des threads
    // séparés, où les variables posées par globalSetup ne sont pas visibles.
    setupFiles: ["./tests/helpers/setup-worker.ts"],
    // 60 s : le premier test paie le démarrage de Nest et de Prisma.
    testTimeout: 60_000,
    hookTimeout: 120_000,
    pool: "threads",
    // Une seule suite à la fois : plusieurs fichiers écrivant simultanément
    // dans la même base se marcheraient dessus.
    poolOptions: {
      threads: { singleThread: true }
    }
  }
});
