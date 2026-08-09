import { ApiProperty } from "@nestjs/swagger";

/**
 * DTO de réponse des zones publiques (§7), reflétant `zones.service.ts`.
 *
 * Une zone est un disque : un centre (`latitude`, `longitude`) et un rayon
 * (`radiusKm`). C'est ce disque qui décide si une adresse tombe dans le
 * périmètre d'un prestataire à la réservation.
 */

/** Ville de rattachement d'une zone. */
export class ZoneCityDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty() slug!: string;
}

/**
 * Un élément de `GET /zones` — les zones ACTIVES uniquement.
 *
 * `active` n'est pas renvoyé : le service ne le sélectionne pas, puisque par
 * construction toutes les zones listées ici sont actives.
 */
export class PublicZoneDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true }) latitude!: number | null;
  @ApiProperty({ nullable: true }) longitude!: number | null;
  @ApiProperty({ nullable: true, description: "Rayon couvert, en kilomètres" }) radiusKm!: number | null;
  @ApiProperty({ type: ZoneCityDto, nullable: true }) city!: ZoneCityDto | null;
}

/**
 * Un élément de `GET /zones/nearby` — même forme, plus la distance calculée.
 *
 * Les zones sont triées de la plus proche à la plus lointaine, et celles dont
 * le centre dépasse le rayon demandé sont écartées.
 */
export class NearbyZoneDto extends PublicZoneDto {
  @ApiProperty({ description: "Distance entre le point demandé et le CENTRE de la zone, en kilomètres" })
  distanceKm!: number;
}
