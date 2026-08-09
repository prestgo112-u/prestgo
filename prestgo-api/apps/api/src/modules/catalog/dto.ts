import { Type } from "class-transformer";
import { IsBoolean, IsInt, IsNumber, IsOptional, IsString, IsUUID, Matches, Max, MaxLength, Min, MinLength } from "class-validator";

// Un « slug » est l'identifiant lisible utilisé dans les URL : uniquement des
// minuscules, des chiffres et des tirets (ex : « menage-a-domicile »).
const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const SLUG_MESSAGE = "Le slug ne peut contenir que des minuscules, des chiffres et des tirets";

export class CreateCategoryBodyDto {
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name!: string;

  @IsString()
  @Matches(SLUG_PATTERN, { message: SLUG_MESSAGE })
  @MaxLength(120)
  slug!: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  displayOrder?: number;
}

export class UpdateCategoryBodyDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  displayOrder?: number;
}

export class CreateServiceTypeBodyDto {
  @IsUUID(undefined, { message: "categoryId doit être un identifiant valide" })
  categoryId!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name!: string;

  @IsString()
  @Matches(SLUG_PATTERN, { message: SLUG_MESSAGE })
  @MaxLength(120)
  slug!: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;
}

export class UpdateServiceTypeBodyDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

export class CreateServicePackBodyDto {
  @IsUUID(undefined, { message: "providerServiceId doit être un identifiant valide" })
  providerServiceId!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(150)
  title!: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @Type(() => Number)
  @IsNumber({}, { message: "Le prix doit être un nombre" })
  @Min(0, { message: "Le prix ne peut pas être négatif" })
  price!: number;

  @Type(() => Number)
  @IsInt({ message: "La durée doit être un nombre entier de minutes" })
  @Min(5, { message: "La durée minimale est de 5 minutes" })
  @Max(1440, { message: "La durée ne peut pas dépasser une journée (1440 minutes)" })
  durationMinutes!: number;
}

export class UpdateServicePackBodyDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(150)
  title?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber({}, { message: "Le prix doit être un nombre" })
  @Min(0, { message: "Le prix ne peut pas être négatif" })
  price?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: "La durée doit être un nombre entier de minutes" })
  @Min(5)
  @Max(1440)
  durationMinutes?: number;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

export class AttachProviderServiceBodyDto {
  @IsUUID(undefined, { message: "providerId doit être un identifiant valide" })
  providerId!: string;

  @IsUUID(undefined, { message: "serviceTypeId doit être un identifiant valide" })
  serviceTypeId!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(150)
  title!: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  description?: string;
}

/**
 * Option payante ajoutable à une formule (§8 : `optionIds`).
 *
 * `durationMinutes` est facultative et vaut zéro par défaut : beaucoup
 * d'options (fournitures, garantie étendue) coûtent de l'argent sans rallonger
 * l'intervention.
 */
export class CreateServicePackOptionBodyDto {
  @IsString()
  @MinLength(2)
  @MaxLength(150)
  title!: string;

  @Type(() => Number)
  @IsNumber({}, { message: "Le prix doit être un nombre" })
  @Min(0, { message: "Le prix ne peut pas être négatif" })
  price!: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt({ message: "La durée doit être un nombre entier de minutes" })
  @Min(0)
  @Max(1440, { message: "La durée ne peut pas dépasser une journée (1440 minutes)" })
  durationMinutes?: number;
}

export class UpdateServicePackOptionBodyDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(150)
  title?: string;

  @IsOptional()
  @Type(() => Number)
  @IsNumber({}, { message: "Le prix doit être un nombre" })
  @Min(0)
  price?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  @Max(1440)
  durationMinutes?: number;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}
