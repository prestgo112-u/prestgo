import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import type { Prisma } from "@prisma/client";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { buildOrderBy, type SortAllowList } from "../../common/dto/sorting.js";
import { AuditService } from "../audit/audit.service.js";
import type { UserStatus } from "./user.types.js";
import type { UpdateUserStatusDto, UserListQuery, UserWithRoles } from "./user.types.js";

const userWithRolesInclude = {
  roles: {
    include: {
      role: {
        include: {
          permissions: { include: { permission: true } }
        }
      }
    }
  }
} as const;

@Injectable()
export class UsersService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  /**
   * Colonnes triables de la liste utilisateurs (§15.4).
   *
   * `passwordHash` et consorts en sont évidemment absents : sans liste
   * blanche, `sort` permettrait de trier sur l'empreinte du mot de passe et
   * d'en deviner le contenu par comparaisons successives.
   */
  private static readonly SORTABLE: SortAllowList = {
    createdAt: { path: ["createdAt"], defaultDirection: "desc" },
    email: ["email"],
    lastName: ["lastName"],
    status: ["status"]
  };

  async list(query: UserListQuery): Promise<{ data: UserWithRoles[]; total: number; page: number; limit: number }> {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));

    const where: Record<string, unknown> = {};
    if (query.status) {
      where.status = query.status;
    }
    if (query.search) {
      where.OR = [
        { email: { contains: query.search, mode: "insensitive" } },
        { firstName: { contains: query.search, mode: "insensitive" } },
        { lastName: { contains: query.search, mode: "insensitive" } },
        { phone: { contains: query.search } }
      ];
    }

    const [rows, total] = await Promise.all([
      this.prisma.user.findMany({
        where,
        include: userWithRolesInclude,
        orderBy: buildOrderBy<Prisma.UserOrderByWithRelationInput>(query.sort, UsersService.SORTABLE, {
          createdAt: "desc"
        }),
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.user.count({ where })
    ]);

    return { data: rows.map((row) => this.toDto(row)), total, page, limit };
  }

  async findById(id: string): Promise<UserWithRoles> {
    const user = await this.prisma.user.findUnique({ where: { id }, include: userWithRolesInclude });
    if (!user) {
      throw new NotFoundException("User not found");
    }
    return this.toDto(user);
  }

  async changeStatus(id: string, dto: UpdateUserStatusDto, actorId?: string): Promise<UserWithRoles> {
    const current = await this.prisma.user.findUnique({ where: { id } });
    if (!current) {
      throw new NotFoundException("User not found");
    }

    const updated = await this.prisma.user.update({
      where: { id },
      data: { status: dto.status },
      include: userWithRolesInclude
    });

    await this.audit.record({
      actorId,
      action: "admin.users.status.update",
      entity: "User",
      entityId: id,
      oldValue: { status: current.status },
      newValue: { status: dto.status, reason: dto.reason }
    });

    return this.toDto(updated);
  }

  /**
   * Ajoute une note interne du support sur un compte.
   *
   * Le CDC ne prévoit pas de table dédiée aux notes utilisateur : elles vivent
   * dans le champ `notes` du profil client (§7). On empile les notes en gardant
   * leur date, pour ne jamais écraser ce qu'un collègue a écrit.
   */
  async addNote(id: string, note: string, actorId?: string) {
    const user = await this.prisma.user.findUnique({ where: { id } });
    if (!user) {
      throw new NotFoundException("User not found");
    }

    const profile = await this.prisma.clientProfile.findUnique({ where: { userId: id } });
    const line = `[${new Date().toISOString().slice(0, 10)}] ${note.trim()}`;
    const merged = profile?.notes ? `${profile.notes}\n${line}` : line;

    const saved = await this.prisma.clientProfile.upsert({
      where: { userId: id },
      update: { notes: merged },
      create: { userId: id, notes: line }
    });

    await this.audit.record({
      actorId,
      action: "admin.users.note.add",
      entity: "User",
      entityId: id,
      newValue: { note: line }
    });

    return { notes: saved.notes };
  }

  /**
   * Remplace la liste des rôles d'un utilisateur.
   *
   * C'est ce qui manquait pour satisfaire le critère du CDC « un super admin
   * peut gérer les utilisateurs internes » : les rôles étaient affichés, mais
   * aucune route ne permettait de les modifier.
   *
   * On remplace d'un bloc (suppression puis insertion) plutôt que de calculer
   * les différences : c'est plus simple et le résultat est le même. Les deux
   * opérations sont dans une transaction pour ne jamais laisser l'utilisateur
   * sans aucun rôle en cas d'erreur au milieu.
   */
  async setRoles(id: string, roleIds: string[], actorId?: string): Promise<UserWithRoles> {
    const user = await this.prisma.user.findUnique({ where: { id }, include: userWithRolesInclude });
    if (!user) {
      throw new NotFoundException("User not found");
    }

    // On vérifie que tous les rôles demandés existent vraiment.
    const roles = await this.prisma.role.findMany({ where: { id: { in: roleIds } } });
    if (roles.length !== roleIds.length) {
      throw new BadRequestException("Un ou plusieurs rôles sont introuvables");
    }

    const before = user.roles.map((userRole) => userRole.role.code);

    await this.prisma.$transaction([
      this.prisma.userRole.deleteMany({ where: { userId: id } }),
      this.prisma.userRole.createMany({ data: roleIds.map((roleId) => ({ userId: id, roleId })) })
    ]);

    await this.audit.record({
      actorId,
      action: "admin.users.roles.update",
      entity: "User",
      entityId: id,
      oldValue: { roles: before },
      newValue: { roles: roles.map((role) => role.code) }
    });

    return this.findById(id);
  }

  private toDto(user: {
    id: string;
    firstName: string | null;
    lastName: string | null;
    phone: string | null;
    email: string | null;
    status: string;
    phoneVerifiedAt: Date | null;
    emailVerifiedAt: Date | null;
    createdAt: Date;
    updatedAt: Date;
    roles: { role: { code: string; permissions: { permission: { code: string } }[] } }[];
  }): UserWithRoles {
    const permissions = new Set<string>();
    for (const userRole of user.roles) {
      for (const rolePermission of userRole.role.permissions) {
        permissions.add(rolePermission.permission.code);
      }
    }

    return {
      id: user.id,
      firstName: user.firstName ?? undefined,
      lastName: user.lastName ?? undefined,
      phone: user.phone ?? undefined,
      email: user.email ?? undefined,
      status: user.status as UserStatus,
      phoneVerifiedAt: user.phoneVerifiedAt ?? undefined,
      emailVerifiedAt: user.emailVerifiedAt ?? undefined,
      createdAt: user.createdAt,
      updatedAt: user.updatedAt,
      roles: user.roles.map((userRole) => userRole.role.code),
      permissions: [...permissions]
    };
  }
}
