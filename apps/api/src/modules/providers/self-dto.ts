import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  MinLength
} from "class-validator";
import { EmptyToUndefined } from "../../common/dto/transforms.js";
import { MAX_PROVIDER_ZONES } from "../settings/settings.keys.js";

export class CreateProviderProfileBodyDto {
  @IsString()
  @MinLength(2, { message: "Le nom public doit contenir au moins 2 caractères" })
  @MaxLength(120)
  publicName!: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(2000)
  bio?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: "L'expérience doit être un nombre d'années" })
  @Min(0)
  @Max(70)
  experienceYears?: number;
}

/**
 * Disponibilité déclarée par le prestataire (§7).
 *
 * `unavailable` le fait disparaître de la recherche et refuse toute nouvelle
 * réservation — c'est l'interrupteur « je ne prends plus de mission », sans
 * avoir à effacer son agenda.
 */
export const AVAILABILITY_STATUSES = ["available", "busy", "unavailable"] as const;

export class UpdateProviderProfileBodyDto {
  @IsOptional()
  @IsString()
  @MinLength(2, { message: "Le nom public doit contenir au moins 2 caractères" })
  @MaxLength(120)
  publicName?: string;

  @IsOptional()
  @IsIn(AVAILABILITY_STATUSES, { message: `Disponibilité acceptée : ${AVAILABILITY_STATUSES.join(", ")}` })
  availabilityStatus?: (typeof AVAILABILITY_STATUSES)[number];

  @IsOptional()
  @IsUUID(undefined, { message: "Identifiant de fichier invalide" })
  avatarFileId?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(2000)
  bio?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: "L'expérience doit être un nombre d'années" })
  @Min(0)
  @Max(70)
  experienceYears?: number;
}

export class CreateProviderServiceBodyDto {
  @IsUUID(undefined, { message: "Type de service invalide" })
  serviceTypeId!: string;

  @IsString()
  @MinLength(3, { message: "Le titre doit contenir au moins 3 caractères" })
  @MaxLength(150)
  title!: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(1000)
  description?: string;
}

export class UpdateProviderServiceBodyDto {
  @IsOptional()
  @IsString()
  @MinLength(3)
  @MaxLength(150)
  title?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

/**
 * Corps de `PUT /providers/me/zones`.
 *
 * Une liste vide est acceptée : elle signifie « je ne couvre plus aucune
 * zone », ce qui est un choix légitime (arrêt temporaire d'activité). Le
 * prestataire disparaîtra alors des résultats de recherche, comme prévu au §7.
 */
export class ReplaceProviderZonesBodyDto {
  @IsArray()
  @ArrayUnique({ message: "La même zone est indiquée plusieurs fois" })
  @ArrayMaxSize(MAX_PROVIDER_ZONES, { message: `Pas plus de ${MAX_PROVIDER_ZONES} zones` })
  @IsUUID(undefined, { each: true, message: "Chaque zone doit être un identifiant valide" })
  zoneIds!: string[];
}

export class SubmitDocumentBodyDto {
  @IsString()
  @MinLength(2, { message: "Le type de document est obligatoire" })
  @MaxLength(60)
  type!: string;

  @IsUUID(undefined, { message: "Identifiant de fichier invalide" })
  fileId!: string;
}

export class CreatePortfolioItemBodyDto {
  @IsUUID(undefined, { message: "Identifiant de fichier invalide" })
  fileId!: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(120)
  title?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(100)
  displayOrder?: number;
}

export class UpdatePortfolioItemBodyDto {
  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(120)
  title?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(100)
  displayOrder?: number;
}
