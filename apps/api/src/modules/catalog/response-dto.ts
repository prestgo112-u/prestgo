import { ApiProperty } from "@nestjs/swagger";

/** DTO de réponse des formules et options du prestataire (§8), reflétant `catalog.service.ts`. */

/** Réponse de `POST/PATCH /providers/me/service-packs*` (forme brute Prisma). */
export class ServicePackDto {
  @ApiProperty() id!: string;
  @ApiProperty() providerServiceId!: string;
  @ApiProperty() title!: string;
  @ApiProperty({ nullable: true }) description!: string | null;
  @ApiProperty() price!: number;
  @ApiProperty() durationMinutes!: number;
  @ApiProperty() active!: boolean;
  @ApiProperty() createdAt!: Date;
}

/** Un élément de `GET /providers/me/service-packs/:packId/options`. */
export class ServicePackOptionListItemDto {
  @ApiProperty() id!: string;
  @ApiProperty() title!: string;
  @ApiProperty() price!: number;
  @ApiProperty() durationMinutes!: number;
  @ApiProperty() active!: boolean;
  @ApiProperty() createdAt!: Date;
}

/** Réponse de `POST /providers/me/service-packs/:packId/options` et `PATCH /providers/me/service-pack-options/:id` (forme brute Prisma). */
export class ServicePackOptionDto {
  @ApiProperty() id!: string;
  @ApiProperty() packId!: string;
  @ApiProperty() title!: string;
  @ApiProperty() price!: number;
  @ApiProperty() durationMinutes!: number;
  @ApiProperty() active!: boolean;
  @ApiProperty() createdAt!: Date;
}
