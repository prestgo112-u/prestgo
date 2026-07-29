import { ApiProperty } from "@nestjs/swagger";

/**
 * DTO de réponse du module fichiers, reflétant `files.controller.ts`.
 *
 * Les trois routes qui renvoient du JSON (`POST /files/upload`,
 * `GET /files/:id`, `DELETE /files/:id`) renvoient toutes la ligne `File`
 * BRUTE de Prisma — d'où un seul DTO.
 *
 * `GET /files/:id/content` n'est pas concernée : elle renvoie le binaire du
 * fichier, hors enveloppe.
 */
export class FileDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true, description: "Compte propriétaire ; null pour un fichier produit par le système" })
  ownerId!: string | null;
  @ApiProperty() originalName!: string;
  @ApiProperty() mimeType!: string;
  @ApiProperty({ description: "Taille en octets" }) size!: number;
  @ApiProperty({ description: "Clé de stockage interne, calculée par le serveur" }) storageKey!: string;
  @ApiProperty({
    enum: ["public", "authenticated", "restricted", "sensitive"],
    description:
      "Seules `restricted` et `sensitive` peuvent être demandées à l'envoi. " +
      "`public` est posée par le serveur quand le fichier devient un avatar ou une réalisation de portfolio."
  })
  visibility!: string;
  @ApiProperty() createdAt!: Date;
  @ApiProperty({ nullable: true, description: "Renseignée quand le fichier a été désactivé ; il n'est alors plus lisible" })
  disabledAt!: Date | null;
}
