import { Controller, Get, Query, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import { ok } from "../../common/contracts/api-response.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { ProviderContextService } from "../providers/provider-context.service.js";
import { MissionBookingService } from "./mission-booking.service.js";
import { MyMissionsQueryDto } from "./mobile-dto.js";

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
  async listMine(@Query() query: MyMissionsQueryDto, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    const result = await this.booking.listForProvider(providerId, query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }
}
