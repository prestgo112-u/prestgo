import { Controller, Get, Param, Query } from "@nestjs/common";
import { ApiOperation, ApiTags } from "@nestjs/swagger";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse, ApiErrorResponse } from "../../common/openapi/api-envelope.decorator.js";
import { Public } from "../../common/decorators/public.decorator.js";
import { ProviderSearchQueryDto } from "./search-dto.js";
import { ProviderSearchService } from "./provider-search.service.js";
import { ProviderPublicProfileDto, ProviderSearchItemDto } from "./response-dto.js";

/**
 * Recherche et fiche publique des prestataires (§7).
 *
 * Routes PUBLIQUES : c'est l'écran d'accueil de l'application. Obliger à créer
 * un compte pour regarder l'offre ferait fuir la moitié des visiteurs.
 *
 * Ce contrôleur est enregistré AVANT l'espace prestataire dans le module :
 * `/providers/search` doit être reconnue avant que `search` ne soit pris pour
 * un identifiant.
 */
@ApiTags("Provider search")
@Controller("providers")
export class ProviderSearchController {
  constructor(private readonly search: ProviderSearchService) {}

  /**
   * GET /providers/search — le moteur de la plateforme.
   *
   * Seuls apparaissent les prestataires `approved`, au compte actif, déclarés
   * disponibles, couvrant la position demandée et — si un créneau est indiqué —
   * réellement libres à cette heure. Ces filtres ne sont pas paramétrables.
   */
  @Public()
  @Get("search")
  @ApiOperation({ summary: "Search available providers by service, location and time slot" })
  @ApiEnvelopeResponse(ProviderSearchItemDto, {
    isArray: true,
    paginated: true,
    description: "Prestataires approuvés, actifs et disponibles correspondant aux filtres"
  })
  @ApiErrorResponse(400, "Combinaison de filtres invalide (tri par distance sans géoposition, date sans heure, ou l'inverse)")
  async searchProviders(@Query() query: ProviderSearchQueryDto) {
    const result = await this.search.search(query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  /**
   * GET /providers/:id/public — fiche publique complète, en un seul appel.
   *
   * Le suffixe `/public` est explicite : il dit que cette vue est expurgée de
   * toute donnée interne, par opposition à `/admin/providers/:id`.
   */
  @Public()
  @Get(":id/public")
  @ApiOperation({ summary: "Get the full public profile of a provider" })
  @ApiEnvelopeResponse(ProviderPublicProfileDto, { description: "Fiche publique complète" })
  @ApiErrorResponse(404, "Prestataire introuvable, ou non approuvé")
  async publicProfile(@Param("id") id: string) {
    return ok(await this.search.publicProfile(id));
  }
}
