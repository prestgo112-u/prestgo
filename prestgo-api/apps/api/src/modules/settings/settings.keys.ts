/**
 * Clés de `system_settings` utilisées par la surface mobile (§13), avec leur
 * valeur de repli.
 *
 * Pourquoi les regrouper ici plutôt que d'écrire la chaîne à chaque appel : une
 * clé mal orthographiée dans un service passerait inaperçue — `getNumber()`
 * renverrait silencieusement la valeur de repli, et la règle métier serait
 * appliquée avec un délai que personne n'a choisi.
 *
 * Les valeurs de repli sont celles du §13 : elles s'appliquent tant que le
 * réglage n'a pas été semé, jamais pour contourner un réglage existant.
 */
export const SETTING = {
  providerRequiredDocumentTypes: "provider.required_document_types",
  missionMinLeadTimeMinutes: "mission.min_lead_time_minutes",
  missionCancellationNoticeHours: "mission.cancellation_notice_hours",
  missionStartWindowMinutes: "mission.start_window_minutes",
  missionPendingExpiryHours: "mission.pending_expiry_hours",
  missionAutoCloseDays: "mission.auto_close_days",
  reviewsWindowDays: "reviews.window_days"
} as const;

export const SETTING_DEFAULT = {
  providerRequiredDocumentTypes: ["id_card"],
  missionMinLeadTimeMinutes: 60,
  missionCancellationNoticeHours: 6,
  missionStartWindowMinutes: 120,
  missionPendingExpiryHours: 24,
  missionAutoCloseDays: 7,
  reviewsWindowDays: 14
} as const;

/** Nombre maximum d'adresses par client (§4). */
export const MAX_ADDRESSES_PER_USER = 10;

/** Nombre maximum de réalisations dans un portfolio (§6). */
export const MAX_PORTFOLIO_ITEMS = 20;

/** Nombre maximum de zones d'intervention par prestataire (§6). */
export const MAX_PROVIDER_ZONES = 15;
