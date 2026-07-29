import type { INestApplication } from "@nestjs/common";
import { DocumentBuilder, SwaggerModule } from "@nestjs/swagger";
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

export function setupOpenApi(app: INestApplication): void {
  const config = new DocumentBuilder()
    .setTitle("PRESTGO Back-office Admin and Backend Services")
    .setDescription("Versioned contract for PRESTGO V1 backend and internal admin workflows.")
    .setVersion("1.0.0")
    .addBearerAuth()
    .addServer("/api/v1", "API v1")
    .build();

  const document = SwaggerModule.createDocument(app, config);
  SwaggerModule.setup("api/docs", app, document);

  // Export du contrat OpenAPI, pour la génération de clients.
  //
  // Le chemin était calculé depuis `process.cwd()` en supposant que le
  // processus démarre à la racine du monorepo. Lancée depuis `apps/api` — ce
  // que fait `pnpm --filter` comme tout script local — l'écriture échouait
  // silencieusement, et le contrat livré à l'équipe mobile restait périmé.
  const contractPath = resolveContractPath();
  try {
    mkdirSync(dirname(contractPath), { recursive: true });
    writeFileSync(contractPath, JSON.stringify(document, null, 2));
  } catch (error) {
    console.warn(`Failed to export OpenAPI contract: ${error instanceof Error ? error.message : String(error)}`);
  }
}

/**
 * Retrouve `packages/contracts/openapi.json` quel que soit le dossier de départ.
 *
 * On remonte l'arborescence jusqu'à trouver le marqueur du monorepo
 * (`pnpm-workspace.yaml`) plutôt que de coder « ../.. » en dur : la profondeur
 * changerait au premier déplacement de l'application.
 */
function resolveContractPath(): string {
  let directory = process.cwd();

  for (let depth = 0; depth < 6; depth += 1) {
    if (existsSync(join(directory, "pnpm-workspace.yaml"))) {
      return join(directory, "packages", "contracts", "openapi.json");
    }
    const parent = dirname(directory);
    if (parent === directory) {
      break;
    }
    directory = parent;
  }

  return join(process.cwd(), "packages", "contracts", "openapi.json");
}
