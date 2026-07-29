import { Body, Controller, Get, Param, Patch, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { SettingsService } from "./settings.service.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";
import { UpdateSettingBodyDto } from "../administration/dto.js";

@ApiTags("Settings")
@ApiBearerAuth()
@Controller("admin/settings")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminSettingsController {
  constructor(private readonly settings: SettingsService) {}

  @Get()
  @Permissions("admin.settings.read")
  @ApiOperation({ summary: "List settings" })
  async list() {
    return ok(await this.settings.list());
  }

  // PATCH /admin/settings/:key  { value }
  @Patch(":key")
  @Permissions("admin.settings.update")
  @ApiOperation({ summary: "Update a setting" })
  async update(@Param("key") key: string, @Body() body: UpdateSettingBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.settings.update(key, body.value, req.user?.id));
  }
}
