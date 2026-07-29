import { Body, Controller, Get, Param, Post, Query, Req } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { ClientsService } from "./clients.service.js";
import { AddClientNoteBodyDto, ClientListQueryDto } from "./dto.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { ok } from "../../common/contracts/api-response.js";

// Routes clients : /api/v1/admin/clients/...
// Les gardes (token + permissions) sont appliquées globalement, voir app.module.ts.
@ApiTags("Clients")
@ApiBearerAuth()
@Controller("admin/clients")
export class AdminClientsController {
  constructor(private readonly clients: ClientsService) {}

  @Get()
  @Permissions("admin.clients.read")
  @ApiOperation({ summary: "List clients with filters and pagination" })
  async list(@Query() query: ClientListQueryDto) {
    const result = await this.clients.list(query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  @Get(":id")
  @Permissions("admin.clients.read")
  @ApiOperation({ summary: "Get a client profile" })
  async detail(@Param("id") id: string) {
    return ok(await this.clients.findById(id));
  }

  @Get(":id/missions")
  @Permissions("admin.clients.read")
  @ApiOperation({ summary: "Get the mission history of a client" })
  async missions(@Param("id") id: string, @Query() query: PaginationQueryDto) {
    const result = await this.clients.missions(id, query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  @Post(":id/notes")
  @Permissions("admin.clients.notes")
  @ApiOperation({ summary: "Add an internal note about a client" })
  async addNote(@Param("id") id: string, @Body() body: AddClientNoteBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.clients.addNote(id, body.note, req.user?.id), undefined, "Note enregistrée");
  }
}
