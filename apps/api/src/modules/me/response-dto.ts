import { ApiProperty } from "@nestjs/swagger";

/**
 * DTO de réponse du module `me` (§3, §4).
 *
 * Chaque classe reflète exactement ce que le service renvoie aujourd'hui
 * (voir `me.service.ts`, `addresses.service.ts`, `favorites.service.ts`) —
 * aucun champ n'est inventé ni réorganisé pour « mieux coller » à un idéal.
 */

export class MeProfileDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true }) firstName!: string | null;
  @ApiProperty({ nullable: true }) lastName!: string | null;
  @ApiProperty({ nullable: true }) email!: string | null;
  @ApiProperty({ nullable: true }) phone!: string | null;
  @ApiProperty({ enum: ["draft", "pending", "active", "rejected", "suspended", "deleted"] }) status!: string;
  @ApiProperty() emailVerified!: boolean;
  @ApiProperty() phoneVerified!: boolean;
  @ApiProperty({ type: [String] }) roles!: string[];
  @ApiProperty() hasClientProfile!: boolean;
  @ApiProperty() hasProviderProfile!: boolean;
  @ApiProperty({ nullable: true }) providerId!: string | null;
  @ApiProperty({
    nullable: true,
    enum: ["profile_incomplete", "pending_review", "approved", "changes_requested", "rejected", "suspended"]
  })
  providerValidationStatus!: string | null;
  @ApiProperty() createdAt!: Date;
}

export class PendingVerificationDto {
  @ApiProperty({ enum: ["email", "sms"] }) channel!: string;
  @ApiProperty() target!: string;
}

/** Réponse de `PATCH /me` : le profil à jour, plus les vérifications déclenchées. */
export class UpdateProfileResultDto extends MeProfileDto {
  @ApiProperty({ type: [PendingVerificationDto] }) pendingVerifications!: PendingVerificationDto[];
}

/** Réponse de `POST /me/password`. */
export class ChangePasswordResultDto {
  @ApiProperty({ description: "Nombre d'autres sessions fermées par ce changement" })
  revokedSessions!: number;
}

/** Réponse de `DELETE /me`. */
export class DeactivateAccountResultDto {
  @ApiProperty({ enum: ["deleted"] }) status!: "deleted";
}

/**
 * Une adresse du carnet (§4).
 *
 * `userId` n'apparaît que sur les réponses de création/modification (le
 * service ne le sélectionne pas explicitement sur la liste) ; marqué
 * facultatif pour refléter fidèlement cette petite différence sans
 * fragmenter en plusieurs DTOs quasi identiques.
 */
export class AddressDto {
  @ApiProperty() id!: string;
  @ApiProperty({ required: false }) userId?: string;
  @ApiProperty({ nullable: true }) label!: string | null;
  @ApiProperty({ nullable: true }) city!: string | null;
  @ApiProperty({ nullable: true }) commune!: string | null;
  @ApiProperty({ nullable: true }) details!: string | null;
  @ApiProperty({ nullable: true }) latitude!: number | null;
  @ApiProperty({ nullable: true }) longitude!: number | null;
  @ApiProperty() isDefault!: boolean;
  @ApiProperty() createdAt!: Date;
}

/** Réponse de `DELETE /me/addresses/:id` : suppression réelle ou archivage. */
export class RemoveAddressResultDto {
  @ApiProperty() removed!: boolean;
  @ApiProperty() archived!: boolean;
  @ApiProperty({ required: false }) reason?: string;
}

/** Un prestataire en favori, tel que renvoyé par `GET /me/favorites`. */
export class FavoriteProviderDto {
  @ApiProperty() id!: string;
  @ApiProperty() publicName!: string;
  @ApiProperty({ nullable: true }) bio!: string | null;
  @ApiProperty() score!: number;
  @ApiProperty() reviewsCount!: number;
  @ApiProperty({ type: [String] }) categories!: string[];
  @ApiProperty({ description: "Validé ET non suspendu — un favori suspendu reste listé avec available: false" })
  available!: boolean;
  @ApiProperty() favoritedAt!: Date;
}

/** Réponse de `POST/DELETE /me/favorites/:providerId` (idempotents). */
export class FavoriteActionResultDto {
  @ApiProperty() favorited!: boolean;
}
