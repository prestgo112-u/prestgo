import { Injectable, Logger, type OnModuleDestroy } from "@nestjs/common";
import type { JobQueue } from "../../common/queues/job-queue.js";
import { createQueue } from "../../common/queues/queue.factory.js";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { buildTransports, type NotificationTransport } from "./transports.js";

interface NotificationJob {
  notificationId: string;
}

/**
 * Achemine réellement les notifications.
 *
 * Avant ce lot, `send()` créait une ligne au statut `queued` et s'arrêtait là :
 * le statut ne changeait jamais, rien n'était acheminé, et l'interface affichait
 * pourtant « envoyé ». C'était trompeur.
 *
 * Désormais chaque notification est mise en file, traitée par un transport, et
 * son statut passe à `sent` ou `failed` selon le résultat.
 */
@Injectable()
export class NotificationDispatcher implements OnModuleDestroy {
  private readonly logger = new Logger(NotificationDispatcher.name);
  private readonly transports: Map<string, NotificationTransport>;
  private readonly queue: JobQueue<NotificationJob>;

  constructor(private readonly prisma: PrismaService) {
    // Le transport push a besoin de deux choses que lui seul ne peut pas
    // savoir : quels appareils appartiennent au destinataire, et quoi faire
    // d'un jeton refusé. On les lui passe sous forme de fonctions plutôt que
    // de lui donner accès à la base — il reste ainsi ignorant du modèle de
    // données, et testable sans elle.
    this.transports = buildTransports({
      resolveTargets: async (userId) =>
        this.prisma.deviceToken.findMany({
          where: { userId, active: true },
          select: { token: true, platform: true }
        }),
      onInvalidToken: async (token) => {
        await this.prisma.deviceToken.updateMany({ where: { token }, data: { active: false } });
        this.logger.log("Jeton push désactivé : refusé par le fournisseur");
      }
    });

    // Le driver est choisi par `QUEUE_DRIVER` / `REDIS_URL` (§15.3) : Redis en
    // production, mémoire en développement, immédiat en test — un test ne doit
    // pas attendre un minuteur pour vérifier le résultat.
    this.queue = createQueue<NotificationJob>("notifications", (job) => this.deliver(job.notificationId), {
      intervalMs: 5_000,
      maxAttempts: 3
    });
  }

  // Met une notification en file d'attente.
  async enqueue(notificationId: string): Promise<void> {
    await this.queue.add({ notificationId });
  }

  /**
   * Traite une notification : choisit le transport, l'achemine, met à jour le
   * statut.
   *
   * Une erreur est relancée volontairement : c'est elle qui déclenche une
   * nouvelle tentative côté file.
   */
  private async deliver(notificationId: string): Promise<void> {
    const notification = await this.prisma.notification.findUnique({
      where: { id: notificationId },
      include: { user: { select: { email: true, phone: true } } }
    });

    if (!notification || notification.status === "sent") {
      return; // déjà traitée, ou supprimée entre-temps
    }

    const transport = this.transports.get(notification.channel);
    if (!transport) {
      await this.markFailed(notificationId, `canal inconnu : ${notification.channel}`);
      return;
    }

    // Destinataire selon le canal. Une notification « in_app » n'en a pas
    // besoin : elle est lue dans l'application.
    const to =
      notification.channel === "sms"
        ? notification.user?.phone
        : notification.channel === "email"
          ? notification.user?.email
          : notification.userId;

    if (!to && notification.channel !== "in_app") {
      await this.markFailed(notificationId, `destinataire absent pour le canal ${notification.channel}`);
      return;
    }

    try {
      await transport.send({
        channel: notification.channel,
        to: to ?? "—",
        title: notification.title,
        body: notification.body,
        // Les données structurées accompagnent le push : c'est ce qui permet à
        // l'application d'ouvrir directement la mission concernée au lieu de
        // déposer l'utilisateur sur l'écran d'accueil.
        data: (notification.data as Record<string, unknown> | null) ?? undefined
      });

      await this.prisma.notification.update({
        where: { id: notificationId },
        data: { status: "sent", sentAt: new Date() }
      });
    } catch (error) {
      await this.markFailed(notificationId, error instanceof Error ? error.message : String(error));
      throw error; // relance -> nouvelle tentative
    }
  }

  private async markFailed(notificationId: string, reason: string): Promise<void> {
    this.logger.warn(`Notification ${notificationId} en échec : ${reason}`);
    await this.prisma.notification.update({ where: { id: notificationId }, data: { status: "failed" } });
  }

  /**
   * Reprend les notifications restées en attente.
   *
   * Utile après un redémarrage : la file étant en mémoire, ce qui n'avait pas
   * été traité serait sinon perdu.
   */
  async requeuePending(): Promise<number> {
    const pending = await this.prisma.notification.findMany({
      where: { status: "queued" },
      select: { id: true },
      take: 500
    });

    for (const notification of pending) {
      await this.queue.add({ notificationId: notification.id });
    }
    return pending.length;
  }

  async onModuleDestroy(): Promise<void> {
    await this.queue.close();
  }
}
