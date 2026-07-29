import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";

@Injectable()
export class MessagesService {
  constructor(private readonly prisma: PrismaService) {}

  // Liste les fils de discussion (un par mission) avec le nombre de messages.
  async listThreads(query: { page?: number; limit?: number }) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));

    const [rows, total] = await Promise.all([
      this.prisma.chatThread.findMany({
        include: {
          mission: { select: { id: true, status: true } },
          _count: { select: { messages: true } }
        },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.chatThread.count()
    ]);

    const data = rows.map((t) => ({
      id: t.id,
      missionId: t.missionId,
      missionStatus: t.mission.status,
      status: t.status,
      messageCount: t._count.messages,
      createdAt: t.createdAt
    }));

    return { data, total, page, limit };
  }

  /**
   * Mes conversations (§12).
   *
   * Un fil est « à moi » si je suis le client de la mission ou son prestataire.
   * Le nombre de non-lus ne compte QUE les messages des autres : mes propres
   * messages n'ont pas à être marqués lus.
   */
  async listThreadsForUser(userId: string, query: { page?: number; limit?: number }) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));

    const where = {
      mission: {
        OR: [{ clientId: userId }, { provider: { userId } }]
      }
    };

    const [rows, total] = await Promise.all([
      this.prisma.chatThread.findMany({
        where,
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * limit,
        take: limit,
        select: {
          id: true,
          status: true,
          createdAt: true,
          mission: {
            select: {
              id: true,
              status: true,
              scheduledAt: true,
              clientId: true,
              client: { select: { firstName: true, lastName: true } },
              provider: { select: { userId: true, publicName: true, avatarFileId: true } }
            }
          },
          messages: {
            orderBy: { createdAt: "desc" },
            take: 1,
            select: { id: true, message: true, senderId: true, createdAt: true }
          },
          _count: { select: { messages: { where: { readAt: null, senderId: { not: userId } } } } }
        }
      }),
      this.prisma.chatThread.count({ where })
    ]);

    const data = rows.map((thread) => {
      const iAmTheClient = thread.mission.clientId === userId;
      return {
        id: thread.id,
        missionId: thread.mission.id,
        missionStatus: thread.mission.status,
        scheduledAt: thread.mission.scheduledAt,
        status: thread.status,
        // Le libellé affiché est celui de l'INTERLOCUTEUR, pas le mien.
        counterpartName: iAmTheClient
          ? (thread.mission.provider?.publicName ?? "Prestataire")
          : [thread.mission.client.firstName, thread.mission.client.lastName].filter(Boolean).join(" ") || "Client",
        counterpartAvatarFileId: iAmTheClient ? (thread.mission.provider?.avatarFileId ?? null) : null,
        lastMessage: thread.messages[0] ?? null,
        unreadCount: thread._count.messages,
        createdAt: thread.createdAt
      };
    });

    return { data, total, page, limit };
  }

  /**
   * Nom affiché de l'expéditeur dans une notification.
   *
   * On retombe sur « Votre interlocuteur » plutôt que sur une chaîne vide : une
   * notification qui commence par « : Bonjour » n'aide personne.
   */
  async senderName(userId?: string): Promise<string> {
    if (!userId) {
      return "Votre interlocuteur";
    }
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { firstName: true, lastName: true, providerProfile: { select: { publicName: true } } }
    });
    const name = [user?.firstName, user?.lastName].filter(Boolean).join(" ").trim();
    return name || user?.providerProfile?.publicName || "Votre interlocuteur";
  }

  /**
   * Marque comme lus les messages reçus dans un fil.
   *
   * Seuls les messages des AUTRES sont touchés : horodater ses propres
   * messages comme « lus par soi-même » n'aurait aucun sens et fausserait
   * l'accusé de lecture affiché à l'interlocuteur.
   */
  async markThreadRead(threadId: string, userId: string) {
    const result = await this.prisma.chatMessage.updateMany({
      where: { threadId, readAt: null, senderId: { not: userId } },
      data: { readAt: new Date() }
    });
    return { updated: result.count };
  }

  // Détail d'un fil : tous ses messages, du plus ancien au plus récent.
  async threadDetail(threadId: string) {
    const thread = await this.prisma.chatThread.findUnique({
      where: { id: threadId },
      include: { messages: { orderBy: { createdAt: "asc" } } }
    });
    if (!thread) {
      throw new NotFoundException("Fil de discussion introuvable");
    }
    return thread;
  }

  // Messages seuls (l'appelant a déjà vérifié les droits sur le fil).
  async listMessages(threadId: string) {
    return this.prisma.chatMessage.findMany({
      where: { threadId },
      orderBy: { createdAt: "asc" },
      select: {
        id: true,
        senderId: true,
        message: true,
        createdAt: true,
        readAt: true,
        // Les pièces jointes accompagnent le message : sans elles, l'appelant
        // verrait une conversation amputée de ses photos.
        files: { select: { file: { select: { id: true, originalName: true, mimeType: true, size: true } } } }
      }
    });
  }

  /**
   * Envoie un message dans un fil, avec ses éventuelles pièces jointes (§12).
   *
   * Un fil clos n'accepte plus de message : sinon une conversation « fermée »
   * après litige pourrait être relancée sans que personne ne le voie.
   *
   * Les pièces jointes passent en visibilité `restricted` : lisibles de leur
   * propriétaire et du support (`files.any.read`), jamais du public. Une photo
   * de dégât des eaux envoyée dans une conversation n'a pas à être accessible
   * par simple identifiant.
   */
  async sendMessage(threadId: string, message: string, senderId?: string, fileIds: string[] = []) {
    const thread = await this.prisma.chatThread.findUnique({ where: { id: threadId } });
    if (!thread) {
      throw new NotFoundException("Fil de discussion introuvable");
    }
    if (thread.status === "closed") {
      throw new BadRequestException("Cette conversation est clôturée");
    }

    const attachments = [...new Set(fileIds)];
    if (attachments.length > 0) {
      // Les fichiers doivent APPARTENIR à l'expéditeur. Sans ce contrôle, on
      // pourrait exposer à l'autre partie n'importe quel fichier de la
      // plateforme en citant simplement son identifiant.
      const owned = await this.prisma.file.findMany({
        where: { id: { in: attachments }, ownerId: senderId, disabledAt: null },
        select: { id: true }
      });
      if (owned.length !== attachments.length) {
        throw new BadRequestException("Pièce jointe introuvable ou ne vous appartenant pas");
      }
    }

    return this.prisma.$transaction(async (tx) => {
      if (attachments.length > 0) {
        await tx.file.updateMany({ where: { id: { in: attachments } }, data: { visibility: "restricted" } });
      }

      return tx.chatMessage.create({
        data: {
          threadId,
          senderId,
          message: message.trim(),
          files: { create: attachments.map((fileId) => ({ fileId })) }
        },
        select: {
          id: true,
          senderId: true,
          message: true,
          createdAt: true,
          files: { select: { file: { select: { id: true, originalName: true, mimeType: true, size: true } } } }
        }
      });
    });
  }
}
