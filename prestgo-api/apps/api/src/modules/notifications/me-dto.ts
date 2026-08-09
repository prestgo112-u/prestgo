import { Transform } from "class-transformer";
import { IsBoolean, IsIn, IsOptional, IsString, MaxLength, MinLength } from "class-validator";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { DEVICE_PLATFORMS } from "./devices.service.js";

export class MyNotificationsQueryDto extends PaginationQueryDto {
  /**
   * `?unread=true` ne filtre que les non-lues.
   *
   * La conversion explicite est nécessaire : dans une URL, tout arrive sous
   * forme de texte, et `Boolean("false")` vaut `true`.
   */
  @IsOptional()
  @Transform(({ value }) => (value === "true" || value === true ? true : value === "false" || value === false ? false : value))
  @IsBoolean({ message: "« unread » doit valoir true ou false" })
  unread?: boolean;
}

export class RegisterDeviceBodyDto {
  @IsIn(DEVICE_PLATFORMS, { message: `Plateforme acceptée : ${DEVICE_PLATFORMS.join(", ")}` })
  platform!: (typeof DEVICE_PLATFORMS)[number];

  @IsString()
  @MinLength(10, { message: "Jeton d'appareil invalide" })
  @MaxLength(512)
  token!: string;
}
