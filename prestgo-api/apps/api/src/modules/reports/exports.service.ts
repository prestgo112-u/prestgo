import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import { FileStorageService } from "../files/file-storage.service.js";
import { buildCsv } from "./csv.js";

// Types d'export proposés par le back-office (CDC §4.1 : « CSV/Excel : comptes,
// prestataires, missions, litiges, avis »).
export const EXPORT_TYPES = ["users", "providers", "missions", "disputes", "reviews"] as const;
export type ExportType = (typeof EXPORT_TYPES)[number];

@Injectable()
export class ExportsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly storage: FileStorageService
  ) {}

  /**
   * Crée une demande d'export, GÉNÈRE RÉELLEMENT le fichier CSV, puis clôt le job.
   *
   * Avant le Lot 1, cette méthode créait une ligne `File` de taille 0 sans jamais
   * écrire le moindre octet : l'export était donc inutilisable.
   */
  async create(dto: { type: string; filters?: unknown }, actorId?: string) {
    const type = this.parseType(dto.type);

    const job = await this.prisma.exportJob.create({
      data: {
        requestedBy: actorId,
        type,
        filters: (dto.filters ?? {}) as object,
        status: "pending"
      }
    });

    try {
      const csv = await this.buildContent(type);
      const content = Buffer.from(csv, "utf8");
      const storageKey = `exports/${job.id}.csv`;

      await this.storage.save(storageKey, content);

      // Le fichier est "restricted" : depuis le Lot 0, seul son propriétaire
      // (celui qui a demandé l'export) ou un admin porteur de `files.any.read`
      // peut le lire.
      const file = await this.prisma.file.create({
        data: {
          ownerId: actorId,
          originalName: `${type}-${job.id}.csv`,
          mimeType: "text/csv",
          size: content.length,
          storageKey,
          visibility: "restricted"
        }
      });

      const completed = await this.prisma.exportJob.update({
        where: { id: job.id },
        data: { status: "completed", fileId: file.id, completedAt: new Date() }
      });

      await this.audit.record({
        actorId,
        action: "admin.exports.create",
        entity: "ExportJob",
        entityId: job.id,
        newValue: { type, size: content.length }
      });

      return completed;
    } catch (error) {
      // Si la génération échoue, le job doit le refléter au lieu de rester
      // bloqué en "pending" pour toujours.
      await this.prisma.exportJob.update({ where: { id: job.id }, data: { status: "failed" } });
      throw error;
    }
  }

  // Liste paginée des exports.
  async list(query: { page?: number; limit?: number } = {}) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));

    const [data, total] = await Promise.all([
      this.prisma.exportJob.findMany({
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.exportJob.count()
    ]);

    return { data, total, page, limit };
  }

  // Récupère le statut d'un export.
  async findById(id: string) {
    const job = await this.prisma.exportJob.findUnique({ where: { id } });
    if (!job) {
      throw new NotFoundException("Export introuvable");
    }
    return job;
  }

  private parseType(value: string): ExportType {
    const type = (value || "").trim() as ExportType;
    if (!EXPORT_TYPES.includes(type)) {
      throw new BadRequestException(`Type d'export inconnu. Valeurs acceptées : ${EXPORT_TYPES.join(", ")}`);
    }
    return type;
  }

  // Construit le contenu CSV correspondant au type demandé.
  private async buildContent(type: ExportType): Promise<string> {
    switch (type) {
      case "users":
        return this.usersCsv();
      case "providers":
        return this.providersCsv();
      case "missions":
        return this.missionsCsv();
      case "disputes":
        return this.disputesCsv();
      case "reviews":
        return this.reviewsCsv();
    }
  }

  private async usersCsv(): Promise<string> {
    const rows = await this.prisma.user.findMany({
      orderBy: { createdAt: "desc" },
      include: { roles: { include: { role: { select: { code: true } } } } }
    });
    return buildCsv(
      ["id", "email", "prenom", "nom", "telephone", "statut", "roles", "cree_le"],
      rows.map((u) => [
        u.id,
        u.email,
        u.firstName,
        u.lastName,
        u.phone,
        u.status,
        u.roles.map((r) => r.role.code).join(" | "),
        u.createdAt
      ])
    );
  }

  private async providersCsv(): Promise<string> {
    const rows = await this.prisma.providerProfile.findMany({
      orderBy: { createdAt: "desc" },
      include: { user: { select: { email: true, phone: true, status: true } } }
    });
    return buildCsv(
      ["id", "nom_public", "email", "telephone", "statut_validation", "disponibilite", "score", "annees_experience", "cree_le"],
      rows.map((p) => [
        p.id,
        p.publicName,
        p.user.email,
        p.user.phone,
        p.validationStatus,
        p.availabilityStatus,
        p.score,
        p.experienceYears,
        p.createdAt
      ])
    );
  }

  private async missionsCsv(): Promise<string> {
    const rows = await this.prisma.mission.findMany({
      orderBy: { createdAt: "desc" },
      include: {
        client: { select: { email: true, firstName: true, lastName: true } },
        provider: { select: { publicName: true } },
        pack: { select: { title: true, price: true, durationMinutes: true } },
        address: { select: { city: true, commune: true } }
      }
    });
    return buildCsv(
      ["id", "statut", "client", "prestataire", "prestation", "prix", "duree_min", "ville", "commune", "planifiee_le", "creee_le"],
      rows.map((m) => [
        m.id,
        m.status,
        [m.client.firstName, m.client.lastName].filter(Boolean).join(" ") || m.client.email,
        m.provider?.publicName,
        m.pack?.title,
        m.pack?.price,
        m.pack?.durationMinutes,
        m.address?.city,
        m.address?.commune,
        m.scheduledAt,
        m.createdAt
      ])
    );
  }

  private async disputesCsv(): Promise<string> {
    const rows = await this.prisma.dispute.findMany({ orderBy: { createdAt: "desc" } });
    return buildCsv(
      ["id", "mission_id", "statut", "motif", "assigne_a", "decision", "cree_le"],
      rows.map((d) => [d.id, d.missionId, d.status, d.reason, d.assignedTo, d.decision, d.createdAt])
    );
  }

  private async reviewsCsv(): Promise<string> {
    const rows = await this.prisma.review.findMany({ orderBy: { createdAt: "desc" } });
    return buildCsv(
      ["id", "mission_id", "note", "statut", "commentaire", "cree_le"],
      rows.map((r) => [r.id, r.missionId, r.rating, r.status, r.comment, r.createdAt])
    );
  }
}
