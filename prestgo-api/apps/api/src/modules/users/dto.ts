import { ArrayUnique, IsArray, IsEnum, IsOptional, IsString, IsUUID, MaxLength, MinLength } from "class-validator";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { EmptyToUndefined } from "../../common/dto/transforms.js";
import { UserStatus } from "./user.types.js";

export class UserListQueryDto extends PaginationQueryDto {
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

export class AddUserNoteBodyDto {
  @IsString()
  @MinLength(2, { message: "La note ne peut pas être vide" })
  @MaxLength(2000)
  note!: string;
}

export class SetUserRolesBodyDto {
  @IsArray()
  @ArrayUnique()
  @IsUUID(undefined, { each: true, message: "Chaque rôle doit être un identifiant valide" })
  roleIds!: string[];
}

export class UpdateUserStatusBodyDto {
  @IsEnum(UserStatus, { message: "Statut d'utilisateur inconnu" })
  status!: UserStatus;

  // Un changement de statut est une action sensible : le motif est exigé
  // pour que le journal d'audit reste exploitable.
  @IsString()
  @MinLength(3, { message: "Le motif doit contenir au moins 3 caractères" })
  @MaxLength(500)
  reason!: string;
}
