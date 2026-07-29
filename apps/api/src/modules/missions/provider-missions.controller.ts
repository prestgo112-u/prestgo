import { Controller, Get, Query, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse, ApiErrorResponse } from "../../common/openapi/api-envelope.decorator.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { ProviderContextService } from "../providers/provider-context.service.js";
import { MissionBookingService } from "./mission-booking.service.js";
import { MyMissionsQueryDto } from "./mobile-dto.js";
import { MissionListItemDto } from "./response-dto.js";

/**
 * Missions du prestataire connecté (§9).
 *
 * Le prestataire est résolu depuis le jeton : il n'existe aucun moyen de
 * consulter le planning d'un confrère.
 */
@ApiTags("Missions")
@ApiBearerAuth()
@Controller("providers")
export class ProviderMissionsController {
  constructor(
    private readonly booking: MissionBookingService,
    private readonly context: ProviderContextService
  ) {}

  /**
   * GET /providers/me/missions — mon planning.
   *
   * Trié par date d'intervention CROISSANTE : un prestataire veut voir ce qui
   * arrive. C'est l'inverse du besoin du client, qui consulte plutôt son
   * historique.
   */
  @Get("me/missions")
  @ApiOperation({ summary: "List my missions as a provider (soonest first)" })
  @ApiEnvelopeResponse(MissionListItemDto, { isArray: true, paginated: true, description: "Mes missions, la plus proche d'abord" })
  @ApiErrorResponse(403, "Authentification requise, ou ce compte n'a pas de profil prestataire")
  async listMine(@Query() query: MyMissionsQueryDto, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    const result = await this.booking.listForProvider(providerId, query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }
}
