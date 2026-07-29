import { Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import type {
  AssignPermissionsDto,
  CreateRoleDto,
  PermissionDto,
  RoleWithPermissions,
  UpdateRoleDto
} from "./role.types.js";

// "include" dit à Prisma de ramener aussi les permissions liées au rôle
// (jointure), pour ne pas faire une deuxième requête.
const roleInclude = { permissions: { include: { permission: true } } } as const;

// @Injectable = ce service peut être "injecté" (fourni automatiquement) dans
// d'autres classes par NestJS. On reçoit Prisma (accès base) et Audit (journal).
@Injectable()
export class RolesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  // Liste tous les rôles avec leurs permissions, triés par code.
  async listRoles(): Promise<RoleWithPermissions[]> {
    const roles = await this.prisma.role.findMany({ include: roleInclude, orderBy: { code: "asc" } });
    return roles.map((role) => this.toRoleDto(role));
  }

  // Liste toutes les permissions existantes (pour construire l'écran des rôles).
  async listPermissions(): Promise<PermissionDto[]> {
    const permissions = await this.prisma.permission.findMany({ orderBy: { code: "asc" } });
    return permissions.map((permission) => ({
      id: permission.id,
      code: permission.code,
      module: permission.module,
      action: permission.action,
      description: permission.description ?? undefined
    }));
  }

  // Crée un rôle, et lui attache directement des permissions si fournies.
  async createRole(dto: CreateRoleDto, actorId?: string): Promise<RoleWithPermissions> {
    const role = await this.prisma.role.create({
      data: {
        code: dto.code,
        name: dto.name,
        description: dto.description,
        permissions: dto.permissionIds
          ? { create: dto.permissionIds.map((permissionId) => ({ permissionId })) }
          : undefined
      },
      include: roleInclude
    });

    // On enregistre l'action dans le journal d'audit (traçabilité obligatoire).
    await this.audit.record({ actorId, action: "admin.roles.create", entity: "Role", entityId: role.id, newValue: dto });
    return this.toRoleDto(role);
  }

  // Met à jour le nom/description d'un rôle, et remplace ses permissions si fournies.
  async updateRole(id: string, dto: UpdateRoleDto, actorId?: string): Promise<RoleWithPermissions> {
    const current = await this.prisma.role.findUnique({ where: { id } });
    if (!current) {
      // NotFoundException = renvoie automatiquement une réponse HTTP 404.
      throw new NotFoundException("Role not found");
    }

    await this.prisma.role.update({
      where: { id },
      data: { name: dto.name, description: dto.description },
      include: roleInclude
    });

    if (dto.permissionIds) {
      await this.setPermissions(id, dto.permissionIds);
    }

    await this.audit.record({ actorId, action: "admin.roles.update", entity: "Role", entityId: id, newValue: dto });
    return this.findRole(id);
  }

  // Remplace la liste des permissions d'un rôle.
  async assignPermissions(id: string, dto: AssignPermissionsDto, actorId?: string): Promise<RoleWithPermissions> {
    await this.setPermissions(id, dto.permissionIds);
    await this.audit.record({
      actorId,
      action: "admin.roles.permissions.update",
      entity: "Role",
      entityId: id,
      newValue: dto
    });
    return this.findRole(id);
  }

  // Récupère un rôle par son id (usage interne).
  private async findRole(id: string): Promise<RoleWithPermissions> {
    const role = await this.prisma.role.findUnique({ where: { id }, include: roleInclude });
    if (!role) {
      throw new NotFoundException("Role not found");
    }
    return this.toRoleDto(role);
  }

  // Supprime toutes les permissions actuelles du rôle puis remet la nouvelle liste,
  // le tout dans une transaction (tout réussit, ou rien n'est modifié).
  private async setPermissions(roleId: string, permissionIds: string[]): Promise<void> {
    await this.prisma.$transaction([
      this.prisma.rolePermission.deleteMany({ where: { roleId } }),
      this.prisma.rolePermission.createMany({
        data: permissionIds.map((permissionId) => ({ roleId, permissionId })),
        skipDuplicates: true
      })
    ]);
  }

  // Transforme l'objet base de données en objet "propre" renvoyé par l'API.
  private toRoleDto(role: {
    id: string;
    code: string;
    name: string;
    description: string | null;
    isSystem: boolean;
    createdAt: Date;
    updatedAt: Date;
    permissions: { permission: { id: string; code: string; module: string; action: string; description: string | null } }[];
  }): RoleWithPermissions {
    return {
      id: role.id,
      code: role.code,
      name: role.name,
      description: role.description ?? undefined,
      isSystem: role.isSystem,
      createdAt: role.createdAt,
      updatedAt: role.updatedAt,
      permissions: role.permissions.map((rolePermission) => ({
        id: rolePermission.permission.id,
        code: rolePermission.permission.code,
        module: rolePermission.permission.module,
        action: rolePermission.permission.action,
        description: rolePermission.permission.description ?? undefined
      }))
    };
  }
}
