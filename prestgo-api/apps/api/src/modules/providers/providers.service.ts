import { Injectable, NotFoundException } from "@nestjs/common";
import type { Prisma, ProviderValidationStatus } from "@prisma/client";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { buildOrderBy, type SortAllowList } from "../../common/dto/sorting.js";
import { AuditService } from "../audit/audit.service.js";
import {
  NOTIFICATION,
  NotificationEventsService,
  type NotificationCode
} from "../notifications/notification-events.service.js";
import { assertTransition } from "./provider-status.machine.js";
import type {
  ProviderDetailDto,
  ProviderListItem,
  ProviderListQuery,
  ProviderStatusChangeDto,
  ProviderUpdateDto
} from "./provider.types.js";

@Injectable()
export class ProvidersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly events: NotificationEventsService
  ) {}

  /** Colonnes triables de la liste prestataires (§15.4). */
  private static readonly SORTABLE: SortAllowList = {
    createdAt: { path: ["createdAt"], defaultDirection: "desc" },
    publicName: ["publicName"],
    score: { path: ["score"], defaultDirection: "desc" },
    reviewsCount: { path: ["reviewsCount"], defaultDirection: "desc" },
    validationStatus: ["validationStatus"]
  };

  // Liste paginée des prestataires, filtrable par statut de validation et recherche.
  async list(query: ProviderListQuery): Promise<{ data: ProviderListItem[]; total: number; page: number; limit: number }> {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));

    const where: Record<string, unknown> = {};
    if (query.validationStatus) {
      where.validationStatus = query.validationStatus;
    }
    if (query.search?.trim()) {
      // Le CDC demande de chercher par nom, email ET téléphone.
      const search = query.search.trim();
      where.OR = [
        { publicName: { contains: search, mode: "insensitive" } },
        { user: { email: { contains: search, mode: "insensitive" } } },
        { user: { phone: { contains: search, mode: "insensitive" } } }
      ];
    }

    const [rows, total] = await Promise.all([
      this.prisma.providerProfile.findMany({
        where,
        include: { user: { select: { email: true } } },
        // `sort` réellement appliqué (§15.4), sur une liste blanche de colonnes.
        orderBy: buildOrderBy<Prisma.ProviderProfileOrderByWithRelationInput>(
          query.sort,
          ProvidersService.SORTABLE,
          { createdAt: "desc" }
        ),
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.providerProfile.count({ where })
    ]);

    const data = rows.map((row) => ({
      id: row.id,
      userId: row.userId,
      publicName: row.publicName,
      validationStatus: row.validationStatus,
      availabilityStatus: row.availabilityStatus,
      score: row.score,
      email: row.user.email ?? undefined,
      createdAt: row.createdAt
    }));

    return { data, total, page, limit };
  }

  // Détail d'un prestataire : profil + documents + notes internes.
  async findById(id: string): Promise<ProviderDetailDto> {
    const provider = await this.prisma.providerProfile.findUnique({
      where: { id },
      include: {
        user: { select: { email: true } },
        documents: { orderBy: { createdAt: "desc" } },
        notes: { orderBy: { createdAt: "desc" } }
      }
    });

    if (!provider) {
      throw new NotFoundException("Prestataire introuvable");
    }

    return {
      id: provider.id,
      userId: provider.userId,
      publicName: provider.publicName,
      validationStatus: provider.validationStatus,
      availabilityStatus: provider.availabilityStatus,
      score: provider.score,
      email: provider.user.email ?? undefined,
      bio: provider.bio ?? undefined,
      experienceYears: provider.experienceYears ?? undefined,
      createdAt: provider.createdAt,
      documents: provider.documents.map((doc) => ({
        id: doc.id,
        type: doc.type,
        status: doc.status,
        fileId: doc.fileId ?? undefined,
        rejectionReason: doc.rejectionReason ?? undefined,
        reviewedBy: doc.reviewedBy ?? undefined,
        reviewedAt: doc.reviewedAt ?? undefined,
        createdAt: doc.createdAt
      })),
      notes: provider.notes.map((note) => ({
        id: note.id,
        note: note.note,
        authorId: note.authorId ?? undefined,
        createdAt: note.createdAt
      }))
    };
  }

  /**
   * Ajoute une note interne sur un prestataire.
   *
   * « Interne » = visible uniquement du back-office, jamais du prestataire.
   * Le modèle existait déjà en base, mais aucune route ne permettait d'écrire
   * dedans : les notes affichées étaient donc toujours vides.
   */
  async addNote(providerId: string, note: string, actorId?: string) {
    const provider = await this.prisma.providerProfile.findUnique({ where: { id: providerId } });
    if (!provider) {
      throw new NotFoundException("Prestataire introuvable");
    }

    const created = await this.prisma.providerInternalNote.create({
      data: { providerId, authorId: actorId, note: note.trim() }
    });

    await this.audit.record({
      actorId,
      action: "admin.providers.note.add",
      entity: "ProviderInternalNote",
      entityId: created.id,
      newValue: { providerId, note: created.note }
    });

    return created;
  }

  // Change le statut de validation en respectant les transitions autorisées.
  async changeStatus(id: string, dto: ProviderStatusChangeDto, actorId?: string): Promise<ProviderDetailDto> {
    const provider = await this.prisma.providerProfile.findUnique({ where: { id } });
    if (!provider) {
      throw new NotFoundException("Prestataire introuvable");
    }

    // Vérifie que la transition est permise ET qu'un motif est fourni si nécessaire.
    assertTransition(provider.validationStatus, dto.status, dto.reason);

    await this.prisma.providerProfile.update({
      where: { id },
      data: {
        validationStatus: dto.status,
        // Le motif est conservé sur le profil et devient visible du
        // prestataire dans `GET /providers/me` (§5). Sans cela, un dossier en
        // « corrections demandées » n'indiquait pas QUOI corriger : le
        // prestataire re-soumettait à l'identique, et l'agent le rejetait de
        // nouveau.
        rejectionReason: dto.reason ?? null
      }
    });

    await this.audit.record({
      actorId,
      action: "admin.providers.status.update",
      entity: "ProviderProfile",
      entityId: id,
      oldValue: { validationStatus: provider.validationStatus },
      newValue: { validationStatus: dto.status, reason: dto.reason }
    });

    // Le prestataire est PRÉVENU de la décision (§12). Sans notification, il
    // devrait consulter son dossier au hasard pour découvrir qu'il est validé
    // — ou qu'on attend une correction de sa part.
    const code = PROVIDER_DECISION_NOTIFICATIONS[dto.status];
    if (code) {
      await this.events.notify({
        userId: provider.userId,
        code,
        variables: { reason: dto.reason ?? "" },
        data: { providerId: id, type: "provider" }
      });
    }

    return this.findById(id);
  }

  // Met à jour les champs éditables par l'admin (nom public, bio, expérience).
  async updateFields(id: string, dto: ProviderUpdateDto, actorId?: string): Promise<ProviderDetailDto> {
    const provider = await this.prisma.providerProfile.findUnique({ where: { id } });
    if (!provider) {
      throw new NotFoundException("Prestataire introuvable");
    }

    await this.prisma.providerProfile.update({
      where: { id },
      data: {
        publicName: dto.publicName ?? provider.publicName,
        bio: dto.bio ?? provider.bio,
        experienceYears: dto.experienceYears ?? provider.experienceYears,
        resubmissionBlocked: dto.resubmissionBlocked ?? provider.resubmissionBlocked
      }
    });

    await this.audit.record({
      actorId,
      action: "admin.providers.update",
      entity: "ProviderProfile",
      entityId: id,
      newValue: dto
    });

    return this.findById(id);
  }
}

/**
 * Modèle de notification envoyé au prestataire selon la décision de l'agent.
 *
 * `pending_review` et `profile_incomplete` n'y figurent pas : ce sont des états
 * que le prestataire provoque lui-même, il n'a pas à être notifié de sa propre
 * action. `suspended` non plus — une suspension s'accompagne d'un contact
 * humain, pas d'un message automatique.
 */
const PROVIDER_DECISION_NOTIFICATIONS: Partial<Record<ProviderValidationStatus, NotificationCode>> = {
  approved: NOTIFICATION.providerApproved,
  changes_requested: NOTIFICATION.providerChangesRequested,
  rejected: NOTIFICATION.providerRejected
};