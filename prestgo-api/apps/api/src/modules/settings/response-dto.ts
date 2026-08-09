import { ApiProperty } from "@nestjs/swagger";

/**
 * Réponse de `GET /settings/public` (§13).
 *
 * Chaque valeur est celle EN VIGUEUR : le réglage stocké en base s'il existe,
 * sa valeur de repli sinon (`SETTING_DEFAULT`). L'appelant n'a donc jamais à
 * gérer un champ absent.
 */
export class PublicSettingsDto {
  @ApiProperty({
    example: 60,
    description: "Délai minimum entre la réservation et l'intervention (mission.min_lead_time_minutes)"
  })
  missionMinLeadTimeMinutes!: number;

  @ApiProperty({
    example: 6,
    description: "En deçà de ce préavis, une annulation est marquée « tardive » (mission.cancellation_notice_hours)"
  })
  missionCancellationNoticeHours!: number;

  @ApiProperty({
    example: 120,
    description: "Avance maximale à laquelle le prestataire peut démarrer (mission.start_window_minutes)"
  })
  missionStartWindowMinutes!: number;

  @ApiProperty({
    example: 24,
    description: "Délai au bout duquel une demande sans réponse expire (mission.pending_expiry_hours)"
  })
  missionPendingExpiryHours!: number;

  @ApiProperty({
    example: 7,
    description: "Délai de clôture automatique d'une mission terminée (mission.auto_close_days)"
  })
  missionAutoCloseDays!: number;

  @ApiProperty({
    example: 14,
    description: "Fenêtre de dépôt d'un avis après la fin de la mission (reviews.window_days)"
  })
  reviewsWindowDays!: number;
}
