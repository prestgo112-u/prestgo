import { ApiProperty } from "@nestjs/swagger";

/** DTO de réponse du module messages/conversations (§12). */

export class MessageFileRefDto {
  @ApiProperty() id!: string;
  @ApiProperty() originalName!: string;
  @ApiProperty() mimeType!: string;
  @ApiProperty({ required: false }) size?: number;
}

export class MessageAttachmentDto {
  @ApiProperty({ type: MessageFileRefDto }) file!: MessageFileRefDto;
}

/** Un message, tel que renvoyé par `GET/POST /messages/threads/:id/messages`. */
export class MessageDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true }) senderId!: string | null;
  @ApiProperty() message!: string;
  @ApiProperty() createdAt!: Date;
  @ApiProperty({ nullable: true, required: false }) readAt?: Date | null;
  @ApiProperty({ type: [MessageAttachmentDto] }) files!: MessageAttachmentDto[];
}

export class LastMessageRefDto {
  @ApiProperty() id!: string;
  @ApiProperty() message!: string;
  @ApiProperty({ nullable: true }) senderId!: string | null;
  @ApiProperty() createdAt!: Date;
}

/** Un élément de `GET /me/threads`. */
export class MyThreadListItemDto {
  @ApiProperty() id!: string;
  @ApiProperty() missionId!: string;
  @ApiProperty() missionStatus!: string;
  @ApiProperty({ nullable: true }) scheduledAt!: Date | null;
  @ApiProperty() status!: string;
  @ApiProperty() counterpartName!: string;
  @ApiProperty({ nullable: true }) counterpartAvatarFileId!: string | null;
  @ApiProperty({ type: LastMessageRefDto, nullable: true }) lastMessage!: LastMessageRefDto | null;
  @ApiProperty() unreadCount!: number;
  @ApiProperty() createdAt!: Date;
}

/** Réponse de `PATCH /messages/threads/:id/read`. */
export class MarkThreadReadResultDto {
  @ApiProperty({ description: "Nombre de messages effectivement marqués lus" })
  updated!: number;
}
