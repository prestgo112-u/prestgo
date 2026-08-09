import { Body, Controller, Get, HttpCode, Param, Post, Query, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { ExportsService } from "./exports.service.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { CreateExportBodyDto } from "../administration/dto.js";

@ApiTags("Exports")
@ApiBearerAuth()
@Controller("admin/exports")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminExportsController {
  constructor(private readonly exports: ExportsService) {}

  @Get()
  @Permissions("admin.exports.manage")
  @ApiOperation({ summary: "List export jobs" })
  async list(@Query() query: PaginationQueryDto) {
    const result = await this.exports.list(query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  // POST /admin/exports  { type, filters? }
  @Post()
  @HttpCode(202)
  @Permissions("admin.exports.manage")
  @ApiOperation({ summary: "Create export job" })
  async create(@Body() body: CreateExportBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.exports.create(body, req.user?.id), undefined, "Export queued");
  }

  @Get(":id")
  @Permissions("admin.exports.manage")
  @ApiOperation({ summary: "Get export job status" })
  async status(@Param("id") id: string) {
    return ok(await this.exports.findById(id));
  }
}
