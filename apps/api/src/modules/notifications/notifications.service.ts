import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import { NotificationDispatcher } from "./notification-dispatcher.service.js";

@Injectable()
export class NotificationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly dispatcher: NotificationDispatcher
  ) {}

  // Liste les notifications récentes (les plus récentes en premier).
  async list(query: { page?: number; limit?: number }) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));
    const [data, total] = await Promise.all([
      this.prisma.notification.findMany({ orderBy: { createdAt: "desc" }, skip: (page - 1) * limit, take: limit }),
      this.prisma.notification.count()
    ]);
    return { data, total, page, limit };
  }

  /**
   * Notifications de l'utilisateur connecté (§12).
   *
   * Seul le canal `in_app` est renvoyé : les lignes `email`, `sms` et `push`
   * sont des traces d'acheminement, pas des messages à afficher. Les inclure
   * ferait apparaître chaque notification en double ou en triple dans la liste.
   */
  async listForUser(userId: string, query: { page?: number; limit?: number; unread?: boolean }) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));
    const where = {
      userId,
      channel: "in_app",
      ...(query.unread === true ? { readAt: null } : {})
    };

    const [data, total] = await Promise.all([
      this.prisma.notification.findMany({
        where,
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * limit,
        take: limit,
        select: {
          id: true,
          type: true,
          title: true,
          body: true,
          data: true,
          readAt: true,
          createdAt: true
        }
      }),
      this.prisma.notification.count({ where })
    ]);

    return { data, total, page, limit };
  }

  async unreadCount(userId: string) {
    const count = await this.prisma.notification.count({
      where: { userId, channel: "in_app", readAt: null }
    });
    return { unread: count };
  }

  /**
   * Marque une notification comme lue.
   *
   * `updateMany` filtré sur le propriétaire, et non `update` par identifiant :
   * c'est ce qui empêche de marquer lue la notification de quelqu'un d'autre.
   * Le résultat est le même si la notification n'existe pas ou ne vous
   * appartient pas — on n'apprend donc rien en essayant.
   */
  async markRead(userId: string, notificationId: string) {
    const result = await this.prisma.notification.updateMany({
      where: { id: notificationId, userId, readAt: null },
      data: { readAt: new Date() }
    });
    return { updated: result.count };
  }

  async markAllRead(userId: string) {
    const result = await this.prisma.notification.updateMany({
      where: { userId, channel: "in_app", readAt: null },
      data: { readAt: new Date() }
    });
    return { updated: result.count };
  }

  // Liste les modèles de notification réutilisables.
  async listTemplates() {
    return this.prisma.notificationTemplate.findMany({ orderBy: { code: "asc" } });
  }

  /**
   * Modifie un modèle de notification.
   *
   * Le `code` n'est volontairement pas modifiable : c'est lui que le code
   * applicatif utilise pour retrouver un modèle (« welcome », « mission_confirmed »…).
   * Le renommer casserait silencieusement les envois qui s'y réfèrent.
   */
  async updateTemplate(
    id: string,
    dto: { titleTemplate?: string; bodyTemplate?: string; active?: boolean },
    actorId?: string
  ) {
    const existing = await this.prisma.notificationTemplate.findUnique({ where: { id } });
    if (!existing) {
      throw new NotFoundException("Modèle de notification introuvable");
    }

    const template = await this.prisma.notificationTemplate.update({
      where: { id },
      data: {
        titleTemplate: dto.titleTemplate ?? existing.titleTemplate,
        bodyTemplate: dto.bodyTemplate ?? existing.bodyTemplate,
        active: dto.active ?? existing.active
      }
    });

    await this.audit.record({
      actorId,
      action: "admin.notifications.template.update",
      entity: "NotificationTemplate",
      entityId: id,
      oldValue: { titleTemplate: existing.titleTemplate, active: existing.active },
      newValue: dto
    });

    return template;
  }

  // "Envoie" une notification : ici on l'enregistre en base avec le statut "queued".
  // (Dans une vraie mise en production, une file Redis/BullMQ traiterait l'envoi réel.)
  async send(dto: { userId?: string; type: string; title: string; body: string; channel?: string }, actorId?: string) {
    if (!dto.title?.trim() || !dto.body?.trim()) {
      throw new BadRequestException("Le titre et le corps de la notification sont obligatoires");
    }
    const notification = await this.prisma.notification.create({
      data: {
        userId: dto.userId,
        type: dto.type || "custom",
        title: dto.title,
        body: dto.body,
        channel: dto.channel ?? "in_app",
        status: "queued"
      }
    });

    await this.audit.record({
      actorId,
      action: "admin.notifications.send",
      entity: "Notification",
      entityId: notification.id,
      newValue: { title: dto.title, channel: notification.channel }
    });

    // Mise en file pour acheminement réel. En mode « inline » (tests) le
    // traitement est immédiat, donc on relit la ligne pour renvoyer son
    // statut définitif plutôt qu'un « queued » déjà périmé.
    await this.dispatcher.enqueue(notification.id);
    return (await this.prisma.notification.findUnique({ where: { id: notification.id } })) ?? notification;
  }
}
