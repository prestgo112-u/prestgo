import { ApiProperty } from "@nestjs/swagger";

/** DTO de réponse des disponibilités prestataire (§6), reflétant `availability.service.ts`. */

/** Un créneau hebdomadaire, tel que renvoyé par `PUT /providers/me/availabilities`. */
export class ProviderAvailabilitySlotDto {
  @ApiProperty() id!: string;
  @ApiProperty() providerId!: string;
  @ApiProperty({ description: "0 = dimanche ... 6 = samedi" }) weekday!: number;
  @ApiProperty({ description: "Format HH:MM" }) startTime!: string;
  @ApiProperty({ description: "Format HH:MM" }) endTime!: string;
  @ApiProperty() active!: boolean;
  @ApiProperty() createdAt!: Date;
}

/** Une absence exceptionnelle, telle que renvoyée par `POST /providers/me/unavailabilities`. */
export class ProviderUnavailabilityDto {
  @ApiProperty() id!: string;
  @ApiProperty() providerId!: string;
  @ApiProperty() startAt!: Date;
  @ApiProperty() endAt!: Date;
  @ApiProperty({ nullable: true }) reason!: string | null;
  @ApiProperty() createdAt!: Date;
}

/** Réponse de `DELETE /providers/me/unavailabilities/:id`. */
export class RemovedUnavailabilityResultDto {
  @ApiProperty() removed!: boolean;
}
