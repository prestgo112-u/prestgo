import { Body, Controller, Delete, Get, NotFoundException, Param, Post, Put, Req } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { AvailabilityService } from "./availability.service.js";
import { CreateUnavailabilityBodyDto, ReplaceAvailabilitiesBodyDto } from "./dto.js";
import { ProviderContextService } from "../providers/provider-context.service.js";
import { Public } from "../../common/decorators/public.decorator.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse, ApiErrorResponse } from "../../common/openapi/api-envelope.decorator.js";
import { ProviderAvailabilitySlotDto, ProviderUnavailabilityDto, RemovedUnavailabilityResultDto } from "./response-dto.js";

/** 403 commun aux routes `providers/me/*` : voir `ProviderContextService.requireProviderId`. */
const NO_PROVIDER_PROFILE = "Authentification requise, ou ce compte n'a pas de profil prestataire";

// Disponibilités côté prestataire et côté public.
// Les routes « me » sont déclarées AVANT « :id » (voir même remarque côté
// catalogue) : sinon « me » serait capturé comme un identifiant.
@ApiTags("Availability")
@Controller("providers")
export class ProviderAvailabilityController {
  constructor(
    private readonly availability: AvailabilityService,
    private readonly context: ProviderContextService
  ) {}

  /**
   * GET /providers/me/availabilities — relire MON agenda hebdomadaire.
   *
   * Pendant en lecture de `PUT` ci-dessous, par symétrie avec
   * `GET /providers/me/zones`. Sans elle, le prestataire devait relire son
   * propre agenda par la route PUBLIQUE `/providers/:id/availabilities` en
   * passant son propre identifiant — un détour que rien ne justifiait, et qui
   * obligeait l'application à connaître son `providerId` avant d'afficher
   * l'écran.
   *
   * Renvoie exactement ce que `PUT` a enregistré : c'est un vrai miroir.
   */
  @ApiBearerAuth()
  @Get("me/availabilities")
  @ApiOperation({ summary: "Get my weekly availability" })
  @ApiEnvelopeResponse(ProviderAvailabilitySlotDto, { isArray: true, description: "Mon agenda hebdomadaire" })
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  async listMine(@Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.availability.listForProvider(providerId));
  }

  /**
   * PUT /providers/me/availabilities — remplace TOUT l'agenda hebdomadaire.
   *
   * Le CDC prévoit un PUT et non un POST : l'appelant envoie l'agenda complet
   * tel qu'il doit être. C'est plus simple pour une interface où l'on coche des
   * créneaux, et cela évite les états incohérents d'une suite d'ajouts et de
   * suppressions partielles.
   */
  @ApiBearerAuth()
  @Put("me/availabilities")
  @ApiOperation({ summary: "Replace my weekly availability" })
  @ApiEnvelopeResponse(ProviderAvailabilitySlotDto, { isArray: true, description: "Mon agenda hebdomadaire mis à jour" })
  @ApiErrorResponse(400, "Jour hors 0-6, heure de fin avant l'heure de début, ou créneaux qui se chevauchent")
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  async replaceMine(@Body() dto: ReplaceAvailabilitiesBodyDto, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    const slots = await this.availability.replaceAll(providerId, dto.slots, req.user?.id);
    return ok(slots, undefined, "Disponibilités mises à jour");
  }

  // POST /providers/me/unavailabilities — déclarer une absence exceptionnelle.
  @ApiBearerAuth()
  @Post("me/unavailabilities")
  @ApiOperation({ summary: "Declare one of my exceptional unavailabilities" })
  @ApiEnvelopeResponse(ProviderUnavailabilityDto, { status: 201, description: "Indisponibilité enregistrée" })
  @ApiErrorResponse(400, "Date de fin avant la date de début, ou période chevauchant une absence existante")
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  async addUnavailability(@Body() dto: CreateUnavailabilityBodyDto, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(
      await this.availability.addUnavailability(providerId, dto, req.user?.id),
      undefined,
      "Indisponibilité enregistrée"
    );
  }

  // DELETE /providers/me/unavailabilities/:id
  @ApiBearerAuth()
  @Delete("me/unavailabilities/:id")
  @ApiOperation({ summary: "Remove one of my unavailabilities" })
  @ApiEnvelopeResponse(RemovedUnavailabilityResultDto, { description: "Indisponibilité supprimée" })
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  @ApiErrorResponse(404, "Indisponibilité introuvable, ou n'appartenant pas à ce prestataire")
  async removeUnavailability(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    // On vérifie que l'indisponibilité appartient bien au prestataire connecté,
    // sinon n'importe qui pourrait supprimer l'absence d'un confrère.
    const mine = await this.availability.listUnavailabilities(providerId);
    if (!mine.some((item) => item.id === id)) {
      throw new NotFoundException("Indisponibilité introuvable");
    }
    return ok(await this.availability.removeUnavailability(id, req.user?.id));
  }

  // GET /providers/:id/availabilities — agenda public d'un prestataire.
  @Public()
  @Get(":id/availabilities")
  @ApiOperation({ summary: "Get the weekly availability of a provider" })
  async listForProvider(@Param("id") id: string) {
    return ok(await this.availability.listForProvider(id));
  }

  // GET /providers/:id/unavailabilities — absences annoncées.
  @Public()
  @Get(":id/unavailabilities")
  @ApiOperation({ summary: "Get the exceptional unavailabilities of a provider" })
  async listUnavailabilities(@Param("id") id: string) {
    return ok(await this.availability.listUnavailabilities(id));
  }
}
