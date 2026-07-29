import { Body, Controller, Delete, Get, NotFoundException, Param, Post, Put, Req } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { AvailabilityService } from "./availability.service.js";
import { CreateUnavailabilityBodyDto, ReplaceAvailabilitiesBodyDto } from "./dto.js";
import { ProviderContextService } from "../providers/provider-context.service.js";
import { Public } from "../../common/decorators/public.decorator.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { ok } from "../../common/contracts/api-response.js";

// Disponibilités côté prestataire et côté public.
// La route « me » est déclarée avant « :id » (voir même remarque côté catalogue).
@ApiTags("Availability")
@Controller("providers")
export class ProviderAvailabilityController {
  constructor(
    private readonly availability: AvailabilityService,
    private readonly context: ProviderContextService
  ) {}

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
  async replaceMine(@Body() dto: ReplaceAvailabilitiesBodyDto, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    const slots = await this.availability.replaceAll(providerId, dto.slots, req.user?.id);
    return ok(slots, undefined, "Disponibilités mises à jour");
  }

  // POST /providers/me/unavailabilities — déclarer une absence exceptionnelle.
  @ApiBearerAuth()
  @Post("me/unavailabilities")
  @ApiOperation({ summary: "Declare one of my exceptional unavailabilities" })
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
