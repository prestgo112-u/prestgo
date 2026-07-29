import { Injectable, Logger } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { NotificationDispatcher } from "./notification-dispatcher.service.js";

/**
 * Codes des modèles de notification du Lot 6 (§12).
 *
 * Les regrouper ici évite la faute de frappe silencieuse : un code inconnu
 * produirait une notification au texte vide, envoyée quand même.
 */
export const NOTIFICATION = {
  missionCreated: "mission.created",
  missionAccepted: "mission.accepted",
  missionRefused: "mission.refused",
  missionStarted: "mission.started",
  missionCompleted: "mission.completed",
  missionCancelled: "mission.cancelled",
  missionExpired: "mission.expired",
  missionReminder: "mission.reminder",
  rescheduleRequested: "mission.reschedule.requested",
  rescheduleAccepted: "mission.reschedule.accepted",
  reviewReceived: "review.received",
  reviewRequest: "review.request",
  providerApproved: "provider.approved",
  providerChangesRequested: "provider.changes_requested",
  providerRejected: "provider.rejected",
  disputeOpened: "dispute.opened",
  disputeMessage: "dispute.message",
  disputeDecided: "dispute.decided",
  chatMessage: "chat.message"
} as const;

export type NotificationCode = (typeof NOTIFICATION)[keyof typeof NOTIFICATION];

export interface NotifyInput {
  userId: string;
  code: NotificationCode;
  /** Valeurs injectées dans le modèle (`{{clientName}}`, `{{scheduledAt}}`…). */
  variables?: Record<string, string | number | null | undefined>;
  /** Données structurées transmises à l'application (pour ouvrir le bon écran). */
  data?: Record<string, unknown>;
  /** Canaux forcés. Par défaut : in-app, plus push si l'appareil est enregistré. */
  channels?: string[];
  /**
   * Clé de regroupement des push (§12 : « max 1 par fil et par minute »).
   *
   * Quand elle est fournie, un push déjà parti pour la même clé dans la minute
   * écoulée fait retomber l'envoi sur le seul canal in-app. Sans ce garde-fou,
   * une conversation animée déclencherait une vibration par message —
   * l'utilisateur couperait les notifications, et manquerait ensuite celles qui
   * comptent vraiment.
   */
  groupKey?: string;
}

/** Fenêtre de regroupement des push (§12). */
const PUSH_GROUP_WINDOW_MS = 60_000;

/**
 * Émet les notifications métier à partir des modèles en base (§12).
 *
 * Pourquoi passer par des modèles plutôt que d'écrire le texte dans le code :
 * corriger une formulation ne doit pas demander un déploiement. Les modèles
 * sont éditables depuis le back-office (`/admin/notifications/templates`).
 *
 * Une notification qui échoue ne fait JAMAIS échouer l'action métier qui l'a
 * déclenchée. Une mission acceptée reste acceptée même si le push ne part pas :
 * l'inverse — annuler une acceptation parce qu'un SMS a échoué — serait absurde.
 */
@Injectable()
export class NotificationEventsService {
  private readonly logger = new Logger(NotificationEventsService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly dispatcher: NotificationDispatcher
  ) {}

  async notify(input: NotifyInput): Promise<void> {
    try {
      await this.deliver(input);
    } catch (error) {
      this.logger.error(
        `Notification « ${input.code} » non émise pour ${input.userId} : ${error instanceof Error ? error.message : String(error)}`
      );
    }
  }

  /** Variante multi-destinataires (les deux parties d'une mission). */
  async notifyMany(userIds: (string | null | undefined)[], input: Omit<NotifyInput, "userId">): Promise<void> {
    const unique = [...new Set(userIds.filter((id): id is string => Boolean(id)))];
    await Promise.all(unique.map((userId) => this.notify({ ...input, userId })));
  }

  private async deliver(input: NotifyInput): Promise<void> {
    const template = await this.prisma.notificationTemplate.findUnique({ where: { code: input.code } });

    if (!template) {
      this.logger.warn(`Modèle de notification « ${input.code} » introuvable`);
      return;
    }
    if (!template.active) {
      return; // désactivé volontairement depuis le back-office
    }

    const title = render(template.titleTemplate, input.variables ?? {});
    const body = render(template.bodyTemplate, input.variables ?? {});

    let channels = input.channels ?? (await this.defaultChannels(input.userId));

    if (input.groupKey && channels.includes("push") && (await this.pushRecentlySent(input.userId, input.groupKey))) {
      channels = channels.filter((channel) => channel !== "push");
    }

    for (const channel of channels) {
      const notification = await this.prisma.notification.create({
        data: {
          userId: input.userId,
          type: input.code,
          title,
          body,
          channel,
          status: "queued",
          // La clé de regroupement est stockée AVEC la notification : c'est
          // elle qu'on relit pour savoir si un push est déjà parti récemment.
          data: { ...(input.data ?? {}), ...(input.groupKey ? { groupKey: input.groupKey } : {}) } as object
        },
        select: { id: true }
      });
      await this.dispatcher.enqueue(notification.id);
    }
  }

  /** Un push a-t-il déjà été émis pour cette clé dans la dernière minute ? */
  private async pushRecentlySent(userId: string, groupKey: string): Promise<boolean> {
    const since = new Date(Date.now() - PUSH_GROUP_WINDOW_MS);
    const recent = await this.prisma.notification.count({
      where: {
        userId,
        channel: "push",
        createdAt: { gte: since },
        data: { path: ["groupKey"], equals: groupKey }
      }
    });
    return recent > 0;
  }

  /**
   * Canaux retenus par défaut.
   *
   * L'in-app est systématique : c'est la trace consultable dans l'application,
   * elle ne dépend d'aucun fournisseur externe. Le push s'y ajoute seulement si
   * l'utilisateur a un appareil enregistré — sinon on créerait des lignes
   * `failed` sans destinataire, qui pollueraient le suivi des échecs réels.
   */
  private async defaultChannels(userId: string): Promise<string[]> {
    const hasDevice = await this.prisma.deviceToken.count({ where: { userId, active: true } });
    return hasDevice > 0 ? ["in_app", "push"] : ["in_app"];
  }
}

/**
 * Remplace les `{{variables}}` d'un modèle.
 *
 * Une variable absente est remplacée par une chaîne vide plutôt que laissée
 * telle quelle : afficher « Bonjour {{name}} » à un utilisateur serait pire que
 * « Bonjour ».
 */
function render(template: string, variables: Record<string, string | number | null | undefined>): string {
  return template.replace(/\{\{\s*(\w+)\s*\}\}/g, (_match, key: string) => {
    const value = variables[key];
    return value == null ? "" : String(value);
  });
}
