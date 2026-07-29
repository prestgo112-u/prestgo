import { Type } from "class-transformer";
import {
  ArrayMaxSize,
  IsArray,
  IsDateString,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  ValidateNested
} from "class-validator";

// Format horaire attendu : « HH:MM » sur 24 heures (ex : « 09:00 », « 17:30 »).
const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;

export class CreateUnavailabilityBodyDto {
  @IsDateString({}, { message: "La date de début doit être au format ISO" })
  startAt!: string;

  @IsDateString({}, { message: "La date de fin doit être au format ISO" })
  endAt!: string;

  @IsOptional()
  @IsString()
  @MaxLength(300)
  reason?: string;
}

export class ReplaceAvailabilitiesBodyDto {
  // `@ValidateNested` + `@Type` sont indispensables : sans eux, chaque créneau
  // resterait un objet brut et ses propres règles ne seraient jamais vérifiées.
  @IsArray()
  @ArrayMaxSize(50, { message: "Un agenda hebdomadaire ne peut pas dépasser 50 créneaux" })
  @ValidateNested({ each: true })
  @Type(() => AvailabilitySlotDto)
  slots!: AvailabilitySlotDto[];
}

export class AvailabilitySlotDto {
  @Type(() => Number)
  @IsInt({ message: "Le jour doit être un entier" })
  @Min(0, { message: "Le jour va de 0 (dimanche) à 6 (samedi)" })
  @Max(6, { message: "Le jour va de 0 (dimanche) à 6 (samedi)" })
  weekday!: number;

  @Matches(TIME_PATTERN, { message: "L'heure de début doit être au format HH:MM" })
  startTime!: string;

  @Matches(TIME_PATTERN, { message: "L'heure de fin doit être au format HH:MM" })
  endTime!: string;
}

export class CreateAvailabilityBodyDto {
  @Type(() => Number)
  @IsInt({ message: "Le jour doit être un entier" })
  @Min(0, { message: "Le jour va de 0 (dimanche) à 6 (samedi)" })
  @Max(6, { message: "Le jour va de 0 (dimanche) à 6 (samedi)" })
  weekday!: number;

  @Matches(TIME_PATTERN, { message: "L'heure de début doit être au format HH:MM" })
  startTime!: string;

  @Matches(TIME_PATTERN, { message: "L'heure de fin doit être au format HH:MM" })
  endTime!: string;
}
