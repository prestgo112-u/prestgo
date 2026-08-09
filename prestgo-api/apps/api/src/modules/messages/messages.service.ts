import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import type { Prisma } from "@prisma/client";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { buildOrderBy, parseSort, type SortAllowList } from "../../common/dto/sorting.js";

@Injectable()
export class MessagesService {
  /**
   * Colonnes triables de « mes conversations » (§15.4), en mode tolérant (§12).
   *
   * `lastMessageAt` n'est PAS une colonne persistée : `ChatThread` n'a pas de
   * champ `updatedAt`, seulement `createdAt` (date de création du fil, pas de
   * dernière activité). Le tri par dernier message se fait donc en mémoire,
   * après la lecture — même principe que le tri par distance de
   * `provider-search.service.ts`, qui n'est pas non plus une colonne SQL.
   */
  private static readonly MY_THREADS_SORTABLE: SortAllowList = {
    createdAt: { path: ["createdAt"], defaultDirection: "desc" },
    lastMessageAt: { path: ["createdAt"], defaultDirection: "desc" }
  };

  /**
   * Colonnes triables des messages d'UN fil, en mode tolérant (§12).
   *
   * Défaut CROISSANT (le plus ancien d'abord) — c'est l'ordre qu'affichait
   * déjà `listMessages` avant sa pagination (décision F, écart n°12) : une
   * conversation se lit du début vers la fin, à l'inverse de la plupart des
   * listes de l'API qui affichent le plus récent en premier.
   */
  private static readonly THREAD_MESSAGES_SORTABLE: SortAllowList = {
    createdAt: { path: ["createdAt"], defaultDirection: "asc" }
  };

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
   * Nombre total de messages non lus, tous fils confondus (§12).
   *
   * Pendant de `NotificationsService.unreadCount` : l'application mobile a
   * besoin d'une pastille sur l'onglet messagerie sans charger la liste des
   * conversations. Sommer les `unreadCount` de `GET /me/threads` ne donnait que
   * le total de la PREMIÈRE page — une approximation fausse dès qu'un
   * utilisateur dépasse la taille de page.
   *
   * Le filtre est celui de `listThreadsForUser` : un fil est « à moi » si je
   * suis le client de la mission ou son prestataire. Et comme dans le décompte
   * par fil, mes propres messages ne comptent jamais comme non lus.
   */
  async unreadCountForUser(userId: string) {
    const count = await this.prisma.chatMessage.count({
      where: {
        readAt: null,
        senderId: { not: userId },
        thread: { mission: { OR: [{ clientId: userId }, { provider: { userId } }] } }
      }
    });
    return { unread: count };
  }

  /**
   * Mes conversations (§12).
   *
   * Un fil est « à moi » si je suis le client de la mission ou son prestataire.
   * Le nombre de non-lus ne compte QUE les messages des autres : mes propres
   * messages n'ont pas à être marqués lus.
   */
  async listThreadsForUser(userId: string, query: { page?: number; limit?: number; sort?: string }) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));

    const where = {
      mission: {
        OR: [{ clientId: userId }, { provider: { userId } }]
      }
    };

    // Tri : un champ inconnu ou mal formé retombe sur le défaut (`null`),
    // sans bloquer l'appelant (§12, mode tolérant).
    const parsed = parseSort(query.sort, MessagesService.MY_THREADS_SORTABLE, { lenient: true });
    const sortByLastMessage = parsed?.field === "lastMessageAt";
    const direction = parsed?.direction ?? "desc";

    const selectShape = {
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
        orderBy: { createdAt: "desc" as const },
        take: 1,
        select: { id: true, message: true, senderId: true, createdAt: true }
      },
      _count: { select: { messages: { where: { readAt: null, senderId: { not: userId } } } } }
    };

    const toDto = (thread: {
      id: string;
      status: string;
      createdAt: Date;
      mission: {
        id: string;
        status: string;
        scheduledAt: Date | null;
        clientId: string;
        client: { firstName: string | null; lastName: string | null };
        provider: { userId: string; publicName: string; avatarFileId: string | null } | null;
      };
      messages: { id: string; message: string; senderId: string | null; createdAt: Date }[];
      _count: { messages: number };
    }) => {
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
    };

    // Tri par date de création du fil : une colonne réelle, la pagination se
    // fait normalement au niveau SQL — c'est le chemin par défaut, inchangé.
    if (!sortByLastMessage) {
      const [rows, total] = await Promise.all([
        this.prisma.chatThread.findMany({
          where,
          orderBy: { createdAt: direction },
          skip: (page - 1) * limit,
          take: limit,
          select: selectShape
        }),
        this.prisma.chatThread.count({ where })
      ]);
      return { data: rows.map(toDto), total, page, limit };
    }

    // Tri par date du DERNIER MESSAGE : ce n'est pas une colonne persistée
    // (`ChatThread` n'a pas d'`updatedAt`). On lit donc l'ensemble des fils de
    // l'utilisateur — un nombre borné, ce sont ses propres conversations —
    // puis on trie en mémoire sur le message le plus récent avant de découper
    // la page. Même principe que le tri par distance de
    // `provider-search.service.ts`, qui n'est pas non plus une colonne SQL.
    const [rows, total] = await Promise.all([
      this.prisma.chatThread.findMany({ where, select: selectShape }),
      this.prisma.chatThread.count({ where })
    ]);

    const sorted = rows
      .map(toDto)
      .sort((a, b) => {
        const aTime = (a.lastMessage?.createdAt ?? a.createdAt).getTime();
        const bTime = (b.lastMessage?.createdAt ?? b.createdAt).getTime();
        return direction === "asc" ? aTime - bTime : bTime - aTime;
      });

    return { data: sorted.slice((page - 1) * limit, page * limit), total, page, limit };
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

  /**
   * Messages d'UN fil, PAGINÉS (l'appelant a déjà vérifié les droits dessus).
   *
   * Décision F (écart n°12 du cahier des charges mobile) : cette méthode
   * renvoyait auparavant TOUS les messages en un seul tableau, sans limite —
   * viable pour une poignée d'échanges, plus du tout pour une conversation
   * qui s'étale sur des mois. Le mécanisme est le même que pour toute autre
   * liste de l'API (`page`/`limit`/`sort`, mode tolérant), pas un schéma de
   * pagination propre à la messagerie.
   */
  async listMessages(threadId: string, query: { page?: number; limit?: number; sort?: string } = {}) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));

    const [data, total] = await Promise.all([
      this.prisma.chatMessage.findMany({
        where: { threadId },
        orderBy: buildOrderBy<Prisma.ChatMessageOrderByWithRelationInput>(
          query.sort,
          MessagesService.THREAD_MESSAGES_SORTABLE,
          { createdAt: "asc" },
          { lenient: true }
        ),
        skip: (page - 1) * limit,
        take: limit,
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
      }),
      this.prisma.chatMessage.count({ where: { threadId } })
    ]);

    return { data, total, page, limit };
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
