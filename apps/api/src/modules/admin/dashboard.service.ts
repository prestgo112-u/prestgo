import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";

// Les 8 cartes statistiques demandées par le CDC §4.2.
export interface DashboardSummary {
  totalUsers: number;
  activeUsers: number;
  approvedProviders: number;
  pendingProviders: number;
  missionsToday: number;
  missionsInProgress: number;
  openDisputes: number;
  reviewsToModerate: number;
  recentActivity: {
    action: string;
    entity: string;
    entityId?: string;
    actorId?: string;
    createdAt: Date;
  }[];
  // Listes rapides (CDC §4.2).
  latestProviders: { id: string; publicName: string; validationStatus: string; createdAt: Date }[];
  latestDisputes: { id: string; reason: string; status: string; createdAt: Date }[];
  documentsToReview: { id: string; type: string; providerName: string; createdAt: Date }[];
}

export interface DashboardCharts {
  // Inscriptions par jour sur la période demandée.
  signupsByDay: { label: string; value: number }[];
  // Missions par catégorie de service.
  missionsByCategory: { label: string; value: number }[];
  // Missions par zone (ville de l'adresse d'intervention).
  missionsByCity: { label: string; value: number }[];
  // Répartition des missions par statut.
  missionsByStatus: { label: string; value: number }[];
  // Indicateurs calculés.
  cancellationRate: number;
  averageValidationHours: number | null;
}

@Injectable()
export class DashboardService {
  constructor(private readonly prisma: PrismaService) {}

  // Calcule les chiffres clés affichés sur le tableau de bord.
  async summary(): Promise<DashboardSummary> {
    // Bornes de la journée en cours, pour compter les missions « du jour ».
    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);
    const endOfDay = new Date(startOfDay);
    endOfDay.setDate(endOfDay.getDate() + 1);

    // Promise.all lance les requêtes en parallèle (plus rapide qu'une par une).
    const [
      totalUsers,
      activeUsers,
      approvedProviders,
      pendingProviders,
      missionsToday,
      missionsInProgress,
      openDisputes,
      reviewsToModerate,
      recentLogs,
      latestProviders,
      latestDisputes,
      documentsToReview
    ] = await Promise.all([
      this.prisma.user.count(),
      this.prisma.user.count({ where: { status: "active" } }),
      this.prisma.providerProfile.count({ where: { validationStatus: "approved" } }),
      // Avant le Lot 2, cette carte comptait les UTILISATEURS au statut "pending",
      // ce qui n'avait rien à voir avec le nombre de prestataires à valider.
      this.prisma.providerProfile.count({ where: { validationStatus: "pending_review" } }),
      this.prisma.mission.count({ where: { scheduledAt: { gte: startOfDay, lt: endOfDay } } }),
      this.prisma.mission.count({ where: { status: "in_progress" } }),
      this.prisma.dispute.count({ where: { status: { in: ["open", "in_review", "waiting_client", "waiting_provider"] } } }),
      this.prisma.review.count({ where: { status: "reported" } }),
      this.prisma.auditLog.findMany({ orderBy: { createdAt: "desc" }, take: 10 }),
      this.prisma.providerProfile.findMany({
        orderBy: { createdAt: "desc" },
        take: 5,
        select: { id: true, publicName: true, validationStatus: true, createdAt: true }
      }),
      this.prisma.dispute.findMany({
        orderBy: { createdAt: "desc" },
        take: 5,
        select: { id: true, reason: true, status: true, createdAt: true }
      }),
      this.prisma.providerDocument.findMany({
        where: { status: "pending" },
        orderBy: { createdAt: "asc" },
        take: 5,
        select: { id: true, type: true, createdAt: true, provider: { select: { publicName: true } } }
      })
    ]);

    return {
      totalUsers,
      activeUsers,
      approvedProviders,
      pendingProviders,
      missionsToday,
      missionsInProgress,
      openDisputes,
      reviewsToModerate,
      recentActivity: recentLogs.map((log) => ({
        action: log.action,
        entity: log.entity,
        entityId: log.entityId ?? undefined,
        actorId: log.actorId ?? undefined,
        createdAt: log.createdAt
      })),
      latestProviders,
      latestDisputes,
      documentsToReview: documentsToReview.map((doc) => ({
        id: doc.id,
        type: doc.type,
        providerName: doc.provider.publicName,
        createdAt: doc.createdAt
      }))
    };
  }

  /**
   * Données des graphiques (CDC §4.2).
   *
   * `days` = profondeur d'historique pour la courbe des inscriptions.
   */
  async charts(days = 30): Promise<DashboardCharts> {
    const since = new Date();
    since.setHours(0, 0, 0, 0);
    since.setDate(since.getDate() - (days - 1));

    const [users, missions, approvedDocuments] = await Promise.all([
      this.prisma.user.findMany({ where: { createdAt: { gte: since } }, select: { createdAt: true } }),
      this.prisma.mission.findMany({
        select: {
          status: true,
          address: { select: { city: true } },
          pack: { select: { providerService: { select: { serviceType: { select: { name: true } } } } } }
        }
      }),
      // Pour le délai moyen de validation : documents revus, avec leur date de dépôt.
      this.prisma.providerDocument.findMany({
        where: { reviewedAt: { not: null } },
        select: { createdAt: true, reviewedAt: true }
      })
    ]);

    // --- Inscriptions par jour ---
    // On prépare une case par jour (même à zéro), sinon la courbe aurait des trous.
    const signupBuckets = new Map<string, number>();
    for (let index = 0; index < days; index += 1) {
      const day = new Date(since);
      day.setDate(day.getDate() + index);
      signupBuckets.set(day.toISOString().slice(0, 10), 0);
    }
    for (const user of users) {
      const key = user.createdAt.toISOString().slice(0, 10);
      if (signupBuckets.has(key)) {
        signupBuckets.set(key, (signupBuckets.get(key) ?? 0) + 1);
      }
    }

    // --- Répartitions ---
    const byCategory = new Map<string, number>();
    const byCity = new Map<string, number>();
    const byStatus = new Map<string, number>();
    let cancelled = 0;

    for (const mission of missions) {
      const category = mission.pack?.providerService?.serviceType?.name ?? "Non catégorisé";
      byCategory.set(category, (byCategory.get(category) ?? 0) + 1);

      const city = mission.address?.city ?? "Non renseignée";
      byCity.set(city, (byCity.get(city) ?? 0) + 1);

      byStatus.set(mission.status, (byStatus.get(mission.status) ?? 0) + 1);

      if (mission.status === "cancelled") {
        cancelled += 1;
      }
    }

    // --- Délai moyen de validation d'un document, en heures ---
    let averageValidationHours: number | null = null;
    if (approvedDocuments.length > 0) {
      const totalMs = approvedDocuments.reduce(
        (sum, doc) => sum + (doc.reviewedAt!.getTime() - doc.createdAt.getTime()),
        0
      );
      averageValidationHours = Math.round((totalMs / approvedDocuments.length / 3_600_000) * 10) / 10;
    }

    return {
      signupsByDay: [...signupBuckets].map(([label, value]) => ({ label, value })),
      missionsByCategory: toSortedSeries(byCategory),
      missionsByCity: toSortedSeries(byCity),
      missionsByStatus: toSortedSeries(byStatus),
      cancellationRate: missions.length > 0 ? Math.round((cancelled / missions.length) * 1000) / 10 : 0,
      averageValidationHours
    };
  }
}

// Transforme un compteur en série triée du plus grand au plus petit.
function toSortedSeries(counts: Map<string, number>): { label: string; value: number }[] {
  return [...counts]
    .map(([label, value]) => ({ label, value }))
    .sort((a, b) => b.value - a.value);
}
