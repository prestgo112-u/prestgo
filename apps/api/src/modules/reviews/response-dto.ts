import { ApiProperty } from "@nestjs/swagger";

/** DTO de réponse du module avis (§11), reflétant `review-submission.service.ts`. */

export class MyReviewMissionProviderRefDto {
  @ApiProperty() id!: string;
  @ApiProperty() publicName!: string;
  @ApiProperty({ nullable: true }) avatarFileId!: string | null;
}

export class MyReviewMissionRefDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true }) scheduledAt!: Date | null;
  @ApiProperty({ type: MyReviewMissionProviderRefDto, nullable: true }) provider!: MyReviewMissionProviderRefDto | null;
}

/** Un élément de `GET /me/reviews`. */
export class MyReviewListItemDto {
  @ApiProperty() id!: string;
  @ApiProperty() rating!: number;
  @ApiProperty({ nullable: true }) comment!: string | null;
  @ApiProperty({ enum: ["published", "reported", "hidden", "rejected"] }) status!: string;
  @ApiProperty() createdAt!: Date;
  @ApiProperty({ type: MyReviewMissionRefDto }) mission!: MyReviewMissionRefDto;
}

/** Réponse de `POST /reviews/:id/report`. */
export class ReportReviewResultDto {
  @ApiProperty() reported!: boolean;
}

/**
 * Un élément de `GET /providers/:id/reviews` — la liste publique des avis
 * PUBLIÉS d'un prestataire.
 *
 * Volontairement anonyme : le service ne sélectionne ni l'auteur ni la mission.
 * Le prénom de l'auteur n'apparaît que sur les cinq derniers avis de la fiche
 * publique (`GET /providers/:id/public` → `latestReviews[].authorFirstName`).
 *
 * Le statut n'est pas exposé non plus : par construction, seuls les avis
 * `published` sortent d'ici.
 */
export class PublicReviewDto {
  @ApiProperty() id!: string;
  @ApiProperty({ minimum: 1, maximum: 5 }) rating!: number;
  @ApiProperty({ nullable: true }) comment!: string | null;
  @ApiProperty() createdAt!: Date;
}
