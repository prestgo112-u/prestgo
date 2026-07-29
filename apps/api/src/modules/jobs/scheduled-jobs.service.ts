import { Injectable, Logger, type OnModuleDestroy, type OnModuleInit } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import type { JobQueue } from "../../common/queues/job-queue.js";
import { createQueue, resolveQueueDriver } from "../../common/queues/queue.factory.js";
import { AuditService } from "../audit/audit.service.js";
import { RefreshSessionService } from "../auth/refresh-session.service.js";
import { IdempotencyService } from "../../common/idempotency/idempotency.service.js";
import { MissionLifecycleService } from "../missions/mission-lifecycle.service.js";
import { formatDateTime } from "../missions/mission-booking.service.js";
import { DevicesService } from "../notifications/devices.service.js";
import { NOTIFICATION, NotificationEventsService } from "../notifications/notification-events.service.js";
import { SETTING, SETTING_DEFAULT } from "../settings/settings.keys.js";
import { SettingsService } from "../settings/settings.service.js";

/** Nom des jobs planifiés (§14) et leur périodicité, en syntaxe cron. */
export const SCHEDULED_JOBS = {
  expireMissions: { key: "missions.expire", pattern: "*/15 * * * *" },
  autoCloseMissions: { key: "missions.auto-close", pattern: "0 3 * * *" },
  missionReminders: { key: "missions.reminder", pattern: "0 9 * * *" },
  reviewReminders: { key: "reviews.remind", pattern: "0 10 * * *" },
  cleanupTokens: { key: "tokens.cleanup", pattern: "0 4 * * 1" }
} as const;

export type ScheduledJobName = keyof typeof SCHEDULED_JOBS;

interface ScheduledJob {
  name: ScheduledJobName;
}

/**
 * Jobs planifiés (§14) — le cycle de vie autonome de la plateforme.
 *
 * Sans eux, une mission jamais acceptée reste `pending_provider` pour
 * toujours : elle bloque un créneau, apparaît dans les listes des deux
 * parties, et personne ne sait qu'elle est morte. C'est exactement le
 * problème que le §16.4 décrit.
 *
 * Chaque exécution est TRACÉE en audit avec l'acteur `system` (§14) : quand
 * une mission passe toute seule à `cancelled`, on doit pouvoir dire quand,
 * pourquoi, et par quel job.
 *
 * Les jobs ne sont réellement planifiés qu'avec une file persistante
 * (`QUEUE_DRIVER=bullmq`). En mode mémoire — développement — la planification
 * repose sur de simples minuteurs, et elle est désactivée en mode `inline`
 * pour ne pas parasiter les tests.
 */
@Injectable()
export class ScheduledJobsService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(ScheduledJobsService.name);
  private readonly queue: JobQueue<ScheduledJob>;

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly settings: SettingsService,
    private readonly lifecycle: MissionLifecycleService,
    private readonly events: NotificationEventsService,
    private readonly devices: DevicesService,
    private readonly sessions: RefreshSessionService,
    private readonly idempotency: IdempotencyService
  ) {
    this.queue = createQueue<ScheduledJob>(
      "scheduled-jobs",
      async (job) => {
        await this.run(job.name);
      },
      { maxAttempts: 2 }
    );
  }

  async onModuleInit(): Promise<void> {
    const driver = resolveQueueDriver();

    if (driver === "inline") {
      // En test, les jobs sont déclenchés explicitement par `run()` : les
      // planifier ferait s'exécuter des transitions au milieu des assertions.
      this.logger.log("Jobs planifiés désactivés (driver « inline »)");
      return;
    }

    if (!this.queue.schedule) {
      this.logger.warn("Le driver de file ne sait pas planifier : les jobs du §14 ne tourneront pas");
      return;
    }

    for (const [name, config] of Object.entries(SCHEDULED_JOBS)) {
      await this.queue.schedule({ name: name as ScheduledJobName }, config.pattern, config.key);
    }
    this.logger.log(`${Object.keys(SCHEDULED_JOBS).length} jobs planifiés (driver « ${driver} »)`);
  }

  async onModuleDestroy(): Promise<void> {
    await this.queue.close();
  }

  /** Exécute un job. Public pour être déclenchable en test et en exploitation. */
  async run(name: ScheduledJobName): Promise<Record<string, number>> {
    switch (name) {
      case "expireMissions":
        return this.expireMissions();
      case "autoCloseMissions":
        return this.autoCloseMissions();
      case "missionReminders":
        return this.sendMissionReminders();
      case "reviewReminders":
        return this.sendReviewReminders();
      case "cleanupTokens":
        return this.cleanupTokens();
    }
  }

  /**
   * Expire les demandes restées sans réponse (§14).
   *
   * Une mission `pending_provider` plus vieille que
   * `mission.pending_expiry_hours` est annulée. Les deux parties sont
   * prévenues : côté client, savoir que sa demande n'a pas abouti lui permet
   * de chercher ailleurs.
   */
  private async expireMissions(): Promise<Record<string, number>> {
    const hours = await this.settings.getNumber(
      SETTING.missionPendingExpiryHours,
      SETTING_DEFAULT.missionPendingExpiryHours
    );
    const threshold = new Date(Date.now() - hours * 60 * 60_000);

    const stale = await this.prisma.mission.findMany({
      where: { status: "pending_provider", createdAt: { lt: threshold } },
      select: {
        id: true,
        scheduledAt: true,
        clientId: true,
        provider: { select: { userId: true, publicName: true } }
      },
      take: 200
    });

    let expired = 0;
    for (const mission of stale) {
      try {
        await this.lifecycle.transition(mission.id, "cancelled", { kind: "system" }, {
          reason: `Demande expirée : sans réponse du prestataire après ${hours} h`,
          auditAction: "system.missions.expire"
        });
        // Notification spécifique : « expirée » n'est pas « annulée », le
        // message doit le dire pour que le client comprenne ce qui s'est passé.
        await this.events.notifyMany([mission.clientId, mission.provider?.userId], {
          code: NOTIFICATION.missionExpired,
          variables: { scheduledAt: formatDateTime(mission.scheduledAt) },
          data: { missionId: mission.id, type: "mission" }
        });
        expired += 1;
      } catch (error) {
        // Une mission qui a changé d'état entre-temps ne doit pas interrompre
        // le traitement des suivantes.
        this.logger.warn(`Expiration impossible pour ${mission.id} : ${String(error)}`);
      }
    }

    await this.trace("system.jobs.missions.expire", { candidates: stale.length, expired });
    return { candidates: stale.length, expired };
  }

  /**
   * Clôture automatiquement les missions terminées et sans litige (§14).
   *
   * `closed` est l'état final : il fige la mission. On ne clôt donc jamais une
   * mission qui porte un litige ouvert — ce serait couper court à l'examen en
   * cours.
   */
  private async autoCloseMissions(): Promise<Record<string, number>> {
    const days = await this.settings.getNumber(SETTING.missionAutoCloseDays, SETTING_DEFAULT.missionAutoCloseDays);
    const threshold = new Date(Date.now() - days * 24 * 60 * 60_000);

    const candidates = await this.prisma.mission.findMany({
      where: {
        status: "completed",
        updatedAt: { lt: threshold },
        disputes: { none: { status: { in: ["open", "in_review", "waiting_client", "waiting_provider"] } } }
      },
      select: { id: true },
      take: 200
    });

    let closed = 0;
    for (const mission of candidates) {
      try {
        await this.lifecycle.transition(mission.id, "closed", { kind: "system" }, {
          reason: `Clôture automatique après ${days} jours sans litige`,
          auditAction: "system.missions.auto-close"
        });
        closed += 1;
      } catch (error) {
        this.logger.warn(`Clôture impossible pour ${mission.id} : ${String(error)}`);
      }
    }

    await this.trace("system.jobs.missions.auto-close", { candidates: candidates.length, closed });
    return { candidates: candidates.length, closed };
  }

  /** Rappelle la veille aux deux parties (§14). */
  private async sendMissionReminders(): Promise<Record<string, number>> {
    const now = new Date();
    const from = new Date(now.getTime() + 24 * 60 * 60_000);
    const to = new Date(now.getTime() + 48 * 60 * 60_000);

    const missions = await this.prisma.mission.findMany({
      where: { status: "confirmed", scheduledAt: { gte: from, lt: to } },
      select: {
        id: true,
        scheduledAt: true,
        clientId: true,
        provider: { select: { userId: true, publicName: true } },
        client: { select: { firstName: true, lastName: true } }
      },
      take: 500
    });

    for (const mission of missions) {
      await this.events.notifyMany([mission.clientId, mission.provider?.userId], {
        code: NOTIFICATION.missionReminder,
        variables: {
          scheduledAt: formatDateTime(mission.scheduledAt),
          providerName: mission.provider?.publicName ?? "",
          clientName: [mission.client.firstName, mission.client.lastName].filter(Boolean).join(" ")
        },
        data: { missionId: mission.id, type: "mission" }
      });
    }

    await this.trace("system.jobs.missions.reminder", { reminded: missions.length });
    return { reminded: missions.length };
  }

  /**
   * Relance les clients qui n'ont pas déposé d'avis (§14).
   *
   * Une seule fois, 48 h après la fin. La notification déjà envoyée sert de
   * mémoire : sans ce contrôle, le client serait relancé à chaque passage
   * quotidien du job jusqu'à ce qu'il cède — ou désinstalle l'application.
   */
  private async sendReviewReminders(): Promise<Record<string, number>> {
    const windowDays = await this.settings.getNumber(SETTING.reviewsWindowDays, SETTING_DEFAULT.reviewsWindowDays);
    const now = Date.now();

    const missions = await this.prisma.mission.findMany({
      where: {
        status: "completed",
        updatedAt: {
          lt: new Date(now - 48 * 60 * 60_000),
          // Inutile de relancer une mission dont la fenêtre de dépôt est close.
          gte: new Date(now - windowDays * 24 * 60 * 60_000)
        },
        reviews: { none: {} }
      },
      select: { id: true, clientId: true, provider: { select: { publicName: true } } },
      take: 200
    });

    let reminded = 0;
    for (const mission of missions) {
      const alreadySent = await this.prisma.notification.count({
        where: { userId: mission.clientId, type: NOTIFICATION.reviewRequest, data: { path: ["missionId"], equals: mission.id } }
      });
      if (alreadySent > 0) {
        continue;
      }

      await this.events.notify({
        userId: mission.clientId,
        code: NOTIFICATION.reviewRequest,
        variables: { providerName: mission.provider?.publicName ?? "votre prestataire" },
        data: { missionId: mission.id, type: "review" }
      });
      reminded += 1;
    }

    await this.trace("system.jobs.reviews.remind", { candidates: missions.length, reminded });
    return { candidates: missions.length, reminded };
  }

  /**
   * Entretien hebdomadaire (§14).
   *
   * Désactive les jetons push dormants depuis 90 jours, et purge au passage les
   * sessions et clés d'idempotence périmées — trois tables qui, sans cela,
   * grossissent indéfiniment.
   */
  private async cleanupTokens(): Promise<Record<string, number>> {
    const [devices, sessions, keys] = await Promise.all([
      this.devices.deactivateStale(90),
      this.sessions.purgeExpired(30),
      this.idempotency.purgeExpired()
    ]);

    await this.trace("system.jobs.tokens.cleanup", { devices, sessions, idempotencyKeys: keys });
    return { devices, sessions, idempotencyKeys: keys };
  }

  /**
   * Trace l'exécution d'un job.
   *
   * `actorId` reste vide : « system » n'est pas un utilisateur, et la colonne
   * pointe vers une vraie ligne de `users`. C'est l'action, préfixée
   * `system.`, qui identifie l'auteur.
   */
  private async trace(action: string, result: Record<string, number>): Promise<void> {
    await this.audit.record({ action, entity: "ScheduledJob", newValue: result });
  }
}
