import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import type { DocumentStatus, Prisma } from "@prisma/client";
import { randomUUID } from "node:crypto";
import { extname } from "node:path";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import { FileStorageService } from "../files/file-storage.service.js";

@Injectable()
export class ProviderDocumentsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly storage: FileStorageService
  ) {}

  /**
   * File d'attente de vérification, TOUS prestataires confondus.
   *
   * C'est la vue qui manquait : jusqu'ici il fallait ouvrir chaque prestataire
   * un par un pour découvrir s'il avait des documents à examiner.
   */
  async verificationQueue(query: { page?: number; limit?: number; status?: DocumentStatus; search?: string }) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));

    const where: Prisma.ProviderDocumentWhereInput = {
      status: query.status ?? "pending"
    };
    if (query.search?.trim()) {
      where.provider = { publicName: { contains: query.search.trim(), mode: "insensitive" } };
    }

    const [rows, total] = await Promise.all([
      this.prisma.providerDocument.findMany({
        where,
        include: {
          provider: { select: { id: true, publicName: true, validationStatus: true, user: { select: { email: true } } } },
          file: { select: { id: true, originalName: true, mimeType: true } }
        },
        // Les dossiers les plus anciens d'abord : on traite dans l'ordre d'arrivée.
        orderBy: { createdAt: "asc" },
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.providerDocument.count({ where })
    ]);

    const data = rows.map((doc) => ({
      id: doc.id,
      type: doc.type,
      status: doc.status,
      createdAt: doc.createdAt,
      fileId: doc.file?.id ?? null,
      fileName: doc.file?.originalName ?? null,
      providerId: doc.provider.id,
      providerName: doc.provider.publicName,
      providerEmail: doc.provider.user.email,
      providerStatus: doc.provider.validationStatus
    }));

    return { data, total, page, limit };
  }

  // Détail d'un document, avec son fichier joint s'il y en a un.
  async findById(documentId: string) {
    const document = await this.prisma.providerDocument.findUnique({
      where: { id: documentId },
      include: {
        file: { select: { id: true, originalName: true, mimeType: true, size: true } },
        provider: { select: { id: true, publicName: true } }
      }
    });
    if (!document) {
      throw new NotFoundException("Document introuvable");
    }
    return document;
  }

  /**
   * Rattache un justificatif (scan, photo, PDF) à un document de vérification.
   *
   * Sans ça, un agent devait approuver ou rejeter un document SANS pouvoir le
   * consulter : la case existait en base mais aucun fichier n'y était jamais lié.
   *
   * Le fichier est enregistré en visibilité « sensible » et appartient au
   * prestataire concerné : seul lui, ou un agent porteur de la permission
   * `files.sensitive.read`, peut le lire.
   */
  async attachFile(
    documentId: string,
    upload: { originalname: string; mimetype: string; size: number; buffer: Buffer },
    actorId?: string
  ) {
    const document = await this.prisma.providerDocument.findUnique({
      where: { id: documentId },
      include: { provider: { select: { userId: true } } }
    });
    if (!document) {
      throw new NotFoundException("Document introuvable");
    }

    const originalName = upload.originalname || "justificatif";
    const extension = extname(originalName).toLowerCase();
    const storageKey = `documents/${document.providerId}/${randomUUID()}${
      /^\.[a-z0-9]{1,10}$/.test(extension) ? extension : ""
    }`;

    await this.storage.save(storageKey, upload.buffer);

    const file = await this.prisma.file.create({
      data: {
        ownerId: document.provider.userId,
        originalName,
        mimeType: upload.mimetype,
        size: upload.size,
        storageKey,
        visibility: "sensitive"
      }
    });

    // Un nouveau justificatif remet le document en attente de revue : la
    // décision précédente ne porte plus sur le bon fichier.
    const updated = await this.prisma.providerDocument.update({
      where: { id: documentId },
      data: { fileId: file.id, status: "pending", rejectionReason: null, reviewedBy: null, reviewedAt: null },
      include: { file: { select: { id: true, originalName: true, mimeType: true, size: true } } }
    });

    await this.audit.record({
      actorId,
      action: "admin.verifications.documents.attach",
      entity: "ProviderDocument",
      entityId: documentId,
      oldValue: { fileId: document.fileId, status: document.status },
      newValue: { fileId: file.id, status: "pending" }
    });

    return updated;
  }

  // Approuve un document : on note qui l'a revu et quand.
  async approve(documentId: string, actorId?: string): Promise<void> {
    const document = await this.prisma.providerDocument.findUnique({ where: { id: documentId } });
    if (!document) {
      throw new NotFoundException("Document introuvable");
    }

    await this.prisma.providerDocument.update({
      where: { id: documentId },
      data: {
        status: "approved",
        rejectionReason: null,
        reviewedBy: actorId,
        reviewedAt: new Date()
      }
    });

    await this.audit.record({
      actorId,
      action: "admin.verifications.documents.approve",
      entity: "ProviderDocument",
      entityId: documentId,
      oldValue: { status: document.status },
      newValue: { status: "approved" }
    });
  }

  // Rejette un document : le motif est OBLIGATOIRE (règle métier US2).
  async reject(documentId: string, reason: string, actorId?: string): Promise<void> {
    if (!reason || reason.trim() === "") {
      throw new BadRequestException("Un motif de rejet est obligatoire");
    }

    const document = await this.prisma.providerDocument.findUnique({ where: { id: documentId } });
    if (!document) {
      throw new NotFoundException("Document introuvable");
    }

    await this.prisma.providerDocument.update({
      where: { id: documentId },
      data: {
        status: "rejected",
        rejectionReason: reason,
        reviewedBy: actorId,
        reviewedAt: new Date()
      }
    });

    await this.audit.record({
      actorId,
      action: "admin.verifications.documents.reject",
      entity: "ProviderDocument",
      entityId: documentId,
      oldValue: { status: document.status },
      newValue: { status: "rejected", reason }
    });
  }
}