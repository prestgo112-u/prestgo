import { applyTestEnv } from "./test-env.js";

// Exécuté dans CHAQUE worker Vitest, avant le chargement des tests.
// C'est ce qui garantit que l'application testée se connecte à la base de test
// et non à celle de développement.
applyTestEnv();
