import { Controller, Get, Query, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { DashboardService } from "./dashboard.service.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";
import { DashboardChartsQueryDto } from "./dto.js";

@ApiTags("Admin Dashboard")
@ApiBearerAuth()
@Controller("admin/dashboard")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class DashboardController {
  constructor(private readonly dashboard: DashboardService) {}

  // GET /api/v1/admin/dashboard/summary — nécessite la permission "admin.dashboard.read".
  @Get("summary")
  @Permissions("admin.dashboard.read")
  @ApiOperation({ summary: "Get operational dashboard summary" })
  async summary() {
    return ok(await this.dashboard.summary());
  }

  // GET /api/v1/admin/dashboard/charts?days=30 — données des graphiques.
  @Get("charts")
  @Permissions("admin.dashboard.read")
  @ApiOperation({ summary: "Get dashboard chart series" })
  async charts(@Query() query: DashboardChartsQueryDto) {
    return ok(await this.dashboard.charts(query.days ?? 30));
  }
}