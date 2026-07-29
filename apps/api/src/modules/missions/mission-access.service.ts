import { ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";

export interface Requester {
  id?: string;
  permissions?: string[];
}

/**
 * Vérifie qu'une personne a le droit de toucher à une mission.
 *
 * C'est LA règle qui protège les routes non-admin : sans elle, n'importe quel
 * compte connecté pourrait lire l'historique de la mission d'un inconnu,
 * écrire dans sa conversation ou ouvrir un litige à sa place. Le contrôle ne
 * peut pas se faire côté client, il doit être fait ici.
 *
 * Sont autorisés : le client de la mission, le prestataire qui la réalise, et
 * les agents du back-office porteurs de la permission indiquée.
 */
@Injectable()
export class MissionAccessService {
  constructor(private readonly prisma: PrismaService) {}

  async requireParticipant(missionId: string, requester: Requester, adminPermission = "admin.missions.read") {
    const mission = await this.prisma.mission.findUnique({
      where: { id: missionId },
      include: { provider: { select: { userId: true } } }
    });

    if (!mission) {
      throw new NotFoundException("Mission introuvable");
    }

    const isAdmin = requester.permissions?.includes(adminPermission) ?? false;
    const isClient = Boolean(requester.id) && mission.clientId === requester.id;
    const isProvider = Boolean(requester.id) && mission.provider?.userId === requester.id;

    if (!isAdmin && !isClient && !isProvider) {
      // Même message que pour une mission inexistante n'apporterait rien ici :
      // l'identifiant est déjà connu de l'appelant. On reste explicite.
      throw new ForbiddenException("Vous n'êtes pas partie à cette mission");
    }

    return { mission, isAdmin, isClient, isProvider };
  }

  // Même contrôle, mais à partir d'une conversation.
  async requireThreadParticipant(threadId: string, requester: Requester) {
    const thread = await this.prisma.chatThread.findUnique({
      where: { id: threadId },
      select: { id: true, missionId: true, status: true }
    });

    if (!thread) {
      throw new NotFoundException("Conversation introuvable");
    }

    const access = await this.requireParticipant(thread.missionId, requester, "admin.messages.read");
    return { thread, ...access };
  }
}
