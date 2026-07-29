import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";

/**
 * Recalcul de la réputation d'un prestataire (§11).
 *
 * `provider_profiles.score` et `reviews_count` sont des valeurs dénormalisées :
 * elles évitent de recompter les avis à chaque ligne de résultat de recherche.
 * Le revers est qu'il faut les tenir à jour — d'où ce service unique, appelé
 * au dépôt d'un avis ET à chaque décision de modération.
 *
 * Le point important est le second : masquer un avis d'une étoile doit REMONTER
 * la note. Un recalcul fait au dépôt seulement laisserait la moyenne inclure à
 * jamais des avis retirés, ce qui viderait la modération de son effet.
 */
@Injectable()
export class ProviderRatingService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Recalcule note et nombre d'avis d'un prestataire.
   *
   * Seuls les avis `published` comptent. Un avis `reported` continue d'être
   * pris en compte : signaler ne doit pas suffire à faire bouger la note d'un
   * concurrent (§11 — l'avis reste visible tant qu'un modérateur n'a pas
   * tranché).
   */
  async recompute(providerId: string): Promise<{ score: number; reviewsCount: number }> {
    const where = { status: "published" as const, mission: { providerId } };

    const [aggregate, count] = await Promise.all([
      this.prisma.review.aggregate({ where, _avg: { rating: true } }),
      this.prisma.review.count({ where })
    ]);

    // Aucun avis publié : la note retombe à 0, pas à une valeur héritée.
    // Le nombre d'avis, renvoyé à côté, dit qu'il s'agit d'une absence de note
    // et non d'une mauvaise note.
    const score = aggregate._avg.rating != null ? Math.round(aggregate._avg.rating * 100) / 100 : 0;

    await this.prisma.providerProfile.update({
      where: { id: providerId },
      data: { score, reviewsCount: count }
    });

    return { score, reviewsCount: count };
  }

  /** Recalcule à partir d'un avis (cas de la modération, qui ne connaît que lui). */
  async recomputeFromReview(reviewId: string): Promise<void> {
    const review = await this.prisma.review.findUnique({
      where: { id: reviewId },
      select: { mission: { select: { providerId: true } } }
    });
    const providerId = review?.mission.providerId;
    if (providerId) {
      await this.recompute(providerId);
    }
  }
}
