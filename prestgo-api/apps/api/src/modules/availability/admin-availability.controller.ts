import { Body, Controller, Delete, Get, HttpCode, Param, Post, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { AvailabilityService } from "./availability.service.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";
import { CreateAvailabilityBodyDto } from "./dto.js";

// Disponibilités rattachées à un prestataire : /admin/providers/:providerId/availability
@ApiTags("Availability")
@ApiBearerAuth()
@Controller("admin/providers/:providerId/availability")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminAvailabilityController {
  constructor(private readonly availability: AvailabilityService) {}

  @Get()
  @Permissions("admin.availability.read")
  @ApiOperation({ summary: "List a provider's availability" })
  async list(@Param("providerId") providerId: string) {
    return ok(await this.availability.listForProvider(providerId));
  }

  @Post()
  @HttpCode(200)
  @Permissions("admin.availability.manage")
  @ApiOperation({ summary: "Add an availability slot" })
  async add(
    @Param("providerId") providerId: string,
    @Body() body: CreateAvailabilityBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    return ok(await this.availability.add(providerId, body, req.user?.id), undefined, "Slot added");
  }

  @Delete(":slotId")
  @Permissions("admin.availability.manage")
  @ApiOperation({ summary: "Remove an availability slot" })
  async remove(@Param("slotId") slotId: string, @Req() req: AuthenticatedRequest) {
    return ok(await this.availability.remove(slotId, req.user?.id));
  }
}
