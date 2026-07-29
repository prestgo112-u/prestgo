import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import { NOTIFICATION, NotificationEventsService } from "../notifications/notification-events.service.js";
import { SETTING, SETTING_DEFAULT } from "../settings/settings.keys.js";
import { SettingsService } from "../settings/settings.service.js";
import { ProviderRatingService } from "./provider-rating.service.js";

/**
 * Dépôt d'avis et signalements (§11) — la boucle de confiance.
 *
 * Sans cette pièce, la plateforme n'a pas de réputation : le client pouvait
 * LIRE les avis, jamais en déposer. Les notes affichées ne pouvaient donc
 * provenir que du jeu de démonstration.
 */
@Injectable()
export class ReviewSubmissionService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly settings: SettingsService,
    private readonly events: NotificationEventsService,
    private readonly rating: ProviderRatingService
  ) {}

  /**
   * Dépose un avis sur une mission terminée.
   *
   * Les garde-fous, dans l'ordre où ils comptent :
   *   - la mission doit être `completed` ou `closed` — noter une prestation qui
   *     n'a pas eu lieu n'aurait aucun sens ;
   *   - l'auteur doit être partie à la mission — sinon n'importe qui noterait
   *     n'importe qui ;
   *   - un seul avis par mission et par auteur, garanti aussi par une
   *     contrainte d'unicité en base ;
   *   - la fenêtre de dépôt est limitée : un avis déposé six mois plus tard ne
   *     dit plus rien d'utile.
   */
  async submit(missionId: string, authorId: string, dto: { rating: number; comment?: string }) {
    const mission = await this.prisma.mission.findUnique({
      where: { id: missionId },
      select: {
        id: true,
        status: true,
        clientId: true,
        provider: { select: { id: true, userId: true, publicName: true } },
        history: {
          where: { newStatus: "completed" },
          orderBy: { createdAt: "desc" },
          take: 1,
          select: { createdAt: true }
        }
      }
    });

    if (!mission) {
      throw new NotFoundException("Mission introuvable");
    }

    const isClient = mission.clientId === authorId;
    const isProvider = mission.provider?.userId === authorId;
    if (!isClient && !isProvider) {
      throw new ForbiddenException("Vous n'êtes pas partie à cette mission");
    }

    if (mission.status !== "completed" && mission.status !== "closed") {
      throw new BadRequestException("Vous pourrez déposer un avis une fois la mission terminée");
    }

    // V1 : seul le client note le prestataire (§11). `targetId` est déjà en
    // place pour la notation croisée, mais l'ouvrir maintenant reviendrait à
    // livrer une fonctionnalité non spécifiée.
    if (!isClient) {
      throw new ForbiddenException("Seul le client peut déposer un avis en V1");
    }

    const windowDays = await this.settings.getNumber(SETTING.reviewsWindowDays, SETTING_DEFAULT.reviewsWindowDays);
    const completedAt = mission.history[0]?.createdAt;
    if (completedAt) {
      const deadline = new Date(completedAt.getTime() + windowDays * 24 * 60 * 60_000);
      if (new Date() > deadline) {
        throw new BadRequestException(`La fenêtre de dépôt d'avis (${windowDays} jours) est dépassée`);
      }
    }

    const existing = await this.prisma.review.findFirst({
      where: { missionId, authorId },
      select: { id: true }
    });
    if (existing) {
      throw new ConflictException("Vous avez déjà déposé un avis sur cette mission");
    }

    const review = await this.prisma.review.create({
      data: {
        missionId,
        authorId,
        targetId: mission.provider?.userId,
        rating: dto.rating,
        comment: dto.comment?.trim(),
        // Publication immédiate, modération a posteriori (§11 et §6.3
        // inchangé) : retenir chaque avis en attente de relecture rendrait la
        // réputation inutilisable au lancement.
        status: "published"
      },
      select: { id: true, rating: true, comment: true, status: true, createdAt: true }
    });

    // La note du prestataire est recalculée dans la foulée : un avis déposé
    // qui ne bouge pas la moyenne affichée serait incompréhensible.
    if (mission.provider) {
      await this.rating.recompute(mission.provider.id);
    }

    await this.audit.record({
      actorId: authorId,
      action: "missions.review.submit",
      entity: "Review",
      entityId: review.id,
      newValue: { missionId, rating: dto.rating }
    });

    await this.events.notifyMany([mission.provider?.userId], {
      code: NOTIFICATION.reviewReceived,
      variables: { rating: dto.rating },
      data: { missionId, reviewId: review.id, type: "review" }
    });

    return review;
  }

  /** Les avis que J'AI déposés (§11). */
  async listMine(authorId: string, query: { page?: number; limit?: number }) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));
    const where = { authorId };

    const [data, total] = await Promise.all([
      this.prisma.review.findMany({
        where,
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * limit,
        take: limit,
        select: {
          id: true,
          rating: true,
          comment: true,
          status: true,
          createdAt: true,
          mission: {
            select: {
              id: true,
              scheduledAt: true,
              provider: { select: { id: true, publicName: true, avatarFileId: true } }
            }
          }
        }
      }),
      this.prisma.review.count({ where })
    ]);

    return { data, total, page, limit };
  }

  /**
   * Signale un avis (§11).
   *
   * L'avis passe en `reported` mais N'EST PAS MASQUÉ : seul un modérateur peut
   * décider de le retirer. Sinon, signaler suffirait à faire disparaître un
   * avis négatif — l'arme parfaite contre la critique légitime.
   */
  async report(reviewId: string, reporterId: string, reason: string) {
    const review = await this.prisma.review.findUnique({
      where: { id: reviewId },
      select: { id: true, status: true, authorId: true }
    });
    if (!review) {
      throw new NotFoundException("Avis introuvable");
    }
    if (review.authorId === reporterId) {
      throw new BadRequestException("Vous ne pouvez pas signaler votre propre avis");
    }

    const already = await this.prisma.reviewReport.findFirst({
      where: { reviewId, reportedBy: reporterId },
      select: { id: true }
    });
    if (already) {
      throw new ConflictException("Vous avez déjà signalé cet avis");
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.reviewReport.create({
        data: { reviewId, reportedBy: reporterId, reason: reason.trim(), status: "pending" }
      });
      // On ne repasse en `reported` que depuis `published` : un avis déjà
      // masqué ou rejeté par un modérateur ne doit pas remonter d'un cran.
      if (review.status === "published") {
        await tx.review.update({ where: { id: reviewId }, data: { status: "reported" } });
      }
    });

    await this.audit.record({
      actorId: reporterId,
      action: "reviews.report",
      entity: "Review",
      entityId: reviewId,
      newValue: { reason }
    });

    return { reported: true };
  }
}
