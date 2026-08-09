import { Injectable, NotFoundException } from "@nestjs/common";
import type { Prisma } from "@prisma/client";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";

@Injectable()
export class ClientsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  /**
   * Qu'est-ce qu'un « client » ?
   *
   * C'est un utilisateur de la plateforme qui n'est ni prestataire, ni membre
   * d'une équipe interne. On le reconnaît donc en excluant ceux qui ont un
   * profil prestataire et ceux qui portent un rôle back-office.
   *
   * On ne se base pas sur `ClientProfile` pour la liste : un utilisateur peut
   * très bien avoir commandé une mission sans qu'un profil ait été créé. Le
   * profil sert à porter les informations internes (note du support).
   */
  private baseFilter(): Prisma.UserWhereInput {
    return {
      providerProfile: { is: null },
      roles: { none: {} }
    };
  }

  async list(query: { page?: number; limit?: number; search?: string; status?: string }) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));

    const where: Prisma.UserWhereInput = { ...this.baseFilter() };
    if (query.status) {
      where.status = query.status as Prisma.UserWhereInput["status"];
    }
    if (query.search?.trim()) {
      const search = query.search.trim();
      // `mode: "insensitive"` = la recherche ignore les majuscules.
      where.OR = [
        { email: { contains: search, mode: "insensitive" } },
        { firstName: { contains: search, mode: "insensitive" } },
        { lastName: { contains: search, mode: "insensitive" } },
        { phone: { contains: search, mode: "insensitive" } }
      ];
    }

    const [rows, total] = await Promise.all([
      this.prisma.user.findMany({
        where,
        include: {
          clientProfile: { select: { notes: true } },
          // `_count` demande à Prisma de compter les missions sans les charger.
          _count: { select: { clientMissions: true } }
        },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.user.count({ where })
    ]);

    const data = rows.map((user) => ({
      id: user.id,
      email: user.email,
      phone: user.phone,
      firstName: user.firstName,
      lastName: user.lastName,
      status: user.status,
      missionCount: user._count.clientMissions,
      hasNotes: Boolean(user.clientProfile?.notes),
      createdAt: user.createdAt
    }));

    return { data, total, page, limit };
  }

  // Fiche client : identité, adresses et note interne du support.
  async findById(id: string) {
    const user = await this.prisma.user.findFirst({
      where: { id, ...this.baseFilter() },
      include: {
        clientProfile: true,
        addresses: { orderBy: { isDefault: "desc" } },
        _count: { select: { clientMissions: true } }
      }
    });
    if (!user) {
      throw new NotFoundException("Client introuvable");
    }

    return {
      id: user.id,
      email: user.email,
      phone: user.phone,
      firstName: user.firstName,
      lastName: user.lastName,
      status: user.status,
      createdAt: user.createdAt,
      missionCount: user._count.clientMissions,
      notes: user.clientProfile?.notes ?? null,
      addresses: user.addresses.map((address) => ({
        id: address.id,
        label: address.label,
        city: address.city,
        commune: address.commune,
        details: address.details,
        isDefault: address.isDefault
      }))
    };
  }

  // Historique des missions commandées par ce client.
  async missions(id: string, query: { page?: number; limit?: number }) {
    await this.findById(id); // vérifie que le client existe

    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));
    const where = { clientId: id };

    const [rows, total] = await Promise.all([
      this.prisma.mission.findMany({
        where,
        include: {
          provider: { select: { publicName: true } },
          pack: { select: { title: true, price: true } }
        },
        orderBy: { createdAt: "desc" },
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.mission.count({ where })
    ]);

    const data = rows.map((mission) => ({
      id: mission.id,
      status: mission.status,
      scheduledAt: mission.scheduledAt,
      providerName: mission.provider?.publicName ?? "—",
      packTitle: mission.pack?.title ?? "—",
      price: mission.pack?.price ?? null,
      createdAt: mission.createdAt
    }));

    return { data, total, page, limit };
  }

  /**
   * Ajoute une note interne sur un client.
   *
   * Le profil client est créé au passage s'il n'existait pas encore (`upsert`).
   * Les notes s'empilent en gardant la date : on ne veut jamais écraser ce
   * qu'un collègue a écrit avant.
   */
  async addNote(id: string, note: string, actorId?: string) {
    await this.findById(id);

    const existing = await this.prisma.clientProfile.findUnique({ where: { userId: id } });
    const stamp = new Date().toISOString().slice(0, 10);
    const line = `[${stamp}] ${note.trim()}`;
    const merged = existing?.notes ? `${existing.notes}\n${line}` : line;

    const profile = await this.prisma.clientProfile.upsert({
      where: { userId: id },
      update: { notes: merged },
      create: { userId: id, notes: line }
    });

    await this.audit.record({
      actorId,
      action: "admin.clients.note.add",
      entity: "ClientProfile",
      entityId: profile.id,
      newValue: { note: line }
    });

    return { notes: profile.notes };
  }
}
