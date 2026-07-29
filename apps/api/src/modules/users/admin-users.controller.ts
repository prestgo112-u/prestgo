import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { UsersService } from "./users.service.js";
import { AddUserNoteBodyDto, SetUserRolesBodyDto, UpdateUserStatusBodyDto, UserListQueryDto } from "./dto.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";

// @Controller("admin/users") = toutes les routes ci-dessous commencent par
//   /api/v1/admin/users (le préfixe /api/v1 est ajouté globalement dans main.ts).
// @UseGuards(JwtAuthGuard, PermissionsGuard) = avant CHAQUE route de ce contrôleur,
//   on vérifie d'abord le token (JwtAuthGuard) puis les permissions (PermissionsGuard).
@ApiTags("Admin Users")
@ApiBearerAuth()
@Controller("admin/users")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminUsersController {
  // NestJS injecte automatiquement le service dont on a besoin.
  constructor(private readonly users: UsersService) {}

  // GET /api/v1/admin/users?page=1&limit=20&status=active&search=...
  // @Permissions(...) = le PermissionsGuard exige cette permission pour entrer.
  @Get()
  @Permissions("admin.users.read")
  @ApiOperation({ summary: "List users with filters and pagination" })
  async list(@Query() query: UserListQueryDto) {
    const result = await this.users.list(query);
    // ok(...) enveloppe la réponse au format standard { success, data, meta }.
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  @Get(":id")
  @Permissions("admin.users.read")
  @ApiOperation({ summary: "Get user detail" })
  async detail(@Param("id") id: string) {
    const user = await this.users.findById(id);
    return ok(user);
  }

  @Patch(":id/status")
  @Permissions("admin.users.status.update")
  @ApiOperation({ summary: "Change user status" })
  async changeStatus(
    @Param("id") id: string,
    @Body() dto: UpdateUserStatusBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    const user = await this.users.changeStatus(id, dto, req.user?.id);
    return ok(user);
  }

  // POST /admin/users/:id/notes — note interne du support sur un compte.
  // Elle est stockée sur le profil client, créé au besoin.
  @Post(":id/notes")
  @Permissions("admin.users.read")
  @ApiOperation({ summary: "Add an internal note about a user" })
  async addNote(@Param("id") id: string, @Body() dto: AddUserNoteBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.users.addNote(id, dto.note, req.user?.id), undefined, "Note enregistrée");
  }

  // PATCH /admin/users/:id/roles — affecte les rôles internes d'un utilisateur.
  @Patch(":id/roles")
  @Permissions("admin.roles.manage")
  @ApiOperation({ summary: "Set the roles of a user" })
  async setRoles(@Param("id") id: string, @Body() dto: SetUserRolesBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.users.setRoles(id, dto.roleIds, req.user?.id), undefined, "Rôles mis à jour");
  }
}
