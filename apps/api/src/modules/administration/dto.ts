import { IsBoolean, IsIn, IsOptional, IsString, IsUUID, MaxLength, MinLength } from "class-validator";
import { EXPORT_TYPES } from "../reports/exports.service.js";

// --- Réglages ---
export class UpdateSettingBodyDto {
  // La valeur est toujours transportée en texte ; sa cohérence avec le type
  // déclaré (number, boolean, json) est vérifiée par le service.
  @IsString({ message: "La valeur du réglage doit être une chaîne de caractères" })
  @MaxLength(5000)
  value!: string;
}

// --- Notifications ---
export class SendNotificationBodyDto {
  @IsOptional()
  @IsUUID(undefined, { message: "userId doit être un identifiant valide" })
  userId?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(80)
  type!: string;

  @IsString()
  @MinLength(1, { message: "Le titre est obligatoire" })
  @MaxLength(200)
  title!: string;

  @IsString()
  @MinLength(1, { message: "Le contenu est obligatoire" })
  @MaxLength(4000)
  body!: string;

  @IsOptional()
  @IsIn(["in_app", "email", "sms"], { message: "Canal inconnu (in_app, email ou sms)" })
  channel?: string;
}

export class UpdateNotificationTemplateBodyDto {
  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(200)
  titleTemplate?: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(4000)
  bodyTemplate?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

// --- Exports ---
export class CreateExportBodyDto {
  @IsIn(EXPORT_TYPES as unknown as string[], {
    message: `Type d'export inconnu. Valeurs acceptées : ${EXPORT_TYPES.join(", ")}`
  })
  type!: string;

  @IsOptional()
  filters?: unknown;
}
