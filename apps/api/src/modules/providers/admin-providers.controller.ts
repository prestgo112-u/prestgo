import { Body, Controller, Get, Param, Patch, Post, Query, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { ProvidersService } from "./providers.service.js";
import {
  AddProviderNoteBodyDto,
  ProviderListQueryDto,
  ProviderStatusChangeBodyDto,
  ProviderUpdateBodyDto
} from "./dto.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";

// Routes de gestion des prestataires : /api/v1/admin/providers...
@ApiTags("Providers")
@ApiBearerAuth()
@Controller("admin/providers")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminProvidersController {
  constructor(private readonly providers: ProvidersService) {}

  // GET /admin/providers — liste paginée (filtre par statut de validation).
  @Get()
  @Permissions("admin.providers.read")
  @ApiOperation({ summary: "List providers with validation status filter" })
  async list(@Query() query: ProviderListQueryDto) {
    const result = await this.providers.list(query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  // GET /admin/providers/:id — détail (profil + documents + notes).
  @Get(":id")
  @Permissions("admin.providers.read")
  @ApiOperation({ summary: "Get provider detail" })
  async detail(@Param("id") id: string) {
    return ok(await this.providers.findById(id));
  }

  // PATCH /admin/providers/:id — met à jour les champs éditables par l'admin.
  @Patch(":id")
  @Permissions("admin.providers.update")
  @ApiOperation({ summary: "Update admin-editable provider fields" })
  async update(@Param("id") id: string, @Body() dto: ProviderUpdateBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.providers.updateFields(id, dto, req.user?.id));
  }

  // PATCH /admin/providers/:id/status — change le statut de validation (approuver, rejeter...).
  @Patch(":id/status")
  @Permissions("admin.providers.status.update")
  @ApiOperation({ summary: "Change provider validation status" })
  async changeStatus(@Param("id") id: string, @Body() dto: ProviderStatusChangeBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.providers.changeStatus(id, dto, req.user?.id));
  }

  // POST /admin/providers/:id/notes — ajoute une note interne (invisible du prestataire).
  @Post(":id/notes")
  @Permissions("admin.providers.update")
  @ApiOperation({ summary: "Add an internal note about a provider" })
  async addNote(@Param("id") id: string, @Body() dto: AddProviderNoteBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.providers.addNote(id, dto.note, req.user?.id), undefined, "Note enregistrée");
  }
}