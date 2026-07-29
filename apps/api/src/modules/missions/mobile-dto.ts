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
import { Transform, Type } from "class-transformer";
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
  /**
   * Un statut, ou plusieurs séparés par des virgules (`?status=completed,closed`).
   *
   * Les onglets de l'application ne correspondent pas un pour un aux statuts :
   * « Terminées » couvre `completed` ET `closed`, « À venir » couvre
   * `pending_provider` ET `confirmed`. Avec un filtre scalaire, chaque onglet
   * imposait soit deux appels, soit le chargement de toutes les missions puis
   * un regroupement côté client — c'est-à-dire une pagination fausse.
   *
   * La forme scalaire reste valable : `?status=confirmed` donne toujours
   * exactement le même résultat qu'avant.
   */
  @IsOptional()
  @EmptyToUndefined()
  @Transform(({ value }) =>
    typeof value === "string"
      ? value
          .split(",")
          .map((item) => item.trim())
          .filter(Boolean)
      : value
  )
  @IsEnum(MissionStatus, { each: true, message: "Statut de mission inconnu" })
  status?: MissionStatus | MissionStatus[];

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
