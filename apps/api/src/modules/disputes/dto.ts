import { DisputeStatus } from "@prisma/client";
import { IsBoolean, IsEnum, IsOptional, IsString, IsUUID, MaxLength, MinLength } from "class-validator";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { EmptyToUndefined } from "../../common/dto/transforms.js";

export class DisputeListQueryDto extends PaginationQueryDto {
  @IsOptional()
  @EmptyToUndefined()
  @IsEnum(DisputeStatus, { message: "Statut de litige inconnu" })
  status?: DisputeStatus;

  @IsOptional()
  @EmptyToUndefined()
  @IsUUID(undefined, { message: "assignedTo doit être un identifiant d'agent valide" })
  assignedTo?: string;

  // Recherche dans le motif et la description.
  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(120)
  search?: string;
}

export class OpenDisputeBodyDto {
  @IsUUID(undefined, { message: "missionId doit être un identifiant valide" })
  missionId!: string;

  @IsString()
  @MinLength(3, { message: "Le motif est obligatoire" })
  @MaxLength(300)
  reason!: string;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  description?: string;
}

export class AssignDisputeBodyDto {
  @IsUUID(undefined, { message: "assignedTo doit être un identifiant d'agent valide" })
  assignedTo!: string;
}

export class DisputeStatusChangeBodyDto {
  @IsEnum(DisputeStatus, { message: "Statut de litige inconnu" })
  status!: DisputeStatus;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;

  // La décision est exigée sur les statuts de clôture ; cette règle métier
  // reste dans le service, ici on ne vérifie que la forme.
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  decision?: string;
}

export class DisputeMessageBodyDto {
  @IsString()
  @MinLength(1, { message: "Le message ne peut pas être vide" })
  @MaxLength(4000)
  message!: string;

  // `true` = commentaire réservé au back-office, invisible du client et du
  // prestataire (CDC §4.5). Par défaut le message est visible des parties.
  @IsOptional()
  @IsBoolean()
  internalOnly?: boolean;
}

export class AttachDisputeFileBodyDto {
  @IsUUID(undefined, { message: "fileId doit être un identifiant valide" })
  fileId!: string;
}
