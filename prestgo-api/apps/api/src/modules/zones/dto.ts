import { Type } from "class-transformer";
import { IsBoolean, IsLatitude, IsLongitude, IsNumber, IsOptional, IsString, Max, MaxLength, Min, MinLength } from "class-validator";

export class NearbyZonesQueryDto {
  @Type(() => Number)
  @IsLatitude({ message: "La latitude doit être comprise entre -90 et 90" })
  latitude!: number;

  @Type(() => Number)
  @IsLongitude({ message: "La longitude doit être comprise entre -180 et 180" })
  longitude!: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber({}, { message: "Le rayon doit être un nombre" })
  @Min(0.1, { message: "Le rayon doit être d'au moins 100 mètres" })
  @Max(500, { message: "Le rayon ne peut pas dépasser 500 km" })
  radiusKm?: number;
}

export class CreateZoneBodyDto {
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name!: string;

  @IsOptional()
  @IsString()
  @MaxLength(120)
  cityId?: string;

  @IsOptional()
  @Type(() => Number)
  @IsLatitude({ message: "La latitude doit être comprise entre -90 et 90" })
  latitude?: number;

  @IsOptional()
  @Type(() => Number)
  @IsLongitude({ message: "La longitude doit être comprise entre -180 et 180" })
  longitude?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber({}, { message: "Le rayon doit être un nombre" })
  @Min(0)
  @Max(500)
  radiusKm?: number;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}

export class UpdateZoneBodyDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name?: string;

  @IsOptional()
  @Type(() => Number)
  @IsLatitude({ message: "La latitude doit être comprise entre -90 et 90" })
  latitude?: number;

  @IsOptional()
  @Type(() => Number)
  @IsLongitude({ message: "La longitude doit être comprise entre -180 et 180" })
  longitude?: number;

  @IsOptional()
  @Type(() => Number)
  @IsNumber({}, { message: "Le rayon doit être un nombre" })
  @Min(0)
  @Max(500)
  radiusKm?: number;

  @IsOptional()
  @IsBoolean()
  active?: boolean;
}
