import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import type { DisputeStatus, Prisma } from "@prisma/client";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import { assertTransition } from "./dispute-status.machine.js";

@Injectable()
export class DisputesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  // Liste paginée des litiges, filtrable par statut, agent assigné et recherche.
  async list(query: { page?: number; limit?: number; status?: DisputeStatus; assignedTo?: string; search?: string }) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));

    const where: Prisma.DisputeWhereInput = {};
    if (query.status) {
      where.status = query.status;
    }
    if (query.assignedTo) {
      where.assignedTo = query.assignedTo;
    }
    if (query.search?.trim()) {
      const search = query.search.trim();
      where.OR = [
        { reason: { contains: search, mode: "insensitive" } },
        { description: { contains: search, mode: "insensitive" } }
      ];
    }

    const [rows, total] = await Promise.all([
      this.prisma.dispute.findMany({
        where,
        include: {
          mission: {
            select: {
              id: true,
              status: true,
              client: { select: { firstName: true, lastName: true, email: true } },
              provider: { select: { publicName: true } }
            }
          }
        },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.dispute.count({ where })
    ]);

    const data = rows.map((dispute) => ({
      id: dispute.id,
      missionId: dispute.missionId,
      reason: dispute.reason,
      status: dispute.status,
      assignedTo: dispute.assignedTo,
      decision: dispute.decision,
      createdAt: dispute.createdAt,
      clientName:
        [dispute.mission.client.firstName, dispute.mission.client.lastName].filter(Boolean).join(" ") ||
        dispute.mission.client.email ||
        "—",
      providerName: dispute.mission.provider?.publicName ?? "—"
    }));

    return { data, total, page, limit };
  }

  // Détail d'un litige avec ses messages.
  /**
   * Détail d'un litige.
   *
   * `includeInternal` distingue les deux publics (CDC §4.5) :
   *   - le back-office voit tout, y compris les commentaires internes ;
   *   - le client et le prestataire ne voient que les messages qui leur sont
   *     destinés, et les pièces jointes.
   *
   * Le paramètre vaut `false` par défaut : si un appelant oublie de le
   * préciser, on montre le MOINS de choses possible, jamais l'inverse.
   */
  async findById(id: string, includeInternal = false) {
    const dispute = await this.prisma.dispute.findUnique({
      where: { id },
      include: {
        messages: {
          where: includeInternal ? {} : { internalOnly: false },
          orderBy: { createdAt: "asc" }
        },
        files: { include: { file: { select: { id: true, originalName: true, mimeType: true, size: true } } } }
      }
    });
    if (!dispute) {
      throw new NotFoundException("Litige introuvable");
    }

    // On aplatit les pièces jointes pour éviter un niveau d'imbrication inutile.
    return {
      ...dispute,
      files: dispute.files.map((link) => link.file)
    };
  }

  // Ouvre un nouveau litige rattaché à une mission.
  async open(dto: { missionId: string; reason: string; description?: string }, actorId?: string) {
    if (!dto.reason || dto.reason.trim() === "") {
      throw new BadRequestException("Un motif est obligatoire pour ouvrir un litige");
    }
    const dispute = await this.prisma.dispute.create({
      data: {
        missionId: dto.missionId,
        reason: dto.reason,
        description: dto.description,
        openedBy: actorId,
        status: "open"
      }
    });

    await this.audit.record({ actorId, action: "disputes.open", entity: "Dispute", entityId: dispute.id, newValue: dto });
    return dispute;
  }

  // Assigne le litige à un agent de support.
  async assign(id: string, assignedTo: string, actorId?: string) {
    const dispute = await this.prisma.dispute.findUnique({ where: { id } });
    if (!dispute) {
      throw new NotFoundException("Litige introuvable");
    }
    await this.prisma.dispute.update({ where: { id }, data: { assignedTo } });
    await this.audit.record({
      actorId,
      action: "admin.disputes.assign",
      entity: "Dispute",
      entityId: id,
      newValue: { assignedTo }
    });
    return this.findById(id);
  }

  // Change le statut du litige (transition contrôlée ; décision requise pour résoudre/rejeter/clôturer).
  async changeStatus(id: string, status: DisputeStatus, reason: string | undefined, decision: string | undefined, actorId?: string) {
    const dispute = await this.prisma.dispute.findUnique({ where: { id } });
    if (!dispute) {
      throw new NotFoundException("Litige introuvable");
    }
    // La décision OU le motif satisfait l'exigence de justification.
    assertTransition(dispute.status, status, decision ?? reason);

    await this.prisma.dispute.update({
      where: { id },
      data: { status, decision: decision ?? dispute.decision }
    });

    await this.audit.record({
      actorId,
      action: "admin.disputes.status.update",
      entity: "Dispute",
      entityId: id,
      oldValue: { status: dispute.status },
      newValue: { status, reason, decision }
    });

    return this.findById(id);
  }

  // Ajoute un message dans le fil d'un litige.
  async addMessage(id: string, message: string, actorId?: string, internalOnly = false) {
    if (!message || message.trim() === "") {
      throw new BadRequestException("Le message ne peut pas être vide");
    }
    const dispute = await this.prisma.dispute.findUnique({ where: { id } });
    if (!dispute) {
      throw new NotFoundException("Litige introuvable");
    }
    await this.prisma.disputeMessage.create({
      data: { disputeId: id, senderId: actorId, message, internalOnly }
    });
    // L'appelant est le back-office : il doit revoir tout le fil, commentaires
    // internes compris.
    return this.findById(id, true);
  }

  /**
   * Attache une preuve à un litige (photo, facture, capture d'écran).
   *
   * Le fichier doit avoir été déposé au préalable via `POST /files/upload` :
   * on ne fait ici que le rattacher. `upsert` rend l'opération rejouable sans
   * créer de doublon.
   */
  async attachFile(id: string, fileId: string, actorId?: string) {
    const dispute = await this.prisma.dispute.findUnique({ where: { id } });
    if (!dispute) {
      throw new NotFoundException("Litige introuvable");
    }

    const file = await this.prisma.file.findUnique({ where: { id: fileId } });
    if (!file || file.disabledAt) {
      throw new NotFoundException("Fichier introuvable");
    }

    await this.prisma.disputeFile.upsert({
      where: { disputeId_fileId: { disputeId: id, fileId } },
      update: {},
      create: { disputeId: id, fileId }
    });

    await this.audit.record({
      actorId,
      action: "admin.disputes.file.attach",
      entity: "Dispute",
      entityId: id,
      newValue: { fileId, originalName: file.originalName }
    });

    return this.findById(id, true);
  }
}
