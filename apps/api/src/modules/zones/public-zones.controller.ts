import { Controller, Get, Query } from "@nestjs/common";
import { ApiTags, ApiOperation } from "@nestjs/swagger";
import { ZonesService } from "./zones.service.js";
import { NearbyZonesQueryDto } from "./dto.js";
import { Public } from "../../common/decorators/public.decorator.js";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse, ApiErrorResponse } from "../../common/openapi/api-envelope.decorator.js";
import { NearbyZoneDto, PublicZoneDto } from "./response-dto.js";

// Zones couvertes, consultables sans compte : une application doit pouvoir
// afficher où la plateforme intervient avant même l'inscription.
@ApiTags("Zones")
@Controller("zones")
export class PublicZonesController {
  constructor(private readonly zones: ZonesService) {}

  // GET /zones — uniquement les zones ACTIVES.
  @Public()
  @Get()
  @ApiOperation({ summary: "List active zones" })
  @ApiEnvelopeResponse(PublicZoneDto, { isArray: true, description: "Zones actives, triées par nom" })
  async list() {
    return ok(await this.zones.listActive());
  }

  /**
   * GET /zones/nearby?latitude=…&longitude=…&radiusKm=…
   *
   * Répond à l'exigence du CDC §10 : « les recherches par zone doivent
   * exploiter les index géographiques ». Les zones sont triées de la plus
   * proche à la plus lointaine, avec leur distance en kilomètres.
   */
  @Public()
  @Get("nearby")
  @ApiOperation({ summary: "Find active zones within a radius of a point" })
  @ApiEnvelopeResponse(NearbyZoneDto, {
    isArray: true,
    description: "Zones actives dont le centre est dans le rayon, de la plus proche à la plus lointaine"
  })
  @ApiErrorResponse(400, "Latitude, longitude ou rayon invalide")
  async nearby(@Query() query: NearbyZonesQueryDto) {
    return ok(await this.zones.searchNearby(query.latitude, query.longitude, query.radiusKm ?? 10));
  }
}
