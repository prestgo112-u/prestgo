import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import type { MissionStatus } from "@prisma/client";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import { NOTIFICATION, NotificationEventsService, type NotificationCode } from "../notifications/notification-events.service.js";
import { SETTING, SETTING_DEFAULT } from "../settings/settings.keys.js";
import { SettingsService } from "../settings/settings.service.js";
import { assertTransition } from "./mission-status.machine.js";
import { formatDateTime } from "./mission-booking.service.js";

/** Qui déclenche la transition. `system` désigne un job planifié (§14.2). */
export type MissionActorKind = "client" | "provider" | "admin" | "system";

export interface MissionActor {
  id?: string;
  kind: MissionActorKind;
}

export interface TransitionOptions {
  reason?: string;
  /** Circonstances détaillées d'une annulation. */
  details?: string;
  /** Action journalisée (par défaut déduite de l'acteur et du statut visé). */
  auditAction?: string;
}

/**
 * Service UNIQUE de transition d'une mission (§14.1).
 *
 * Toutes les routes qui font bouger une mission passent par ici : celles du
 * client, celles du prestataire, `PATCH /admin/missions/:id/status`, et les
 * jobs planifiés. C'est ce qui garantit la promesse du §17 — « toute
 * transition interdite est refusée avec le MÊME message que côté admin ».
 *
 * Dupliquer cette logique côté mobile aurait produit, à terme, deux machines à
 * états divergentes : un statut atteignable depuis l'application et pas depuis
 * le back-office, ou l'inverse.
 */
@Injectable()
export class MissionLifecycleService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly settings: SettingsService,
    private readonly events: NotificationEventsService
  ) {}

  /**
   * Applique une transition de statut.
   *
   * L'ordre compte : on valide la transition, on écrit dans une transaction
   * (statut + historique + annulation éventuelle), puis seulement on notifie.
   * Notifier avant l'écriture annoncerait un changement qui pourrait échouer.
   */
  async transition(missionId: string, target: MissionStatus, actor: MissionActor, options: TransitionOptions = {}) {
    const mission = await this.load(missionId);

    assertTransition(mission.status, target, options.reason);

    const late = target === "cancelled" ? await this.isLateCancellation(mission.scheduledAt) : false;

    await this.prisma.$transaction(async (tx) => {
      await tx.mission.update({ where: { id: missionId }, data: { status: target } });
      await tx.missionStatusHistory.create({
        data: {
          missionId,
          oldStatus: mission.status,
          newStatus: target,
          // `changedBy` reste nul pour un job : la contrainte pointe vers un
          // utilisateur réel, et « system » n'en est pas un. L'acteur reste
          // identifiable par l'action journalisée en audit.
          changedBy: actor.kind === "system" ? null : actor.id,
          reason: options.reason
        }
      });

      if (target === "cancelled") {
        await tx.missionCancellation.upsert({
          where: { missionId },
          update: {
            reason: options.reason ?? "Annulation",
            details: options.details,
            late,
            cancelledBy: actor.kind === "system" ? null : actor.id
          },
          create: {
            missionId,
            reason: options.reason ?? "Annulation",
            details: options.details,
            late,
            cancelledBy: actor.kind === "system" ? null : actor.id
          }
        });
      }
    });

    await this.audit.record({
      actorId: actor.kind === "system" ? undefined : actor.id,
      action: options.auditAction ?? `missions.${actor.kind}.status.${target}`,
      entity: "Mission",
      entityId: missionId,
      oldValue: { status: mission.status },
      newValue: { status: target, reason: options.reason, ...(target === "cancelled" ? { late } : {}) }
    });

    await this.notifyCounterparties(mission, target, actor, options.reason);

    return { missionId, previousStatus: mission.status, status: target, late };
  }

  // === Actions du prestataire (§9) ===

  async accept(missionId: string, providerUserId: string) {
    await this.requireProviderOf(missionId, providerUserId, "pending_provider");
    return this.transition(missionId, "confirmed", { id: providerUserId, kind: "provider" }, {
      reason: "Acceptée par le prestataire",
      auditAction: "missions.provider.accept"
    });
  }

  async refuse(missionId: string, providerUserId: string, reason: string) {
    await this.requireProviderOf(missionId, providerUserId, "pending_provider");
    // Un refus est une annulation motivée : le client doit savoir pourquoi
    // son créneau se libère.
    return this.transition(missionId, "cancelled", { id: providerUserId, kind: "provider" }, {
      reason,
      auditAction: "missions.provider.refuse"
    });
  }

  /**
   * Démarre l'intervention.
   *
   * Une fenêtre d'avance est imposée : sans elle, un prestataire pourrait
   * marquer « démarré » une mission prévue la semaine suivante, ce qui
   * fausserait les délais et permettrait de la clôturer — donc de déclencher
   * la demande d'avis — avant même d'être passé.
   */
  async start(missionId: string, providerUserId: string) {
    const mission = await this.requireProviderOf(missionId, providerUserId, "confirmed");

    const windowMinutes = await this.settings.getNumber(
      SETTING.missionStartWindowMinutes,
      SETTING_DEFAULT.missionStartWindowMinutes
    );

    if (mission.scheduledAt) {
      const earliest = new Date(mission.scheduledAt.getTime() - windowMinutes * 60_000);
      if (new Date() < earliest) {
        throw new BadRequestException(
          `Vous pourrez démarrer cette mission au plus tôt ${windowMinutes} minutes avant l'heure prévue`
        );
      }
    }

    return this.transition(missionId, "in_progress", { id: providerUserId, kind: "provider" }, {
      auditAction: "missions.provider.start"
    });
  }

  async complete(missionId: string, providerUserId: string) {
    await this.requireProviderOf(missionId, providerUserId, "in_progress");
    return this.transition(missionId, "completed", { id: providerUserId, kind: "provider" }, {
      auditAction: "missions.provider.complete"
    });
  }

  // === Annulation, des deux côtés (§8 et §9) ===

  /**
   * Annulation par une partie prenante.
   *
   * Le client annule depuis `pending_provider` et `confirmed` ; le prestataire
   * depuis `confirmed` (avant acceptation, il « refuse » plutôt). Une
   * annulation tardive n'est pas refusée — elle est ACCEPTÉE et marquée
   * `late` : bloquer le client l'aurait simplement poussé à ne pas prévenir,
   * ce qui est pire pour le prestataire.
   */
  async cancelByParticipant(missionId: string, actorUserId: string, reason: string, details?: string) {
    if (!reason?.trim()) {
      throw new BadRequestException("Un motif d'annulation est obligatoire");
    }

    const mission = await this.load(missionId);
    const isClient = mission.clientId === actorUserId;
    const isProvider = mission.provider?.userId === actorUserId;

    if (!isClient && !isProvider) {
      // 403 et non 404 : la mission existe, l'appelant en connaît déjà
      // l'identifiant, lui répondre « introuvable » serait un mensonge (§14.3).
      throw new ForbiddenException("Vous n'êtes pas partie à cette mission");
    }

    if (isProvider && mission.status === "pending_provider") {
      throw new BadRequestException(
        "Cette mission n'est pas encore acceptée : utilisez le refus (POST /missions/:id/refuse)"
      );
    }

    return this.transition(missionId, "cancelled", { id: actorUserId, kind: isClient ? "client" : "provider" }, {
      reason,
      details,
      auditAction: isClient ? "missions.client.cancel" : "missions.provider.cancel"
    });
  }

  // === Aides internes ===

  private async load(missionId: string) {
    const mission = await this.prisma.mission.findUnique({
      where: { id: missionId },
      select: {
        id: true,
        status: true,
        clientId: true,
        scheduledAt: true,
        provider: { select: { id: true, userId: true, publicName: true } },
        client: { select: { firstName: true, lastName: true } }
      }
    });
    if (!mission) {
      throw new NotFoundException("Mission introuvable");
    }
    return mission;
  }

  /**
   * Vérifie que l'appelant est bien LE prestataire de la mission, et que la
   * mission est dans le statut attendu.
   *
   * Le prestataire est résolu depuis le jeton puis comparé à celui de la
   * mission : un identifiant fourni dans l'URL n'entre jamais dans la décision.
   */
  private async requireProviderOf(missionId: string, providerUserId: string, expected: MissionStatus) {
    const mission = await this.load(missionId);

    if (mission.provider?.userId !== providerUserId) {
      throw new ForbiddenException("Vous n'êtes pas le prestataire de cette mission");
    }
    if (mission.status !== expected) {
      // Message identique à celui de la machine à états, pour que l'expérience
      // soit la même côté mobile et côté back-office.
      throw new BadRequestException(`Action impossible depuis le statut « ${mission.status} »`);
    }

    return mission;
  }

  private async isLateCancellation(scheduledAt: Date | null): Promise<boolean> {
    if (!scheduledAt) {
      return false;
    }
    const noticeHours = await this.settings.getNumber(
      SETTING.missionCancellationNoticeHours,
      SETTING_DEFAULT.missionCancellationNoticeHours
    );
    return scheduledAt.getTime() - Date.now() < noticeHours * 60 * 60_000;
  }

  /**
   * Prévient la partie qui n'a PAS déclenché la transition (§9).
   *
   * On ne notifie jamais l'auteur de sa propre action : recevoir « vous avez
   * accepté la mission » juste après avoir appuyé sur « accepter » est du bruit.
   * Un job (`system`) prévient les deux parties.
   */
  private async notifyCounterparties(
    mission: {
      id: string;
      clientId: string;
      scheduledAt: Date | null;
      provider: { userId: string; publicName: string } | null;
      client: { firstName: string | null; lastName: string | null };
    },
    target: MissionStatus,
    actor: MissionActor,
    reason?: string
  ): Promise<void> {
    const code = TRANSITION_NOTIFICATIONS[target];
    if (!code) {
      return;
    }

    const recipients: (string | null | undefined)[] = [];
    if (actor.kind !== "client") recipients.push(mission.clientId);
    if (actor.kind !== "provider") recipients.push(mission.provider?.userId);

    await this.events.notifyMany(recipients, {
      code,
      variables: {
        providerName: mission.provider?.publicName ?? "Le prestataire",
        clientName: [mission.client.firstName, mission.client.lastName].filter(Boolean).join(" ") || "Le client",
        scheduledAt: formatDateTime(mission.scheduledAt),
        reason: reason ?? ""
      },
      data: { missionId: mission.id, type: "mission" }
    });
  }
}

/**
 * Modèle de notification associé à chaque statut atteint.
 *
 * `disputed` et `draft` n'y figurent pas volontairement : l'ouverture d'un
 * litige a sa propre notification (`dispute.opened`), et `draft` n'est pas un
 * état atteint par une action utilisateur.
 */
const TRANSITION_NOTIFICATIONS: Partial<Record<MissionStatus, NotificationCode>> = {
  confirmed: NOTIFICATION.missionAccepted,
  in_progress: NOTIFICATION.missionStarted,
  completed: NOTIFICATION.missionCompleted,
  cancelled: NOTIFICATION.missionCancelled
};
