import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import { NOTIFICATION, NotificationEventsService } from "../notifications/notification-events.service.js";
import { SETTING, SETTING_DEFAULT } from "../settings/settings.keys.js";
import { SettingsService } from "../settings/settings.service.js";
import { formatDateTime } from "./mission-booking.service.js";

/**
 * Reprogrammation à DEUX PARTIES (§10).
 *
 * La table `mission_reschedules` et ses statuts existaient déjà, mais seul un
 * administrateur pouvait reporter une mission — et sans accord de personne. Ce
 * service expose le cycle complet : l'une des parties propose, l'AUTRE accepte
 * ou refuse. Tant que rien n'est accepté, la date d'origine tient.
 *
 * La reprogrammation administrative reste applicable directement : c'est un
 * outil de support, utilisé quand les parties ne parviennent pas à s'entendre.
 */
@Injectable()
export class MissionRescheduleService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly settings: SettingsService,
    private readonly events: NotificationEventsService
  ) {}

  /** Propose une nouvelle date. Client ou prestataire, indifféremment. */
  async request(missionId: string, actorUserId: string, newDate: string, reason?: string) {
    const mission = await this.requireParty(missionId, actorUserId);

    if (mission.status !== "pending_provider" && mission.status !== "confirmed") {
      throw new BadRequestException(
        `Une mission au statut « ${mission.status} » ne peut plus être reprogrammée`
      );
    }

    const newScheduledAt = new Date(newDate);
    if (Number.isNaN(newScheduledAt.getTime())) {
      throw new BadRequestException("Date de report invalide");
    }

    const minLeadMinutes = await this.settings.getNumber(
      SETTING.missionMinLeadTimeMinutes,
      SETTING_DEFAULT.missionMinLeadTimeMinutes
    );
    if (newScheduledAt.getTime() < Date.now() + minLeadMinutes * 60_000) {
      throw new BadRequestException(`La nouvelle date doit être au moins ${minLeadMinutes} minutes dans le futur`);
    }
    if (mission.scheduledAt && newScheduledAt.getTime() === mission.scheduledAt.getTime()) {
      throw new BadRequestException("La nouvelle date est identique à la date actuelle");
    }

    // Une seule demande en attente à la fois : deux propositions concurrentes
    // rendraient l'acceptation ambiguë — laquelle s'applique ?
    const pending = await this.prisma.missionReschedule.findFirst({
      where: { missionId, status: "requested" },
      select: { id: true }
    });
    if (pending) {
      throw new BadRequestException("Une demande de report est déjà en attente de réponse");
    }

    // La nouvelle date est validée contre l'agenda du prestataire, comme à la
    // réservation : accepter un report vers un créneau non travaillé ne ferait
    // que déplacer le problème.
    await this.assertProviderAvailable(mission.provider?.id, newScheduledAt, mission.durationMinutes);

    const reschedule = await this.prisma.missionReschedule.create({
      data: {
        missionId,
        oldScheduledAt: mission.scheduledAt,
        newScheduledAt,
        reason: reason?.trim(),
        status: "requested",
        createdBy: actorUserId
      },
      select: { id: true, newScheduledAt: true, reason: true, status: true, createdAt: true }
    });

    await this.audit.record({
      actorId: actorUserId,
      action: "missions.reschedule.request",
      entity: "MissionReschedule",
      entityId: reschedule.id,
      newValue: { missionId, newScheduledAt, reason }
    });

    // Seule l'AUTRE partie est prévenue : c'est elle qui doit se prononcer.
    const counterparty = mission.clientId === actorUserId ? mission.provider?.userId : mission.clientId;
    await this.events.notifyMany([counterparty], {
      code: NOTIFICATION.rescheduleRequested,
      variables: { newDate: formatDateTime(newScheduledAt), reason: reason ?? "" },
      data: { missionId, rescheduleId: reschedule.id, type: "reschedule" }
    });

    return reschedule;
  }

  /**
   * Accepte une demande de report.
   *
   * L'auteur ne peut pas accepter sa propre demande : ce serait un report
   * unilatéral déguisé, exactement ce que le §10 cherche à empêcher.
   */
  async accept(missionId: string, rescheduleId: string, actorUserId: string) {
    const { mission, reschedule } = await this.requirePendingRequest(missionId, rescheduleId, actorUserId);

    // Le créneau est revalidé au moment de l'acceptation : entre la demande et
    // la réponse, le prestataire a pu déclarer une absence ou prendre une
    // autre mission.
    await this.assertProviderAvailable(mission.provider?.id, reschedule.newScheduledAt, mission.durationMinutes, missionId);

    await this.prisma.$transaction(async (tx) => {
      await tx.missionReschedule.update({
        where: { id: rescheduleId },
        data: { status: "accepted", decidedBy: actorUserId, decidedAt: new Date() }
      });
      await tx.mission.update({ where: { id: missionId }, data: { scheduledAt: reschedule.newScheduledAt } });
      // L'historique porte la trace du report : sans elle, la mission
      // changerait de date sans qu'on sache quand ni pourquoi.
      await tx.missionStatusHistory.create({
        data: {
          missionId,
          oldStatus: mission.status,
          newStatus: mission.status,
          changedBy: actorUserId,
          reason: `Report accepté : ${formatDateTime(reschedule.oldScheduledAt)} → ${formatDateTime(reschedule.newScheduledAt)}`
        }
      });
    });

    await this.audit.record({
      actorId: actorUserId,
      action: "missions.reschedule.accept",
      entity: "MissionReschedule",
      entityId: rescheduleId,
      oldValue: { scheduledAt: reschedule.oldScheduledAt },
      newValue: { scheduledAt: reschedule.newScheduledAt }
    });

    await this.events.notifyMany([mission.clientId, mission.provider?.userId], {
      code: NOTIFICATION.rescheduleAccepted,
      variables: { newDate: formatDateTime(reschedule.newScheduledAt) },
      data: { missionId, type: "mission" }
    });

    return { id: rescheduleId, status: "accepted" as const, scheduledAt: reschedule.newScheduledAt };
  }

  async reject(missionId: string, rescheduleId: string, actorUserId: string, reason: string) {
    if (!reason?.trim()) {
      throw new BadRequestException("Un motif est obligatoire pour refuser un report");
    }
    const { mission, reschedule } = await this.requirePendingRequest(missionId, rescheduleId, actorUserId);

    await this.prisma.missionReschedule.update({
      where: { id: rescheduleId },
      data: { status: "rejected", decidedBy: actorUserId, decidedAt: new Date(), decisionReason: reason.trim() }
    });

    await this.audit.record({
      actorId: actorUserId,
      action: "missions.reschedule.reject",
      entity: "MissionReschedule",
      entityId: rescheduleId,
      newValue: { reason, refusedDate: reschedule.newScheduledAt }
    });

    // Seul le DEMANDEUR est prévenu du refus : la mission garde sa date, il n'y
    // a rien à annoncer à celui qui vient de refuser.
    await this.events.notifyMany([reschedule.createdBy], {
      code: NOTIFICATION.rescheduleRequested,
      variables: { newDate: formatDateTime(mission.scheduledAt), reason: `Report refusé : ${reason}` },
      data: { missionId, type: "mission" }
    });

    return { id: rescheduleId, status: "rejected" as const };
  }

  /** Historique des demandes d'une mission. */
  async list(missionId: string) {
    return this.prisma.missionReschedule.findMany({
      where: { missionId },
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        oldScheduledAt: true,
        newScheduledAt: true,
        reason: true,
        status: true,
        createdBy: true,
        decidedBy: true,
        decidedAt: true,
        decisionReason: true,
        createdAt: true
      }
    });
  }

  // === Aides internes ===

  private async requireParty(missionId: string, actorUserId: string) {
    const mission = await this.prisma.mission.findUnique({
      where: { id: missionId },
      select: {
        id: true,
        status: true,
        clientId: true,
        scheduledAt: true,
        provider: { select: { id: true, userId: true } },
        pack: { select: { durationMinutes: true } },
        options: { select: { optionId: true } }
      }
    });
    if (!mission) {
      throw new NotFoundException("Mission introuvable");
    }
    if (mission.clientId !== actorUserId && mission.provider?.userId !== actorUserId) {
      throw new ForbiddenException("Vous n'êtes pas partie à cette mission");
    }
    return { ...mission, durationMinutes: mission.pack?.durationMinutes ?? 60 };
  }

  private async requirePendingRequest(missionId: string, rescheduleId: string, actorUserId: string) {
    const mission = await this.requireParty(missionId, actorUserId);

    const reschedule = await this.prisma.missionReschedule.findFirst({
      where: { id: rescheduleId, missionId },
      select: { id: true, status: true, createdBy: true, newScheduledAt: true, oldScheduledAt: true }
    });
    if (!reschedule) {
      throw new NotFoundException("Demande de report introuvable");
    }
    if (reschedule.status !== "requested") {
      throw new BadRequestException(`Cette demande a déjà été traitée (statut « ${reschedule.status} »)`);
    }
    if (reschedule.createdBy === actorUserId) {
      throw new ForbiddenException("Vous ne pouvez pas répondre à votre propre demande de report");
    }

    return { mission, reschedule };
  }

  /**
   * Vérifie que le prestataire est libre à la nouvelle date.
   *
   * `excludeMissionId` évite qu'une mission se voie comme son propre conflit
   * lorsqu'on revalide son créneau au moment de l'acceptation.
   */
  private async assertProviderAvailable(
    providerId: string | undefined,
    scheduledAt: Date,
    durationMinutes: number,
    excludeMissionId?: string
  ): Promise<void> {
    if (!providerId) {
      return; // mission sans prestataire assigné : rien à vérifier
    }

    const endAt = new Date(scheduledAt.getTime() + durationMinutes * 60_000);
    const startTime = formatTime(scheduledAt);
    const endTime = formatTime(endAt);

    const slot = await this.prisma.providerAvailability.findFirst({
      where: {
        providerId,
        active: true,
        weekday: scheduledAt.getUTCDay(),
        startTime: { lte: startTime },
        endTime: { gte: endTime }
      },
      select: { id: true }
    });
    if (!slot) {
      throw new BadRequestException("Le prestataire ne travaille pas sur ce créneau");
    }

    const absent = await this.prisma.providerUnavailability.findFirst({
      where: { providerId, startAt: { lt: endAt }, endAt: { gt: scheduledAt } },
      select: { id: true }
    });
    if (absent) {
      throw new BadRequestException("Le prestataire est absent à cette date");
    }

    const neighbours = await this.prisma.mission.findMany({
      where: {
        providerId,
        ...(excludeMissionId ? { id: { not: excludeMissionId } } : {}),
        status: { in: ["pending_provider", "confirmed", "in_progress"] },
        scheduledAt: {
          gte: new Date(scheduledAt.getTime() - 24 * 60 * 60_000),
          lte: new Date(endAt.getTime() + 24 * 60 * 60_000)
        }
      },
      select: { scheduledAt: true, pack: { select: { durationMinutes: true } } }
    });

    const clash = neighbours.some((other) => {
      if (!other.scheduledAt) return false;
      const otherEnd = new Date(other.scheduledAt.getTime() + (other.pack?.durationMinutes ?? 60) * 60_000);
      return other.scheduledAt < endAt && otherEnd > scheduledAt;
    });
    if (clash) {
      throw new BadRequestException("Le prestataire a déjà une mission sur ce créneau");
    }
  }
}

function formatTime(date: Date): string {
  return `${String(date.getUTCHours()).padStart(2, "0")}:${String(date.getUTCMinutes()).padStart(2, "0")}`;
}
