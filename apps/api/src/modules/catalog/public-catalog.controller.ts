import { Body, Controller, Get, Param, Patch, Post, Req } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { CatalogService } from "./catalog.service.js";
import {
  CreateServicePackBodyDto,
  CreateServicePackOptionBodyDto,
  UpdateServicePackBodyDto,
  UpdateServicePackOptionBodyDto
} from "./dto.js";
import { ProviderContextService } from "../providers/provider-context.service.js";
import { Public } from "../../common/decorators/public.decorator.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { ok } from "../../common/contracts/api-response.js";

// Catalogue public : consultable sans compte (c'est la vitrine de la plateforme).
@ApiTags("Catalog")
@Controller("categories")
export class PublicCategoriesController {
  constructor(private readonly catalog: CatalogService) {}

  // GET /categories — uniquement les catégories et services ACTIFS.
  @Public()
  @Get()
  @ApiOperation({ summary: "List active categories with their service types" })
  async list() {
    return ok(await this.catalog.listPublicCategories());
  }
}

/**
 * Formules de prestation.
 *
 * Les routes « me » sont déclarées AVANT « :id » : sinon le segment « me »
 * serait capturé comme un identifiant de prestataire.
 */
@ApiTags("Catalog")
@Controller("providers")
export class ProviderServicePacksController {
  constructor(
    private readonly catalog: CatalogService,
    private readonly context: ProviderContextService
  ) {}

  // POST /providers/me/service-packs — le prestataire connecté crée une formule.
  @ApiBearerAuth()
  @Post("me/service-packs")
  @ApiOperation({ summary: "Create one of my service packs" })
  async createMine(@Body() dto: CreateServicePackBodyDto, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.catalog.createPackForProvider(providerId, dto, req.user?.id), undefined, "Formule créée");
  }

  // PATCH /providers/me/service-packs/:id
  @ApiBearerAuth()
  @Patch("me/service-packs/:id")
  @ApiOperation({ summary: "Update one of my service packs" })
  async updateMine(
    @Param("id") id: string,
    @Body() dto: UpdateServicePackBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.catalog.updatePackForProvider(providerId, id, dto, req.user?.id));
  }

  /**
   * Options d'une formule (§8).
   *
   * Ces routes sont ce qui rend `optionIds` utilisable à la réservation : sans
   * elles, le prestataire n'aurait aucun moyen de proposer un supplément.
   */
  @ApiBearerAuth()
  @Get("me/service-packs/:packId/options")
  @ApiOperation({ summary: "List the options of one of my service packs" })
  async listMyPackOptions(@Param("packId") packId: string, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.catalog.listPackOptionsForProvider(providerId, packId));
  }

  @ApiBearerAuth()
  @Post("me/service-packs/:packId/options")
  @ApiOperation({ summary: "Add an option to one of my service packs" })
  async createMyPackOption(
    @Param("packId") packId: string,
    @Body() dto: CreateServicePackOptionBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(
      await this.catalog.createPackOptionForProvider(providerId, packId, dto, req.user?.id),
      undefined,
      "Option créée"
    );
  }

  @ApiBearerAuth()
  @Patch("me/service-pack-options/:id")
  @ApiOperation({ summary: "Update or deactivate one of my service pack options" })
  async updateMyPackOption(
    @Param("id") id: string,
    @Body() dto: UpdateServicePackOptionBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.catalog.updatePackOptionForProvider(providerId, id, dto, req.user?.id));
  }

  // GET /providers/:id/service-packs — vitrine publique d'un prestataire.
  @Public()
  @Get(":id/service-packs")
  @ApiOperation({ summary: "List the active service packs of a provider" })
  async listForProvider(@Param("id") id: string) {
    return ok(await this.catalog.listProviderPacks(id));
  }
}
