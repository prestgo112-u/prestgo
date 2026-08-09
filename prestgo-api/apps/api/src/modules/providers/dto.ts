import { ProviderValidationStatus } from "@prisma/client";
import { Type } from "class-transformer";
import { IsBoolean, IsEnum, IsInt, IsOptional, IsString, Max, MaxLength, Min, MinLength } from "class-validator";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { EmptyToUndefined } from "../../common/dto/transforms.js";

export class ProviderListQueryDto extends PaginationQueryDto {
  @IsOptional()
  @EmptyToUndefined()
  @IsEnum(ProviderValidationStatus, { message: "Statut de validation inconnu" })
  validationStatus?: ProviderValidationStatus;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(120)
  search?: string;
}

export class ProviderStatusChangeBodyDto {
  @IsEnum(ProviderValidationStatus, { message: "Statut de validation inconnu" })
  status!: ProviderValidationStatus;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}

export class AddProviderNoteBodyDto {
  @IsString()
  @MinLength(2, { message: "La note ne peut pas être vide" })
  @MaxLength(2000)
  note!: string;
}

export class ProviderUpdateBodyDto {
  @IsOptional()
  @IsString()
  @MaxLength(150)
  publicName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  bio?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: "Le nombre d'années d'expérience doit être un entier" })
  @Min(0)
  @Max(80)
  experienceYears?: number;

  // Bloque la re-soumission du dossier (§5). Volontairement côté admin
  // uniquement : le prestataire ne peut ni le lever ni le poser.
  @IsOptional()
  @IsBoolean()
  resubmissionBlocked?: boolean;
}
