import { MissionStatus } from "@prisma/client";
import { IsDateString, IsEnum, IsOptional, IsString, IsUUID, MaxLength, MinLength } from "class-validator";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { EmptyToUndefined } from "../../common/dto/transforms.js";

export class MissionListQueryDto extends PaginationQueryDto {
  @IsOptional()
  @EmptyToUndefined()
  @IsEnum(MissionStatus, { message: "Statut de mission inconnu" })
  status?: MissionStatus;

  // Période sur la date d'intervention planifiée.
  @IsOptional()
  @EmptyToUndefined()
  @IsDateString({}, { message: "La date de début doit être au format AAAA-MM-JJ" })
  from?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsDateString({}, { message: "La date de fin doit être au format AAAA-MM-JJ" })
  to?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsUUID(undefined, { message: "providerId doit être un identifiant valide" })
  providerId?: string;

  // Recherche libre : nom ou email du client, nom public du prestataire, ville.
  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(120)
  search?: string;
}

export class MissionStatusChangeBodyDto {
  @IsEnum(MissionStatus, { message: "Statut de mission inconnu" })
  status!: MissionStatus;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}

export class MissionRescheduleBodyDto {
  // `@IsDateString` refuse une date mal formée avant même d'atteindre le service.
  @IsDateString({}, { message: "La nouvelle date doit être au format ISO (ex : 2026-08-01T09:00:00Z)" })
  scheduledAt!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}

export class MissionCancelBodyDto {
  // Règle métier CDC : une annulation exige toujours un motif.
  @IsString()
  @MinLength(3, { message: "Un motif d'annulation est obligatoire" })
  @MaxLength(500)
  reason!: string;
}
