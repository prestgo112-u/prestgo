import { Body, Controller, Get, HttpCode, Post, Query, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { NotificationsService } from "./notifications.service.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { SendNotificationBodyDto } from "../administration/dto.js";

@ApiTags("Notifications")
@ApiBearerAuth()
@Controller("admin/notifications")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminNotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get()
  @Permissions("admin.notifications.read")
  @ApiOperation({ summary: "List notifications" })
  async list(@Query() query: PaginationQueryDto) {
    const result = await this.notifications.list(query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  @Get("templates")
  @Permissions("admin.notifications.read")
  @ApiOperation({ summary: "List notification templates" })
  async templates() {
    return ok(await this.notifications.listTemplates());
  }

  // POST /admin/notifications/send  { type, title, body, channel?, userId? }
  @Post("send")
  @HttpCode(202)
  @Permissions("admin.notifications.send")
  @ApiOperation({ summary: "Send a system notification" })
  async send(
    @Body() body: SendNotificationBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    return ok(await this.notifications.send(body, req.user?.id), undefined, "Notification queued");
  }
}
