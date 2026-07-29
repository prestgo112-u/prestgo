import { Body, Controller, Get, HttpCode, Param, Patch, Post, Query, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { MissionsService } from "./missions.service.js";
import {
  MissionCancelBodyDto,
  MissionListQueryDto,
  MissionRescheduleBodyDto,
  MissionStatusChangeBodyDto
} from "./dto.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";

@ApiTags("Missions")
@ApiBearerAuth()
@Controller("admin/missions")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminMissionsController {
  constructor(private readonly missions: MissionsService) {}

  // GET /admin/missions?status=confirmed
  @Get()
  @Permissions("admin.missions.read")
  @ApiOperation({ summary: "List missions" })
  async list(@Query() query: MissionListQueryDto) {
    const result = await this.missions.list(query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  @Get(":id")
  @Permissions("admin.missions.read")
  @ApiOperation({ summary: "Get mission detail" })
  async detail(@Param("id") id: string) {
    return ok(await this.missions.findById(id));
  }

  // PATCH /admin/missions/:id/status  { status, reason? }
  @Patch(":id/status")
  @Permissions("admin.missions.manage")
  @ApiOperation({ summary: "Change mission status" })
  async changeStatus(
    @Param("id") id: string,
    @Body() body: MissionStatusChangeBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    return ok(await this.missions.changeStatus(id, body.status, body.reason, req.user?.id));
  }

  // POST /admin/missions/:id/reschedule  { scheduledAt, reason? }
  @Post(":id/reschedule")
  @HttpCode(200)
  @Permissions("admin.missions.manage")
  @ApiOperation({ summary: "Reschedule mission" })
  async reschedule(
    @Param("id") id: string,
    @Body() body: MissionRescheduleBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    return ok(await this.missions.reschedule(id, body.scheduledAt, body.reason, req.user?.id));
  }

  // POST /admin/missions/:id/cancel  { reason }
  @Post(":id/cancel")
  @HttpCode(200)
  @Permissions("admin.missions.manage")
  @ApiOperation({ summary: "Cancel mission with reason" })
  async cancel(@Param("id") id: string, @Body() body: MissionCancelBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.missions.cancel(id, body.reason, req.user?.id));
  }
}
