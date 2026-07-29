import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import { SETTING, SETTING_DEFAULT } from "./settings.keys.js";

@Injectable()
export class SettingsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  /**
   * Cache mémoire des réglages lus.
   *
   * Les règles métier du Lot 6 interrogent `system_settings` très souvent : à
   * chaque création de mission, à chaque annulation, à chaque passage d'un job.
   * Aller en base pour lire une constante à chaque fois serait du gaspillage.
   *
   * Le cache est court (60 s) et vidé à chaque écriture : un réglage modifié
   * dans le back-office prend effet tout de suite, sans redémarrage.
   */
  private readonly cache = new Map<string, { value: string; readAt: number }>();
  private static readonly CACHE_TTL_MS = 60_000;

  // Liste tous les réglages, triés par clé.
  async list() {
    return this.prisma.systemSetting.findMany({ orderBy: { key: "asc" } });
  }

  /**
   * Lit un réglage, ou renvoie la valeur de repli s'il n'existe pas.
   *
   * Ne jamais lever d'exception ici est délibéré : un réglage absent (base pas
   * encore seedée, clé ajoutée par un lot ultérieur) ne doit pas faire échouer
   * une réservation. La valeur de repli est celle documentée au §13.
   */
  async getRaw(key: string): Promise<string | null> {
    const cached = this.cache.get(key);
    if (cached && Date.now() - cached.readAt < SettingsService.CACHE_TTL_MS) {
      return cached.value;
    }

    const row = await this.prisma.systemSetting.findUnique({ where: { key }, select: { value: true } });
    if (!row) {
      return null;
    }

    this.cache.set(key, { value: row.value, readAt: Date.now() });
    return row.value;
  }

  async getNumber(key: string, fallback: number): Promise<number> {
    const raw = await this.getRaw(key);
    const parsed = Number(raw);
    return raw !== null && Number.isFinite(parsed) ? parsed : fallback;
  }

  async getBoolean(key: string, fallback: boolean): Promise<boolean> {
    const raw = await this.getRaw(key);
    if (raw === "true") return true;
    if (raw === "false") return false;
    return fallback;
  }

  async getStringList(key: string, fallback: string[]): Promise<string[]> {
    const raw = await this.getRaw(key);
    if (!raw) return fallback;
    try {
      const parsed: unknown = JSON.parse(raw);
      // On accepte aussi une liste séparée par des virgules : c'est ce qu'un
      // agent tape spontanément dans le champ texte du back-office.
      if (Array.isArray(parsed)) {
        return parsed.filter((item): item is string => typeof item === "string");
      }
    } catch {
      return raw
        .split(",")
        .map((item) => item.trim())
        .filter(Boolean);
    }
    return fallback;
  }

  /**
   * Réglages métier visibles par l'utilisateur final (§13).
   *
   * Ces six valeurs pilotent des règles que l'application mobile doit refléter
   * AVANT d'appeler l'API : griser « Démarrer » hors de la fenêtre autorisée,
   * afficher un compte à rebours de dépôt d'avis, avertir d'une annulation
   * tardive. Sans cette route, elles ne se lisaient que par `/admin/settings` :
   * l'application devait les coder en dur, et mentait à l'utilisateur dès que
   * l'exploitation modifiait un réglage.
   *
   * Rien d'autre n'est exposé : la liste est FERMÉE, écrite ici en toutes
   * lettres. `list()` reste réservée au back-office — elle renverrait aussi les
   * réglages d'exploitation, qui ne regardent pas le public.
   */
  async publicSettings() {
    const [
      missionMinLeadTimeMinutes,
      missionCancellationNoticeHours,
      missionStartWindowMinutes,
      missionPendingExpiryHours,
      missionAutoCloseDays,
      reviewsWindowDays
    ] = await Promise.all([
      this.getNumber(SETTING.missionMinLeadTimeMinutes, SETTING_DEFAULT.missionMinLeadTimeMinutes),
      this.getNumber(SETTING.missionCancellationNoticeHours, SETTING_DEFAULT.missionCancellationNoticeHours),
      this.getNumber(SETTING.missionStartWindowMinutes, SETTING_DEFAULT.missionStartWindowMinutes),
      this.getNumber(SETTING.missionPendingExpiryHours, SETTING_DEFAULT.missionPendingExpiryHours),
      this.getNumber(SETTING.missionAutoCloseDays, SETTING_DEFAULT.missionAutoCloseDays),
      this.getNumber(SETTING.reviewsWindowDays, SETTING_DEFAULT.reviewsWindowDays)
    ]);

    return {
      missionMinLeadTimeMinutes,
      missionCancellationNoticeHours,
      missionStartWindowMinutes,
      missionPendingExpiryHours,
      missionAutoCloseDays,
      reviewsWindowDays
    };
  }

  // Vérifie que la valeur correspond bien au type déclaré du réglage.
  private validateValue(type: string, value: string): void {
    if (type === "number" && Number.isNaN(Number(value))) {
      throw new BadRequestException("La valeur doit être un nombre");
    }
    if (type === "boolean" && value !== "true" && value !== "false") {
      throw new BadRequestException('La valeur doit être "true" ou "false"');
    }
    if (type === "json") {
      try {
        JSON.parse(value);
      } catch {
        throw new BadRequestException("La valeur doit être du JSON valide");
      }
    }
  }

  // Met à jour la valeur d'un réglage existant (la valeur est validée selon son type).
  async update(key: string, value: string, actorId?: string) {
    const existing = await this.prisma.systemSetting.findUnique({ where: { key } });
    if (!existing) {
      throw new NotFoundException("Réglage introuvable");
    }
    this.validateValue(existing.type, value);

    const updated = await this.prisma.systemSetting.update({
      where: { key },
      data: { value, updatedBy: actorId }
    });

    // Le cache doit être invalidé DANS la foulée : sinon un délai d'annulation
    // corrigé dans le back-office resterait sans effet pendant une minute.
    this.cache.delete(key);

    await this.audit.record({
      actorId,
      action: "admin.settings.update",
      entity: "SystemSetting",
      entityId: key,
      oldValue: { value: existing.value },
      newValue: { value }
    });

    return updated;
  }
}
