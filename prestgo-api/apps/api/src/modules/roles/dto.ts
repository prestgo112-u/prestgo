import { ArrayUnique, IsArray, IsOptional, IsString, IsUUID, Matches, MaxLength, MinLength } from "class-validator";

// Un code de rôle sert d'identifiant technique : minuscules et underscores
// uniquement (ex : « agent_validation »).
const ROLE_CODE_PATTERN = /^[a-z][a-z0-9_]*$/;

export class CreateRoleBodyDto {
  @IsString()
  @Matches(ROLE_CODE_PATTERN, {
    message: "Le code du rôle ne peut contenir que des minuscules, des chiffres et des underscores"
  })
  @MaxLength(60)
  code!: string;

  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsArray()
  @ArrayUnique()
  @IsUUID(undefined, { each: true, message: "Chaque permission doit être un identifiant valide" })
  permissionIds?: string[];
}

export class UpdateRoleBodyDto {
  @IsOptional()
  @IsString()
  @MinLength(2)
  @MaxLength(120)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsArray()
  @ArrayUnique()
  @IsUUID(undefined, { each: true, message: "Chaque permission doit être un identifiant valide" })
  permissionIds?: string[];
}

export class AssignPermissionsBodyDto {
  @IsArray()
  @ArrayUnique()
  @IsUUID(undefined, { each: true, message: "Chaque permission doit être un identifiant valide" })
  permissionIds!: string[];
}
