import { DocumentStatus } from "@prisma/client";
import { IsEnum, IsOptional, IsString, MaxLength, MinLength } from "class-validator";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { EmptyToUndefined } from "../../common/dto/transforms.js";

export class VerificationQueueQueryDto extends PaginationQueryDto {
  // Par défaut la file montre les documents « en attente ».
  @IsOptional()
  @EmptyToUndefined()
  @IsEnum(DocumentStatus, { message: "Statut de document inconnu" })
  status?: DocumentStatus;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(120)
  search?: string;
}

export class RejectDocumentBodyDto {
  // Règle métier US2 : un rejet n'est jamais accepté sans motif.
  @IsString()
  @MinLength(3, { message: "Un motif de rejet est obligatoire" })
  @MaxLength(500)
  reason!: string;
}
