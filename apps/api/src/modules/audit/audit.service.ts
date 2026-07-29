import { Injectable } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { currentIp } from "../../common/middleware/request-context.js";

export interface AuditEntry {
  actorId?: string;
  action: string;
  entity: string;
  entityId?: string;
  oldValue?: unknown;
  newValue?: unknown;
  ip?: string;
  createdAt: Date;
}

export type AuditInput = Omit<AuditEntry, "createdAt">;

@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Écrit une ligne d'audit.
   *
   * L'adresse IP n'est pas un paramètre à passer partout : elle est lue dans le
   * contexte de la requête en cours (§15.5). Un appelant peut toujours la
   * forcer — un job planifié, par exemple, n'en a pas et laisse le champ vide.
   */
  async record(input: AuditInput): Promise<AuditEntry> {
    const entry = await this.prisma.auditLog.create({
      data: {
        actorId: input.actorId,
        action: input.action,
        entity: input.entity,
        entityId: input.entityId,
        oldValue: input.oldValue as any,
        newValue: input.newValue as any,
        ip: input.ip ?? currentIp()
      }
    });

    return {
      actorId: entry.actorId ?? undefined,
      action: entry.action,
      entity: entry.entity,
      entityId: entry.entityId ?? undefined,
      oldValue: entry.oldValue ?? undefined,
      newValue: entry.newValue ?? undefined,
      ip: entry.ip ?? undefined,
      createdAt: entry.createdAt
    };
  }

  // Version paginée avec filtres, pour l'écran "Journal d'audit" de l'US5.
  async listPaginated(query: {
    page?: number;
    limit?: number;
    entity?: string;
    action?: string;
    actorId?: string;
  }): Promise<{ data: AuditEntry[]; total: number; page: number; limit: number }> {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));
    const where: Record<string, unknown> = {};
    if (query.entity) where.entity = query.entity;
    if (query.action) where.action = query.action;
    if (query.actorId) where.actorId = query.actorId;

    const [logs, total] = await Promise.all([
      this.prisma.auditLog.findMany({
        where,
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.auditLog.count({ where })
    ]);

    const data = logs.map((log) => ({
      actorId: log.actorId ?? undefined,
      action: log.action,
      entity: log.entity,
      entityId: log.entityId ?? undefined,
      oldValue: log.oldValue ?? undefined,
      newValue: log.newValue ?? undefined,
      ip: log.ip ?? undefined,
      createdAt: log.createdAt
    }));

    return { data, total, page, limit };
  }

  async list(filters?: { entity?: string; entityId?: string; actorId?: string }): Promise<AuditEntry[]> {
    const where: any = {};
    if (filters?.entity) where.entity = filters.entity;
    if (filters?.entityId) where.entityId = filters.entityId;
    if (filters?.actorId) where.actorId = filters.actorId;

    const logs = await this.prisma.auditLog.findMany({
      where,
      orderBy: { createdAt: "desc" }
    });

    return logs.map((log) => ({
      actorId: log.actorId ?? undefined,
      action: log.action,
      entity: log.entity,
      entityId: log.entityId ?? undefined,
      oldValue: log.oldValue ?? undefined,
      newValue: log.newValue ?? undefined,
      ip: log.ip ?? undefined,
      createdAt: log.createdAt
    }));
  }
}
