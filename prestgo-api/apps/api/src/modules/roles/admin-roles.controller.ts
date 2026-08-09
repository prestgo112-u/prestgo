import { Body, Controller, Get, Param, Patch, Post, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { RolesService } from "./roles.service.js";
import { AssignPermissionsBodyDto, CreateRoleBodyDto, UpdateRoleBodyDto } from "./dto.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";

// Toutes les routes de gestion des rôles exigent la permission "admin.roles.manage".
@ApiTags("Roles")
@ApiBearerAuth()
@Controller("admin")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminRolesController {
  constructor(private readonly roles: RolesService) {}

  // GET /api/v1/admin/roles — liste des rôles avec leurs permissions.
  @Get("roles")
  @Permissions("admin.roles.manage")
  @ApiOperation({ summary: "List roles" })
  async listRoles() {
    return ok(await this.roles.listRoles());
  }

  // GET /api/v1/admin/permissions — liste de toutes les permissions disponibles.
  @Get("permissions")
  @Permissions("admin.roles.manage")
  @ApiOperation({ summary: "List permissions" })
  async listPermissions() {
    return ok(await this.roles.listPermissions());
  }

  // POST /api/v1/admin/roles — crée un rôle.
  @Post("roles")
  @Permissions("admin.roles.manage")
  @ApiOperation({ summary: "Create role" })
  async createRole(@Body() dto: CreateRoleBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.roles.createRole(dto, req.user?.id), undefined, "Role created");
  }

  // PATCH /api/v1/admin/roles/:id — modifie un rôle.
  @Patch("roles/:id")
  @Permissions("admin.roles.manage")
  @ApiOperation({ summary: "Update role" })
  async updateRole(@Param("id") id: string, @Body() dto: UpdateRoleBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.roles.updateRole(id, dto, req.user?.id));
  }

  // PATCH /api/v1/admin/roles/:id/permissions — remplace les permissions d'un rôle.
  @Patch("roles/:id/permissions")
  @Permissions("admin.roles.manage")
  @ApiOperation({ summary: "Assign permissions to a role" })
  async assignPermissions(@Param("id") id: string, @Body() dto: AssignPermissionsBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.roles.assignPermissions(id, dto, req.user?.id));
  }
}