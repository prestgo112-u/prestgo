import { Type } from "class-transformer";
import { IsInt, IsOptional, IsString, Max, Min } from "class-validator";
import { EmptyToUndefined } from "./transforms.js";

/**
 * Paramètres de pagination communs à toutes les listes (CDC §10).
 *
 * Pourquoi une CLASSE et pas une interface : une interface disparaît à la
 * compilation, NestJS ne peut donc rien valider. Une classe décorée survit à
 * l'exécution et le `ValidationPipe` peut faire son travail.
 *
 * `@Type(() => Number)` est indispensable : dans une URL, `?page=2` arrive
 * toujours sous forme de texte `"2"`. Ce décorateur le convertit en nombre
 * avant que `@IsInt` ne le vérifie.
 */
export class PaginationQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: "page doit être un nombre entier" })
  @Min(1, { message: "page doit être supérieur ou égal à 1" })
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: "limit doit être un nombre entier" })
  @Min(1, { message: "limit doit être supérieur ou égal à 1" })
  @Max(100, { message: "limit ne peut pas dépasser 100" })
  limit?: number;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  sort?: string;
}
