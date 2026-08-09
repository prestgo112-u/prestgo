import { Type } from "class-transformer";
import {
  IsBoolean,
  IsEmail,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength
} from "class-validator";
import { EmptyToUndefined } from "../../common/dto/transforms.js";

export class UpdateProfileBodyDto {
  @IsOptional()
  @IsString()
  @MaxLength(80)
  firstName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  lastName?: string;

  @IsOptional()
  @IsEmail({}, { message: "Adresse email invalide" })
  email?: string;

  @IsOptional()
  @Matches(/^\+?[0-9\s-]{8,20}$/, { message: "Numéro de téléphone invalide" })
  phone?: string;
}

export class AddressBodyDto {
  @IsString()
  @MinLength(1, { message: "Le libellé est obligatoire" })
  @MaxLength(50)
  label!: string;

  @IsString()
  @MinLength(1, { message: "La ville est obligatoire" })
  @MaxLength(80)
  city!: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(80)
  commune?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(255)
  details?: string;

  // La géolocalisation est obligatoire : c'est elle qui permet de vérifier
  // qu'une adresse tombe dans la zone d'intervention d'un prestataire (§8).
  // Une adresse sans coordonnées rendrait la réservation impossible.
  @Type(() => Number)
  @IsLatitude({ message: "Latitude invalide" })
  latitude!: number;

  @Type(() => Number)
  @IsLongitude({ message: "Longitude invalide" })
  longitude!: number;

  @IsOptional()
  @IsBoolean()
  isDefault?: boolean;
}

export class UpdateAddressBodyDto {
  @IsOptional()
  @IsString()
  @MaxLength(50)
  label?: string;

  @IsOptional()
  @IsString()
  @MaxLength(80)
  city?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(80)
  commune?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(255)
  details?: string;

  @IsOptional()
  @Type(() => Number)
  @IsLatitude({ message: "Latitude invalide" })
  latitude?: number;

  @IsOptional()
  @Type(() => Number)
  @IsLongitude({ message: "Longitude invalide" })
  longitude?: number;
}

/**
 * Corps de `DELETE /me`.
 *
 * La désactivation d'un compte est irréversible côté utilisateur : on demande
 * une confirmation explicite plutôt qu'un simple appel DELETE, qu'un bouton mal
 * placé pourrait déclencher.
 */
export class DeleteAccountBodyDto {
  @IsString()
  @MinLength(1, { message: "Le mot de passe est obligatoire pour désactiver le compte" })
  password!: string;
}
