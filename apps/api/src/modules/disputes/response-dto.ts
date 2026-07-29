import { ApiProperty } from "@nestjs/swagger";

/**
 * DTO de réponse du module litiges (§6.2), pour les deux routes ouvertes aux
 * PARTIES d'une mission — `POST /disputes` et `GET /disputes/:id`.
 *
 * Chaque champ reflète exactement ce que `disputes.service.ts` renvoie
 * aujourd'hui. Les routes d'administration (`/admin/disputes/*`) renvoient des
 * formes voisines mais plus riches (nom du client, du prestataire, commentaires
 * internes) : elles ne sont pas modélisées ici.
 */

const DISPUTE_STATUSES = ["open", "in_review", "waiting_client", "waiting_provider", "resolved", "rejected", "closed"];

/**
 * Réponse de `POST /disputes` — la ligne `Dispute` brute, sans relation.
 *
 * Ni `messages` ni `files` : à l'ouverture, le litige n'en a aucun. Pour les
 * obtenir, appeler `GET /disputes/:id`.
 */
export class DisputeDto {
  @ApiProperty() id!: string;
  @ApiProperty() missionId!: string;
  @ApiProperty({ nullable: true, description: "Utilisateur à l'origine du litige" }) openedBy!: string | null;
  @ApiProperty() reason!: string;
  @ApiProperty({ nullable: true }) description!: string | null;
  @ApiProperty({ enum: DISPUTE_STATUSES }) status!: string;
  @ApiProperty({ nullable: true, description: "Agent de support en charge, null tant qu'aucun n'est assigné" })
  assignedTo!: string | null;
  @ApiProperty({ nullable: true, description: "Décision finale, renseignée à la résolution" })
  decision!: string | null;
  @ApiProperty() createdAt!: Date;
  @ApiProperty() updatedAt!: Date;
}

/**
 * Un message du fil d'un litige.
 *
 * `internalOnly` est toujours `false` sur `GET /disputes/:id` : les
 * commentaires réservés au back-office sont filtrés en amont par le service
 * (`includeInternal = false`). Le champ reste présent parce qu'il fait partie
 * de la ligne renvoyée.
 */
export class DisputeMessageDto {
  @ApiProperty() id!: string;
  @ApiProperty() disputeId!: string;
  @ApiProperty({ nullable: true }) senderId!: string | null;
  @ApiProperty() message!: string;
  @ApiProperty({ description: "Toujours false sur cette route" }) internalOnly!: boolean;
  @ApiProperty() createdAt!: Date;
}

/** Une pièce jointe de litige, aplatie par le service (le lien n'apparaît pas). */
export class DisputeFileDto {
  @ApiProperty() id!: string;
  @ApiProperty() originalName!: string;
  @ApiProperty() mimeType!: string;
  @ApiProperty({ nullable: true }) size!: number | null;
}

/** Réponse de `GET /disputes/:id` : le litige, son fil et ses preuves. */
export class DisputeDetailDto extends DisputeDto {
  @ApiProperty({ type: [DisputeMessageDto], description: "Messages visibles des parties, du plus ancien au plus récent" })
  messages!: DisputeMessageDto[];

  @ApiProperty({ type: [DisputeFileDto], description: "Pièces jointes, à lire via GET /files/:id/content" })
  files!: DisputeFileDto[];
}
