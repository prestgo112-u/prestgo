import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import type { MissionStatus, Prisma } from "@prisma/client";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { buildOrderBy, type SortAllowList } from "../../common/dto/sorting.js";
import { AuditService } from "../audit/audit.service.js";
import { MissionLifecycleService } from "./mission-lifecycle.service.js";

@Injectable()
export class MissionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly lifecycle: MissionLifecycleService
  ) {}

  /**
   * Colonnes sur lesquelles la liste des missions accepte d'être triée (§15.4).
   *
   * Liste blanche volontairement courte : `sort` ne doit pas devenir un moyen
   * de trier sur n'importe quelle colonne de la base.
   */
  private static readonly SORTABLE: SortAllowList = {
    createdAt: { path: ["createdAt"], defaultDirection: "desc" },
    scheduledAt: { path: ["scheduledAt"], defaultDirection: "asc" },
    status: ["status"],
    amount: ["quotedAmount"]
  };

  // Liste paginée des missions, filtrable par statut, période, prestataire et recherche.
  async list(query: {
    page?: number;
    limit?: number;
    sort?: string;
    status?: MissionStatus;
    from?: string;
    to?: string;
    providerId?: string;
    search?: string;
  }) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));

    const where: Prisma.MissionWhereInput = {};
    if (query.status) {
      where.status = query.status;
    }
    if (query.providerId) {
      where.providerId = query.providerId;
    }
    if (query.from || query.to) {
      const scheduledAt: Prisma.DateTimeNullableFilter = {};
      if (query.from) {
        scheduledAt.gte = new Date(query.from);
      }
      if (query.to) {
        // La borne de fin est inclusive : on prend tout le jour indiqué en
        // décalant d'un jour et en comparant en « strictement inférieur ».
        const to = new Date(query.to);
        to.setDate(to.getDate() + 1);
        scheduledAt.lt = to;
      }
      where.scheduledAt = scheduledAt;
    }
    if (query.search?.trim()) {
      const search = query.search.trim();
      where.OR = [
        { client: { email: { contains: search, mode: "insensitive" } } },
        { client: { firstName: { contains: search, mode: "insensitive" } } },
        { client: { lastName: { contains: search, mode: "insensitive" } } },
        { provider: { publicName: { contains: search, mode: "insensitive" } } },
        { address: { city: { contains: search, mode: "insensitive" } } }
      ];
    }

    const [rows, total] = await Promise.all([
      this.prisma.mission.findMany({
        where,
        include: {
          client: { select: { firstName: true, lastName: true, email: true } },
          provider: { select: { publicName: true } },
          pack: { select: { title: true, price: true } },
          address: { select: { city: true, commune: true } }
        },
        // `sort` est désormais réellement APPLIQUÉ (§15.4). Auparavant il était
        // validé puis ignoré : l'API absorbait le paramètre sans effet, ce qui
        // laissait croire au front que le tri fonctionnait.
        orderBy: buildOrderBy<Prisma.MissionOrderByWithRelationInput>(
          query.sort,
          MissionsService.SORTABLE,
          { createdAt: "desc" }
        ),
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.mission.count({ where })
    ]);

    const data = rows.map((m) => ({
      id: m.id,
      status: m.status,
      scheduledAt: m.scheduledAt,
      clientName: [m.client.firstName, m.client.lastName].filter(Boolean).join(" ") || m.client.email || "—",
      providerName: m.provider?.publicName ?? "—",
      packTitle: m.pack?.title ?? "—",
      city: m.address?.city ?? "—",
      createdAt: m.createdAt
    }));

    return { data, total, page, limit };
  }

  // Détail d'une mission avec son historique de statuts et ses annulations/reports.
  async findById(id: string) {
    const mission = await this.prisma.mission.findUnique({
      where: { id },
      include: {
        client: { select: { firstName: true, lastName: true, email: true } },
        provider: { select: { publicName: true } },
        // Lot 1 : la prestation vendue et le lieu d'intervention.
        pack: {
          select: {
            id: true,
            title: true,
            price: true,
            durationMinutes: true,
            providerService: { select: { title: true, serviceType: { select: { name: true } } } }
          }
        },
        address: { select: { id: true, label: true, city: true, commune: true, details: true } },
        history: { orderBy: { createdAt: "desc" } },
        reschedules: { orderBy: { createdAt: "desc" } },
        cancellation: true
      }
    });
    if (!mission) {
      throw new NotFoundException("Mission introuvable");
    }
    return mission;
  }

  /**
   * Historique des statuts d'une mission, du plus ancien au plus récent.
   *
   * Le contrôle d'accès est fait par l'appelant (MissionAccessService) : ce
   * service ne sait pas qui demande, il ne fait que lire.
   */
  async history(missionId: string) {
    const rows = await this.prisma.missionStatusHistory.findMany({
      where: { missionId },
      orderBy: { createdAt: "asc" },
      select: { id: true, oldStatus: true, newStatus: true, reason: true, createdAt: true }
    });

    const reschedules = await this.prisma.missionReschedule.findMany({
      where: { missionId },
      orderBy: { createdAt: "asc" },
      select: { id: true, oldScheduledAt: true, newScheduledAt: true, reason: true, createdAt: true }
    });

    return { statusHistory: rows, reschedules };
  }

  /**
   * Change le statut d'une mission depuis le back-office.
   *
   * Depuis le Lot 6, cette méthode DÉLÈGUE au service de transition commun
   * (§14.1). L'admin, le client, le prestataire et les jobs planifiés
   * empruntent donc exactement le même chemin : même machine à états, même
   * historique, même message de refus, mêmes notifications. Auparavant, la
   * logique vivait ici et aurait dû être recopiée pour la surface mobile —
   * avec la garantie qu'elle finirait par diverger.
   */
  async changeStatus(id: string, status: MissionStatus, reason: string | undefined, actorId?: string) {
    await this.lifecycle.transition(
      id,
      status,
      { id: actorId, kind: "admin" },
      { reason, auditAction: "admin.missions.status.update" }
    );
    return this.findById(id);
  }

  // Reporte une mission à une nouvelle date (garde une trace du report).
  async reschedule(id: string, newScheduledAt: string, reason: string | undefined, actorId?: string) {
    const mission = await this.prisma.mission.findUnique({ where: { id } });
    if (!mission) {
      throw new NotFoundException("Mission introuvable");
    }
    const newDate = new Date(newScheduledAt);
    if (Number.isNaN(newDate.getTime())) {
      throw new BadRequestException("Date de report invalide");
    }

    await this.prisma.$transaction([
      this.prisma.missionReschedule.create({
        data: { missionId: id, oldScheduledAt: mission.scheduledAt, newScheduledAt: newDate, reason, createdBy: actorId }
      }),
      this.prisma.mission.update({ where: { id }, data: { scheduledAt: newDate } })
    ]);

    await this.audit.record({
      actorId,
      action: "admin.missions.reschedule",
      entity: "Mission",
      entityId: id,
      oldValue: { scheduledAt: mission.scheduledAt },
      newValue: { scheduledAt: newDate, reason }
    });

    return this.findById(id);
  }

  /**
   * Annule une mission depuis le back-office : le motif est obligatoire.
   *
   * Comme `changeStatus`, l'annulation passe par le service commun — ce qui
   * lui fait bénéficier au passage du marquage « annulation tardive » (§8) et
   * des notifications aux deux parties, sans les réécrire ici.
   */
  async cancel(id: string, reason: string, actorId?: string) {
    if (!reason || reason.trim() === "") {
      throw new BadRequestException("Un motif d'annulation est obligatoire");
    }

    await this.lifecycle.transition(
      id,
      "cancelled",
      { id: actorId, kind: "admin" },
      { reason, auditAction: "admin.missions.cancel" }
    );

    return this.findById(id);
  }
}
