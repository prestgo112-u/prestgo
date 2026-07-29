import { IsOptional, IsString, MaxLength } from "class-validator";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { EmptyToUndefined } from "../../common/dto/transforms.js";

export class AuditListQueryDto extends PaginationQueryDto {
  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(80)
  entity?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(120)
  action?: string;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(60)
  actorId?: string;
}
