import { MissionStatus } from "@prisma/client";
import {
  ArrayMaxSize,
  ArrayUnique,
  IsArray,
  IsDateString,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
  MinLength
} from "class-validator";
import { Type } from "class-transformer";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { EmptyToUndefined } from "../../common/dto/transforms.js";

/** Corps de `POST /missions` (§8). */
export class CreateMissionBodyDto {
  @IsUUID(undefined, { message: "Prestataire invalide" })
  providerId!: string;

  @IsUUID(undefined, { message: "Formule invalide" })
  packId!: string;

  @IsOptional()
  @IsArray()
  @ArrayUnique({ message: "La même option est indiquée plusieurs fois" })
  @ArrayMaxSize(10, { message: "Pas plus de 10 options" })
  @IsUUID(undefined, { each: true, message: "Chaque option doit être un identifiant valide" })
  optionIds?: string[];

  @IsDateString({}, { message: "La date doit être au format ISO (ex : 2026-08-02T09:00:00Z)" })
  scheduledAt!: string;

  @IsUUID(undefined, { message: "Adresse invalide" })
  addressId!: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(500, { message: "Les instructions ne peuvent pas dépasser 500 caractères" })
  instructions?: string;
}

/** Filtres de `GET /me/missions` et `GET /providers/me/missions`. */
export class MyMissionsQueryDto extends PaginationQueryDto {
  @IsOptional()
  @EmptyToUndefined()
  @IsEnum(MissionStatus, { message: "Statut de mission inconnu" })
  status?: MissionStatus;

  @IsOptional()
  @EmptyToUndefined()
  @IsDateString({}, { message: "« from » doit être au format AAAA-MM-JJ" })
  from?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsDateString({}, { message: "« to » doit être au format AAAA-MM-JJ" })
  to?: string;
}

/** Corps d'un refus ou d'une annulation : le motif est toujours exigé. */
export class MissionReasonBodyDto {
  @IsString()
  @MinLength(3, { message: "Un motif est obligatoire (au moins 3 caractères)" })
  @MaxLength(500)
  reason!: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(1000)
  details?: string;
}

/** Corps de `POST /missions/:id/reschedule` (§10). */
export class RequestRescheduleBodyDto {
  @IsDateString({}, { message: "La nouvelle date doit être au format ISO" })
  newDate!: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(500)
  reason?: string;
}

/** Corps de `POST /missions/:id/review` (§11). */
export class SubmitReviewBodyDto {
  @Type(() => Number)
  @IsInt({ message: "La note doit être un entier" })
  @Min(1, { message: "La note minimale est 1" })
  @Max(5, { message: "La note maximale est 5" })
  rating!: number;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(1000, { message: "Le commentaire ne peut pas dépasser 1000 caractères" })
  comment?: string;
}

/** Corps de `POST /reviews/:id/report` (§11). */
export class ReportReviewBodyDto {
  @IsString()
  @MinLength(3, { message: "Un motif de signalement est obligatoire" })
  @MaxLength(500)
  reason!: string;
}
