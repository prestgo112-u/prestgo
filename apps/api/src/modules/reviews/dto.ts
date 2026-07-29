import { ReviewStatus } from "@prisma/client";
import { IsEnum, IsOptional, IsString, MaxLength } from "class-validator";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { EmptyToUndefined } from "../../common/dto/transforms.js";

export class ReviewListQueryDto extends PaginationQueryDto {
  @IsOptional()
  @EmptyToUndefined()
  @IsEnum(ReviewStatus, { message: "Statut d'avis inconnu" })
  status?: ReviewStatus;
}

export class ReviewStatusChangeBodyDto {
  @IsEnum(ReviewStatus, { message: "Statut d'avis inconnu" })
  status!: ReviewStatus;

  // Le caractère obligatoire du motif (masquage / rejet) est une règle métier
  // vérifiée dans le service.
  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}
