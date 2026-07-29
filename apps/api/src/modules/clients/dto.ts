import { IsEnum, IsOptional, IsString, MaxLength, MinLength } from "class-validator";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { EmptyToUndefined } from "../../common/dto/transforms.js";
import { UserStatus } from "../users/user.types.js";

export class ClientListQueryDto extends PaginationQueryDto {
  @IsOptional()
  @EmptyToUndefined()
  @IsEnum(UserStatus, { message: "Statut d'utilisateur inconnu" })
  status?: UserStatus;

  @IsOptional()
  @EmptyToUndefined()
  @IsString()
  @MaxLength(120)
  search?: string;
}

export class AddClientNoteBodyDto {
  @IsString()
  @MinLength(2, { message: "La note ne peut pas être vide" })
  @MaxLength(2000)
  note!: string;
}
