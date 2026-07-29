import { Body, Controller, Get, HttpCode, Param, Patch, Post, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { ZonesService } from "./zones.service.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";
import { CreateZoneBodyDto, UpdateZoneBodyDto } from "./dto.js";

@ApiTags("Zones")
@ApiBearerAuth()
@Controller("admin/zones")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminZonesController {
  constructor(private readonly zones: ZonesService) {}

  @Get()
  @Permissions("admin.zones.read")
  @ApiOperation({ summary: "List zones" })
  async list() {
    return ok(await this.zones.list());
  }

  @Post()
  @Permissions("admin.zones.manage")
  @ApiOperation({ summary: "Create zone" })
  async create(
    @Body() body: CreateZoneBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    return ok(await this.zones.create(body, req.user?.id), undefined, "Zone created");
  }

  @Patch(":id")
  @Permissions("admin.zones.manage")
  @ApiOperation({ summary: "Update or (de)activate a zone" })
  async update(
    @Param("id") id: string,
    @Body() body: UpdateZoneBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    return ok(await this.zones.update(id, body, req.user?.id));
  }

  // POST /admin/zones/:id/providers/:providerId — rattacher une zone à un prestataire.
  @Post(":id/providers/:providerId")
  @HttpCode(200)
  @Permissions("admin.zones.manage")
  @ApiOperation({ summary: "Attach a zone to a provider" })
  async attachProvider(@Param("id") id: string, @Param("providerId") providerId: string, @Req() req: AuthenticatedRequest) {
    return ok(await this.zones.attachProvider(id, providerId, req.user?.id));
  }
}
