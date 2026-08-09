import { ForbiddenException, Injectable } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";

/**
 * Retrouve le profil prestataire de l'utilisateur connecté.
 *
 * Toutes les routes « /providers/me/… » en dépendent : elles doivent agir sur
 * LE prestataire connecté, jamais sur un identifiant fourni par le client.
 * C'est ce qui empêche un prestataire de modifier le catalogue d'un confrère
 * en changeant simplement un identifiant dans l'URL.
 */
@Injectable()
export class ProviderContextService {
  constructor(private readonly prisma: PrismaService) {}

  async requireProviderId(userId?: string): Promise<string> {
    if (!userId) {
      throw new ForbiddenException("Authentification requise");
    }

    const profile = await this.prisma.providerProfile.findUnique({
      where: { userId },
      select: { id: true }
    });

    if (!profile) {
      throw new ForbiddenException("Ce compte n'a pas de profil prestataire");
    }

    return profile.id;
  }
}
