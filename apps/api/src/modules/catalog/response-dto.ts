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

/** Un type de service ACTIF, imbriqué dans `GET /categories`. */
export class PublicServiceTypeDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty() slug!: string;
  @ApiProperty({ nullable: true }) description!: string | null;
}

/**
 * Un élément de `GET /categories` — la vitrine du catalogue.
 *
 * Forme brute Prisma de `CatalogCategory`, avec ses types de service actifs
 * imbriqués. Seules les catégories actives sortent, et à l'intérieur, seuls
 * les types de service actifs.
 */
export class PublicCategoryDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty() slug!: string;
  @ApiProperty({ nullable: true }) description!: string | null;
  @ApiProperty({ nullable: true, description: "Icône à lire via GET /files/:id/content" })
  iconFileId!: string | null;
  @ApiProperty() active!: boolean;
  @ApiProperty() displayOrder!: number;
  @ApiProperty() createdAt!: Date;
  @ApiProperty() updatedAt!: Date;
  @ApiProperty({ type: [PublicServiceTypeDto] }) serviceTypes!: PublicServiceTypeDto[];
}

/**
 * Un élément de `GET /providers/:id/service-packs` — la vitrine tarifaire.
 *
 * Le service APLATIT la relation : le service porteur n'apparaît pas en objet
 * imbriqué mais par ses trois champs `serviceId`, `serviceTitle` et
 * `serviceType`. Ni `active` ni `createdAt` ne sortent : par construction,
 * seules les formules actives sont listées.
 */
export class PublicServicePackDto {
  @ApiProperty() id!: string;
  @ApiProperty() title!: string;
  @ApiProperty({ nullable: true }) description!: string | null;
  @ApiProperty() price!: number;
  @ApiProperty() durationMinutes!: number;
  @ApiProperty() serviceId!: string;
  @ApiProperty() serviceTitle!: string;
  @ApiProperty({ description: "Nom du type de service (ex. « Réparation de fuite »)" }) serviceType!: string;
}
