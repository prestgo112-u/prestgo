import { ArrayMaxSize, ArrayUnique, IsArray, IsOptional, IsString, IsUUID, MaxLength, MinLength } from "class-validator";

export class SendMessageBodyDto {
  @IsString()
  @MinLength(1, { message: "Le message ne peut pas être vide" })
  @MaxLength(4000)
  message!: string;

  /**
   * Pièces jointes (§12).
   *
   * Le fichier est d'abord envoyé par `POST /files/upload`, puis rattaché ici —
   * même découpage que pour les justificatifs prestataire : l'application gère
   * l'envoi (progression, reprise) indépendamment de la règle métier.
   *
   * Trois au maximum : au-delà, c'est un partage de dossier, pas une
   * conversation.
   */
  @IsOptional()
  @IsArray()
  @ArrayUnique({ message: "Le même fichier est joint plusieurs fois" })
  @ArrayMaxSize(3, { message: "Pas plus de 3 pièces jointes par message" })
  @IsUUID(undefined, { each: true, message: "Chaque pièce jointe doit être un identifiant de fichier valide" })
  fileIds?: string[];
}
