import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";

/**
 * Prestataires mis en favori par un client (§4).
 *
 * Deux règles y sont attachées :
 *   - on n'ajoute en favori qu'un prestataire `approved` — mettre de côté un
 *     dossier encore en instruction n'aurait pas de sens ;
 *   - un prestataire suspendu APRÈS coup reste dans la liste, avec
 *     `available: false`. Le faire disparaître silencieusement serait pire :
 *     le client croirait avoir perdu son favori.
 */
@Injectable()
export class FavoritesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  async list(clientId: string) {
    const rows = await this.prisma.clientFavorite.findMany({
      where: { clientId },
      orderBy: { createdAt: "desc" },
      select: {
        createdAt: true,
        provider: {
          select: {
            id: true,
            publicName: true,
            bio: true,
            score: true,
            reviewsCount: true,
            validationStatus: true,
            availabilityStatus: true,
            services: {
              where: { active: true },
              select: { serviceType: { select: { category: { select: { name: true } } } } }
            }
          }
        }
      }
    });

    return rows.map((row) => ({
      id: row.provider.id,
      publicName: row.provider.publicName,
      bio: row.provider.bio,
      score: Math.round(row.provider.score * 10) / 10,
      reviewsCount: row.provider.reviewsCount,
      categories: [
        ...new Set(row.provider.services.map((service) => service.serviceType.category.name))
      ],
      // « Disponible » agrège les deux conditions que le client comprend :
      // le prestataire est-il encore validé, et se déclare-t-il joignable ?
      available: row.provider.validationStatus === "approved" && row.provider.availabilityStatus !== "unavailable",
      favoritedAt: row.createdAt
    }));
  }

  /** Ajout idempotent : rappuyer sur le cœur ne doit jamais produire d'erreur. */
  async add(clientId: string, providerId: string) {
    const provider = await this.prisma.providerProfile.findUnique({
      where: { id: providerId },
      select: { id: true, validationStatus: true, userId: true }
    });
    if (!provider) {
      throw new NotFoundException("Prestataire introuvable");
    }
    if (provider.validationStatus !== "approved") {
      throw new BadRequestException("Ce prestataire n'est pas encore validé");
    }
    if (provider.userId === clientId) {
      throw new BadRequestException("Vous ne pouvez pas vous ajouter à vos propres favoris");
    }

    await this.prisma.clientFavorite.upsert({
      where: { clientId_providerId: { clientId, providerId } },
      update: {},
      create: { clientId, providerId }
    });

    await this.audit.record({
      actorId: clientId,
      action: "me.favorites.add",
      entity: "ProviderProfile",
      entityId: providerId
    });

    return { favorited: true };
  }

  /** Retrait idempotent : retirer un favori absent réussit sans erreur. */
  async remove(clientId: string, providerId: string) {
    await this.prisma.clientFavorite.deleteMany({ where: { clientId, providerId } });

    await this.audit.record({
      actorId: clientId,
      action: "me.favorites.remove",
      entity: "ProviderProfile",
      entityId: providerId
    });

    return { favorited: false };
  }
}
