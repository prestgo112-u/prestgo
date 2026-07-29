import { Body, Controller, Get, Param, Patch, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { NotificationsService } from "./notifications.service.js";
import { UpdateNotificationTemplateBodyDto } from "../administration/dto.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";

/**
 * Modèles de notification, sur le chemin exact prévu par le CDC §8 :
 * `/admin/notification-templates`.
 *
 * Le back-office exposait ces modèles sous `/admin/notifications/templates`.
 * Ce chemin reste en place pour ne rien casser, mais le chemin officiel du
 * cahier des charges existe désormais, avec en plus la modification.
 */
@ApiTags("Notifications")
@ApiBearerAuth()
@Controller("admin/notification-templates")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminNotificationTemplatesController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get()
  @Permissions("admin.notifications.read")
  @ApiOperation({ summary: "List notification templates" })
  async list() {
    return ok(await this.notifications.listTemplates());
  }

  @Patch(":id")
  @Permissions("admin.notifications.send")
  @ApiOperation({ summary: "Update a notification template" })
  async update(
    @Param("id") id: string,
    @Body() body: UpdateNotificationTemplateBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    return ok(await this.notifications.updateTemplate(id, body, req.user?.id), undefined, "Modèle mis à jour");
  }
}
