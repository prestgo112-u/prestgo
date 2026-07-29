import { Injectable, NotFoundException } from "@nestjs/common";
import type { ReviewStatus } from "@prisma/client";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import { ProviderRatingService } from "./provider-rating.service.js";
import { assertModeration } from "./review-status.rules.js";

@Injectable()
export class ReviewsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly rating: ProviderRatingService
  ) {}

  /**
   * Avis publics d'un prestataire, avec sa note moyenne.
   *
   * Deux filtres essentiels par rapport à la vue admin :
   *   - seuls les avis au statut `published` sortent (un avis masqué ou
   *     signalé ne doit pas rester visible publiquement) ;
   *   - on remonte les avis dont la mission a été réalisée par CE prestataire.
   */
  async listPublicForProvider(providerId: string, query: { page?: number; limit?: number }) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));
    const where = { status: "published" as const, mission: { providerId } };

    const [rows, total] = await Promise.all([
      this.prisma.review.findMany({
        where,
        select: { id: true, rating: true, comment: true, createdAt: true },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.review.count({ where })
    ]);

    // `data` est un TABLEAU, comme toute autre liste paginée de l'API, et la
    // pagination tient dans `meta`. Cette route renvoyait auparavant un objet
    // `{ averageRating, totalReviews, reviews }` : elle était la seule du
    // périmètre à imposer un modèle client à part.
    //
    // Les deux agrégats n'ont pas été déplacés parce qu'ils font DOUBLON :
    //   - `totalReviews` valait exactement `meta.total` (même `where`) ;
    //   - `averageRating` recalculait `provider_profiles.score`, à la même
    //     clause près, déjà exposé par `GET /providers/:id/public` (avec
    //     `ratingDistribution`), l'écran d'où l'on ouvre cette liste.
    return { data: rows, total, page, limit };
  }

  // Liste paginée des avis, filtrable par statut (ex. voir les "reported").
  async list(query: { page?: number; limit?: number; status?: ReviewStatus }) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));
    const where = query.status ? { status: query.status } : {};

    const [rows, total] = await Promise.all([
      this.prisma.review.findMany({
        where,
        include: { _count: { select: { reports: true } } },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.review.count({ where })
    ]);

    const data = rows.map((r) => ({
      id: r.id,
      missionId: r.missionId,
      rating: r.rating,
      comment: r.comment ?? undefined,
      status: r.status,
      reportCount: r._count.reports,
      createdAt: r.createdAt
    }));

    return { data, total, page, limit };
  }

  // Modère un avis (publier / masquer / rejeter). Motif obligatoire pour masquer ou rejeter.
  async moderate(id: string, status: ReviewStatus, reason: string | undefined, actorId?: string) {
    const review = await this.prisma.review.findUnique({ where: { id } });
    if (!review) {
      throw new NotFoundException("Avis introuvable");
    }

    assertModeration(status, reason);

    await this.prisma.review.update({ where: { id }, data: { status } });

    // Masquer ou republier un avis change la moyenne du prestataire (§11).
    // Sans ce recalcul, modérer n'aurait aucun effet visible : la note
    // continuerait d'inclure un avis retiré.
    await this.rating.recomputeFromReview(id);

    await this.audit.record({
      actorId,
      action: "admin.reviews.moderate",
      entity: "Review",
      entityId: id,
      oldValue: { status: review.status },
      newValue: { status, reason }
    });

    return { id, status };
  }
}
