import { ApiProperty } from "@nestjs/swagger";

/**
 * DTO de réponse du module missions (§8, §9, §10, §11, §12).
 *
 * Reflète `mission-booking.service.ts`, `mission-lifecycle.service.ts` et
 * `mission-reschedule.service.ts` tels qu'ils sont aujourd'hui.
 */

export class MissionClientRefDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true }) firstName!: string | null;
  @ApiProperty({ nullable: true }) lastName!: string | null;
}

export class MissionProviderRefDto {
  @ApiProperty() id!: string;
  @ApiProperty() publicName!: string;
  @ApiProperty({ required: false }) score?: number;
  @ApiProperty({ required: false }) reviewsCount?: number;
  @ApiProperty({ nullable: true }) avatarFileId!: string | null;
}

export class MissionPackRefDto {
  @ApiProperty() id!: string;
  @ApiProperty() title!: string;
  @ApiProperty() price!: number;
  @ApiProperty() durationMinutes!: number;
  @ApiProperty({ type: "object", additionalProperties: true })
  providerService?: Record<string, unknown>;
}

export class MissionAddressRefDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true }) label!: string | null;
  @ApiProperty({ nullable: true }) city!: string | null;
  @ApiProperty({ nullable: true }) commune!: string | null;
  @ApiProperty({ nullable: true }) details!: string | null;
  @ApiProperty({ nullable: true, required: false }) latitude?: number | null;
  @ApiProperty({ nullable: true, required: false }) longitude?: number | null;
}

export class MissionOptionRefDto {
  @ApiProperty() optionId!: string;
  @ApiProperty() title!: string;
  @ApiProperty() price!: number;
}

export class MissionCancellationRefDto {
  @ApiProperty() reason!: string;
  @ApiProperty({ nullable: true }) details!: string | null;
  @ApiProperty() late!: boolean;
  @ApiProperty() createdAt!: Date;
}

export class MissionThreadRefDto {
  @ApiProperty() id!: string;
  @ApiProperty() status!: string;
}

/** Réponse de `GET /missions/:id` et `POST /missions`. */
export class MissionDetailDto {
  @ApiProperty() id!: string;
  @ApiProperty({
    enum: ["draft", "pending_provider", "confirmed", "in_progress", "completed", "closed", "cancelled", "disputed"]
  })
  status!: string;
  @ApiProperty({ nullable: true }) scheduledAt!: Date | null;
  @ApiProperty({ nullable: true }) instructions!: string | null;
  @ApiProperty({ nullable: true, description: "Montant figé à la réservation" }) quotedAmount!: number | null;
  @ApiProperty() createdAt!: Date;
  @ApiProperty({ type: MissionClientRefDto }) client!: MissionClientRefDto;
  @ApiProperty({ type: MissionProviderRefDto, nullable: true }) provider!: MissionProviderRefDto | null;
  @ApiProperty({ type: MissionPackRefDto, nullable: true }) pack!: MissionPackRefDto | null;
  @ApiProperty({ type: [MissionOptionRefDto] }) options!: MissionOptionRefDto[];
  @ApiProperty({ type: MissionAddressRefDto, nullable: true }) address!: MissionAddressRefDto | null;
  @ApiProperty({ type: MissionThreadRefDto, nullable: true }) thread!: MissionThreadRefDto | null;
  @ApiProperty({ type: MissionCancellationRefDto, nullable: true }) cancellation!: MissionCancellationRefDto | null;
  @ApiProperty({ type: "array", items: { type: "object", additionalProperties: true }, description: "Reports en attente de réponse" })
  reschedules!: unknown[];
  @ApiProperty({ type: "array", items: { type: "object", additionalProperties: true } }) reviews!: unknown[];
}

/** Un élément de `GET /me/missions` ou `GET /providers/me/missions`. */
export class MissionListItemDto {
  @ApiProperty() id!: string;
  @ApiProperty() status!: string;
  @ApiProperty({ nullable: true }) scheduledAt!: Date | null;
  @ApiProperty({ nullable: true }) quotedAmount!: number | null;
  @ApiProperty({ nullable: true }) durationMinutes!: number | null;
  @ApiProperty({ nullable: true }) packTitle!: string | null;
  @ApiProperty({ nullable: true }) clientName!: string | null;
  @ApiProperty({ nullable: true }) providerId!: string | null;
  @ApiProperty({ nullable: true }) providerName!: string | null;
  @ApiProperty({ nullable: true }) providerAvatarFileId!: string | null;
  @ApiProperty({ nullable: true }) city!: string | null;
  @ApiProperty({ nullable: true }) commune!: string | null;
  @ApiProperty() createdAt!: Date;
}

/** Réponse commune des routes de transition (accept/refuse/start/complete/cancel). */
export class MissionTransitionResultDto {
  @ApiProperty() missionId!: string;
  @ApiProperty() previousStatus!: string;
  @ApiProperty() status!: string;
  @ApiProperty({ description: "true si une annulation a été acceptée moins de X heures avant l'horaire prévu" })
  late!: boolean;
}

/** Réponse de `POST /missions/:id/reschedule`. */
export class RescheduleRequestResultDto {
  @ApiProperty() id!: string;
  @ApiProperty() newScheduledAt!: Date;
  @ApiProperty({ nullable: true }) reason!: string | null;
  @ApiProperty({ enum: ["requested", "accepted", "rejected", "applied"] }) status!: string;
  @ApiProperty() createdAt!: Date;
}

/** Un élément de `GET /missions/:id/reschedules`. */
export class RescheduleListItemDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true }) oldScheduledAt!: Date | null;
  @ApiProperty() newScheduledAt!: Date;
  @ApiProperty({ nullable: true }) reason!: string | null;
  @ApiProperty({ enum: ["requested", "accepted", "rejected", "applied"] }) status!: string;
  @ApiProperty({ nullable: true }) createdBy!: string | null;
  @ApiProperty({ nullable: true }) decidedBy!: string | null;
  @ApiProperty({ nullable: true }) decidedAt!: Date | null;
  @ApiProperty({ nullable: true }) decisionReason!: string | null;
  @ApiProperty() createdAt!: Date;
}

/** Réponse de `POST /missions/:id/reschedule/:rid/accept`. */
export class RescheduleAcceptResultDto {
  @ApiProperty() id!: string;
  @ApiProperty({ enum: ["accepted"] }) status!: "accepted";
  @ApiProperty() scheduledAt!: Date;
}

/** Réponse de `POST /missions/:id/reschedule/:rid/reject`. */
export class RescheduleRejectResultDto {
  @ApiProperty() id!: string;
  @ApiProperty({ enum: ["rejected"] }) status!: "rejected";
}

/** Réponse de `POST /missions/:id/review`. */
export class ReviewSubmitResultDto {
  @ApiProperty() id!: string;
  @ApiProperty() rating!: number;
  @ApiProperty({ nullable: true }) comment!: string | null;
  @ApiProperty({ enum: ["published", "reported", "hidden", "rejected"] }) status!: string;
  @ApiProperty() createdAt!: Date;
}

/** Réponse de `GET /missions/:id/thread`. */
export class MissionThreadDto {
  @ApiProperty() id!: string;
  @ApiProperty() missionId!: string;
  @ApiProperty() status!: string;
  @ApiProperty() messageCount!: number;
  @ApiProperty() createdAt!: Date;
}

export class MissionStatusHistoryEntryDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true }) oldStatus!: string | null;
  @ApiProperty() newStatus!: string;
  @ApiProperty({ nullable: true }) reason!: string | null;
  @ApiProperty() createdAt!: Date;
}

export class MissionRescheduleHistoryEntryDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true }) oldScheduledAt!: Date | null;
  @ApiProperty() newScheduledAt!: Date;
  @ApiProperty({ nullable: true }) reason!: string | null;
  @ApiProperty() createdAt!: Date;
}

/** Réponse de `GET /missions/:id/history`. */
export class MissionHistoryDto {
  @ApiProperty({ type: [MissionStatusHistoryEntryDto] }) statusHistory!: MissionStatusHistoryEntryDto[];
  @ApiProperty({ type: [MissionRescheduleHistoryEntryDto] }) reschedules!: MissionRescheduleHistoryEntryDto[];
}
