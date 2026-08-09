import { Controller, Get, Param, Req } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { MissionAccessService } from "./mission-access.service.js";
import { MissionsService } from "./missions.service.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse, ApiErrorResponse } from "../../common/openapi/api-envelope.decorator.js";
import { MissionHistoryDto } from "./response-dto.js";

// Routes mission accessibles aux parties prenantes (client et prestataire),
// pas seulement au back-office.
@ApiTags("Missions")
@ApiBearerAuth()
@Controller("missions")
export class MissionsController {
  constructor(
    private readonly missions: MissionsService,
    private readonly access: MissionAccessService
  ) {}

  // GET /missions/:id/history — qui a changé quoi, quand et pourquoi.
  @Get(":id/history")
  @ApiOperation({ summary: "Get the status history of a mission" })
  @ApiEnvelopeResponse(MissionHistoryDto, { description: "Historique des statuts et des reports" })
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Vous n'êtes pas partie à cette mission")
  @ApiErrorResponse(404, "Mission introuvable")
  async history(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    // Contrôle d'appartenance AVANT toute lecture de données.
    await this.access.requireParticipant(id, req.user ?? {});
    return ok(await this.missions.history(id));
  }
}
