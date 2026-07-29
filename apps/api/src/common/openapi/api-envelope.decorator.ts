import { applyDecorators, type Type } from "@nestjs/common";
import { ApiExtraModels, ApiResponse, getSchemaPath } from "@nestjs/swagger";

/**
 * Décorateurs Swagger pour l'enveloppe de réponse standard du projet
 * (`{ success, message, data, errors, meta }`, voir `common/contracts/api-response.ts`).
 *
 * Pourquoi ce fichier : documenter à la main le schéma d'enveloppe sur chaque
 * route aurait produit ~55 blocs `schema: { properties: { ... } }` identiques.
 * Ces fonctions ne font QUE construire des décorateurs `@ApiResponse` — elles
 * ne changent rien à ce que les contrôleurs renvoient réellement à l'exécution.
 */

const ERROR_SCHEMA = {
  properties: {
    success: { type: "boolean", example: false },
    message: { type: "string" },
    errors: {
      type: "array",
      items: {
        type: "object",
        properties: {
          field: { type: "string" },
          code: { type: "string" },
          message: { type: "string" }
        }
      }
    },
    meta: {
      type: "object",
      properties: { correlationId: { type: "string" } }
    }
  }
} as const;

export interface EnvelopeOptions {
  status?: number;
  description?: string;
  /** `data` est un tableau de `dataType` plutôt qu'un objet unique (listes). */
  isArray?: boolean;
  /** Ajoute les propriétés de pagination à `meta` (listes paginées). */
  paginated?: boolean;
}

/**
 * Documente une réponse de succès dans l'enveloppe standard.
 *
 * `dataType` doit être une classe décorée avec `@ApiProperty` sur ses champs.
 * Passer `undefined` documente une réponse dont `data` est un objet libre
 * (cas des quelques routes qui renvoient un objet ad hoc non modélisé).
 */
export function ApiEnvelopeResponse(dataType: Type<unknown> | undefined, options: EnvelopeOptions = {}): MethodDecorator {
  const status = options.status ?? 200;

  const dataSchema = dataType
    ? options.isArray
      ? { type: "array" as const, items: { $ref: getSchemaPath(dataType) } }
      : { $ref: getSchemaPath(dataType) }
    : { type: "object" as const, nullable: true };

  const metaProperties: Record<string, { type: string }> = options.paginated
    ? {
        page: { type: "integer" },
        limit: { type: "integer" },
        total: { type: "integer" }
      }
    : {};

  const responseDecorator = ApiResponse({
    status,
    description: options.description ?? "Succès",
    schema: {
      properties: {
        success: { type: "boolean", example: true },
        message: { type: "string" },
        data: dataSchema,
        meta: { type: "object", properties: metaProperties }
      }
    }
  });

  return dataType ? applyDecorators(ApiExtraModels(dataType), responseDecorator) : applyDecorators(responseDecorator);
}

/**
 * Documente une réponse d'erreur dans l'enveloppe standard (`success: false`).
 *
 * Un seul code par appel : poser plusieurs `@ApiErrorResponse` sur une même
 * route documente chaque cas d'erreur distinctement, avec sa propre description.
 */
export function ApiErrorResponse(status: number, description: string): MethodDecorator {
  return ApiResponse({ status, description, schema: ERROR_SCHEMA });
}
