import { Controller, Get } from "@nestjs/common";
import { ApiOperation, ApiTags } from "@nestjs/swagger";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse } from "../../common/openapi/api-envelope.decorator.js";
import { Public } from "../../common/decorators/public.decorator.js";
import { PublicSettingsDto } from "./response-dto.js";
import { SettingsService } from "./settings.service.js";

/**
 * Réglages métier visibles par l'utilisateur final (§13).
 *
 * Route PUBLIQUE, comme le catalogue et les zones : ces valeurs déterminent ce
 * que l'application affiche avant même une connexion (délai minimum de
 * réservation sur un écran de réservation ouvert depuis une fiche publique).
 *
 * Elles ne révèlent rien de sensible — ce sont les mêmes durées que les
 * messages d'erreur de l'API annoncent déjà en clair (« Une réservation doit
 * être posée au moins 60 minutes à l'avance »).
 */
@ApiTags("Settings")
@Controller("settings")
export class PublicSettingsController {
  constructor(private readonly settings: SettingsService) {}

  @Public()
  @Get("public")
  @ApiOperation({ summary: "Read the business settings the mobile app must mirror" })
  @ApiEnvelopeResponse(PublicSettingsDto, { description: "Réglages métier applicables aujourd'hui" })
  async publicSettings() {
    return ok(await this.settings.publicSettings());
  }
}
