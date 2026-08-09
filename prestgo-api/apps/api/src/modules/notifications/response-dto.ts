import { ApiProperty } from "@nestjs/swagger";

/** DTO de réponse du module notifications/appareils (§12). */

/** Un élément de `GET /me/notifications`. */
export class MyNotificationDto {
  @ApiProperty() id!: string;
  @ApiProperty() type!: string;
  @ApiProperty() title!: string;
  @ApiProperty() body!: string;
  @ApiProperty({ type: "object", additionalProperties: true, nullable: true, description: "Données structurées (ex. missionId) pour ouvrir le bon écran" })
  data!: Record<string, unknown> | null;
  @ApiProperty({ nullable: true }) readAt!: Date | null;
  @ApiProperty() createdAt!: Date;
}

export class UnreadCountDto {
  @ApiProperty() unread!: number;
}

/** Réponse de `PATCH /me/notifications/:id/read` et `POST /me/notifications/read-all`. */
export class MarkReadResultDto {
  @ApiProperty({ description: "Nombre de notifications effectivement marquées lues" })
  updated!: number;
}

/** Un appareil, tel que renvoyé par `GET /me/devices` et `POST /me/devices`. */
export class DeviceDto {
  @ApiProperty() id!: string;
  @ApiProperty({ enum: ["android", "ios", "web"] }) platform!: string;
  @ApiProperty() active!: boolean;
  @ApiProperty() lastSeenAt!: Date;
  @ApiProperty({ required: false }) createdAt?: Date;
}

/** Réponse de `DELETE /me/devices/:token`. */
export class UnregisterDeviceResultDto {
  @ApiProperty() unregistered!: boolean;
}
