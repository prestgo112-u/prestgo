import { ApiProperty } from "@nestjs/swagger";

/**
 * DTO de réponse des modules « espace prestataire » et « recherche » (§5, §6, §7).
 *
 * Reflète ce que les services renvoient aujourd'hui (`provider-self.service.ts`,
 * `provider-documents-self.service.ts`, `provider-search.service.ts`). Les
 * objets profondément imbriqués (services/packs/portfolio/disponibilités à
 * l'intérieur de la fiche publique) sont typés en objet générique plutôt qu'en
 * classes dédiées supplémentaires — le contrat de premier niveau, qui est ce
 * que l'audit vérifie, reste précis.
 */

export class ProviderChecklistDto {
  @ApiProperty() profile!: boolean;
  @ApiProperty() services!: boolean;
  @ApiProperty() zones!: boolean;
  @ApiProperty() availabilities!: boolean;
  @ApiProperty() documents!: boolean;
}

/** Réponse de `POST/GET/PATCH /providers/me` et `POST /providers/me/submit`. */
export class ProviderOverviewDto {
  @ApiProperty() id!: string;
  @ApiProperty() publicName!: string;
  @ApiProperty({ nullable: true }) bio!: string | null;
  @ApiProperty({ nullable: true }) experienceYears!: number | null;
  @ApiProperty({
    enum: ["profile_incomplete", "pending_review", "approved", "changes_requested", "rejected", "suspended"]
  })
  validationStatus!: string;
  @ApiProperty() availabilityStatus!: string;
  @ApiProperty() score!: number;
  @ApiProperty() reviewsCount!: number;
  @ApiProperty({ type: ProviderChecklistDto }) checklist!: ProviderChecklistDto;
  @ApiProperty({ type: [String] }) requiredDocumentTypes!: string[];
  @ApiProperty({ nullable: true }) rejectionReason!: string | null;
  @ApiProperty() resubmissionBlocked!: boolean;
  @ApiProperty({ nullable: true }) submittedAt!: Date | null;
  @ApiProperty({ description: "true seulement si la checklist est complète, le statut le permet, et la re-soumission n'est pas bloquée" })
  canSubmit!: boolean;
  @ApiProperty() createdAt!: Date;
}

/** Un service déclaré, tel que renvoyé par `GET /providers/me/services`. */
export class ProviderServiceListItemDto {
  @ApiProperty() id!: string;
  @ApiProperty() title!: string;
  @ApiProperty({ nullable: true }) description!: string | null;
  @ApiProperty() active!: boolean;
  @ApiProperty() createdAt!: Date;
  @ApiProperty({ type: "object", additionalProperties: true }) serviceType!: Record<string, unknown>;
  @ApiProperty({ type: "array", items: { type: "object", additionalProperties: true } }) packs!: unknown[];
}

/** Un service, tel que renvoyé par `POST/PATCH /providers/me/services` (forme brute Prisma). */
export class ProviderServiceDto {
  @ApiProperty() id!: string;
  @ApiProperty() providerId!: string;
  @ApiProperty() serviceTypeId!: string;
  @ApiProperty() title!: string;
  @ApiProperty({ nullable: true }) description!: string | null;
  @ApiProperty() active!: boolean;
  @ApiProperty() createdAt!: Date;
}

export class ProviderDocumentFileRefDto {
  @ApiProperty() id!: string;
  @ApiProperty() originalName!: string;
  @ApiProperty() mimeType!: string;
  @ApiProperty({ required: false }) size?: number;
}

export class ProviderDocumentDto {
  @ApiProperty() id!: string;
  @ApiProperty() type!: string;
  @ApiProperty({ enum: ["pending", "approved", "rejected"] }) status!: string;
  @ApiProperty() version!: number;
  @ApiProperty({ nullable: true, required: false }) rejectionReason?: string | null;
  @ApiProperty({ nullable: true, required: false }) reviewedAt?: Date | null;
  @ApiProperty() createdAt!: Date;
  @ApiProperty({ type: ProviderDocumentFileRefDto, required: false }) file?: ProviderDocumentFileRefDto;
}

/** Réponse de `GET /providers/me/documents`. */
export class ProviderDocumentsOverviewDto {
  @ApiProperty({ type: [String] }) requiredTypes!: string[];
  @ApiProperty({ type: [String], description: "Types requis sans justificatif exploitable (absent ou rejeté)" })
  missingTypes!: string[];
  @ApiProperty({ type: [ProviderDocumentDto], description: "Toutes les versions" }) documents!: ProviderDocumentDto[];
  @ApiProperty({ type: [ProviderDocumentDto], description: "La dernière version de chaque type" })
  current!: ProviderDocumentDto[];
}

export class ProviderZoneDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true }) latitude!: number | null;
  @ApiProperty({ nullable: true }) longitude!: number | null;
  @ApiProperty({ nullable: true }) radiusKm!: number | null;
  @ApiProperty() active!: boolean;
  @ApiProperty({ type: "object", additionalProperties: true, nullable: true }) city!: Record<string, unknown> | null;
}

/** Une réalisation, telle que renvoyée par `GET /providers/me/portfolio` (avec fichier). */
export class ProviderPortfolioItemListDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true }) title!: string | null;
  @ApiProperty({ nullable: true }) description!: string | null;
  @ApiProperty() displayOrder!: number;
  @ApiProperty() createdAt!: Date;
  @ApiProperty({ type: "object", additionalProperties: true }) file!: Record<string, unknown>;
}

/** Une réalisation, telle que renvoyée par `POST/PATCH /providers/me/portfolio` (forme brute Prisma). */
export class ProviderPortfolioItemDto {
  @ApiProperty() id!: string;
  @ApiProperty() providerId!: string;
  @ApiProperty() fileId!: string;
  @ApiProperty({ nullable: true }) title!: string | null;
  @ApiProperty({ nullable: true }) description!: string | null;
  @ApiProperty() displayOrder!: number;
  @ApiProperty() createdAt!: Date;
}

export class RemovedResultDto {
  @ApiProperty() removed!: boolean;
}

/** Un élément de `GET /providers/search`. */
export class ProviderSearchItemDto {
  @ApiProperty() id!: string;
  @ApiProperty() publicName!: string;
  @ApiProperty() score!: number;
  @ApiProperty() reviewsCount!: number;
  @ApiProperty({ nullable: true, description: "Distance en km jusqu'à la zone la plus proche ; null sans géoposition" })
  distanceKm!: number | null;
  @ApiProperty({ type: [String] }) categories!: string[];
  @ApiProperty({ nullable: true }) startingPrice!: number | null;
  @ApiProperty({ nullable: true }) avatarFileId!: string | null;
  @ApiProperty() availableNow!: boolean;
}

/** Fiche publique complète — `GET /providers/:id/public`. */
export class ProviderPublicProfileDto {
  @ApiProperty() id!: string;
  @ApiProperty() publicName!: string;
  @ApiProperty({ nullable: true }) bio!: string | null;
  @ApiProperty({ nullable: true }) experienceYears!: number | null;
  @ApiProperty({ nullable: true }) avatarFileId!: string | null;
  @ApiProperty() availableNow!: boolean;
  @ApiProperty() score!: number;
  @ApiProperty() reviewsCount!: number;
  @ApiProperty({ nullable: true }) startingPrice!: number | null;
  @ApiProperty({ type: "array", items: { type: "object", additionalProperties: true } }) categories!: unknown[];
  @ApiProperty({
    type: "array",
    items: { type: "object", additionalProperties: true },
    description: "Services actifs, avec leurs formules et options actives"
  })
  services!: unknown[];
  @ApiProperty({ type: "array", items: { type: "object", additionalProperties: true } }) portfolio!: unknown[];
  @ApiProperty({
    type: "array",
    items: { type: "object", additionalProperties: true },
    description: "Créneaux hebdomadaires actifs"
  })
  availability!: unknown[];
  @ApiProperty({
    type: "array",
    items: { type: "object", additionalProperties: true },
    description: "Absences exceptionnelles à venir"
  })
  upcomingUnavailabilities!: unknown[];
  @ApiProperty({ type: "array", items: { type: "object", additionalProperties: true } }) zones!: unknown[];
  @ApiProperty({ type: "object", additionalProperties: { type: "number" }, description: "Nombre d'avis par note, clés \"1\" à \"5\"" })
  ratingDistribution!: Record<string, number>;
  @ApiProperty({
    type: "array",
    items: { type: "object", additionalProperties: true },
    description: "5 avis les plus récents"
  })
  latestReviews!: unknown[];
  @ApiProperty() memberSince!: Date;
}
