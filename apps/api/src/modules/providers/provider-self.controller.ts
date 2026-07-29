import { Body, Controller, Delete, ForbiddenException, Get, HttpCode, Param, Patch, Post, Put, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse, ApiErrorResponse } from "../../common/openapi/api-envelope.decorator.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { ProviderDocumentsSelfService } from "../documents/provider-documents-self.service.js";
import { ProviderContextService } from "./provider-context.service.js";
import { ProviderSelfService } from "./provider-self.service.js";
import {
  CreatePortfolioItemBodyDto,
  CreateProviderProfileBodyDto,
  CreateProviderServiceBodyDto,
  ReplaceProviderZonesBodyDto,
  SubmitDocumentBodyDto,
  UpdatePortfolioItemBodyDto,
  UpdateProviderProfileBodyDto,
  UpdateProviderServiceBodyDto
} from "./self-dto.js";
import {
  ProviderDocumentDto,
  ProviderDocumentsOverviewDto,
  ProviderOverviewDto,
  ProviderPortfolioItemDto,
  ProviderPortfolioItemListDto,
  ProviderServiceDto,
  ProviderServiceListItemDto,
  ProviderZoneDto,
  RemovedResultDto
} from "./response-dto.js";

/** 403 commun à toutes les routes `providers/me/*` : voir `ProviderContextService.requireProviderId`. */
const NO_PROVIDER_PROFILE = "Authentification requise, ou ce compte n'a pas de profil prestataire";

/**
 * Espace prestataire (§5 et §6).
 *
 * Le prestataire est TOUJOURS résolu depuis le jeton via
 * `ProviderContextService` : aucune de ces routes n'accepte un identifiant de
 * prestataire dans l'URL. C'est ce qui rend impossible de modifier le dossier
 * d'un confrère en changeant un segment d'adresse.
 *
 * Les routes `me/…` sont déclarées avant tout segment dynamique, sans quoi
 * « me » serait capturé comme un identifiant.
 */
@ApiTags("Provider space")
@ApiBearerAuth()
@Controller("providers")
export class ProviderSelfController {
  constructor(
    private readonly self: ProviderSelfService,
    private readonly documents: ProviderDocumentsSelfService,
    private readonly context: ProviderContextService
  ) {}

  private requireUserId(req: AuthenticatedRequest): string {
    const id = req.user?.id;
    if (!id) {
      throw new ForbiddenException("Authentification requise");
    }
    return id;
  }

  // === Profil ===

  // POST /providers/me — créer son profil (statut `profile_incomplete`).
  @Post("me")
  @ApiOperation({ summary: "Create my provider profile" })
  @ApiEnvelopeResponse(ProviderOverviewDto, { status: 201, description: "Profil prestataire créé" })
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(409, "Ce compte a déjà un profil prestataire")
  async createProfile(@Body() dto: CreateProviderProfileBodyDto, @Req() req: AuthenticatedRequest) {
    const profile = await this.self.createProfile(this.requireUserId(req), dto);
    return ok(profile, undefined, "Profil prestataire créé. Complétez votre dossier pour le soumettre.");
  }

  // GET /providers/me — profil, statut et checklist de complétude.
  @Get("me")
  @ApiOperation({ summary: "Get my provider profile with its completion checklist" })
  @ApiEnvelopeResponse(ProviderOverviewDto, { description: "Mon dossier prestataire" })
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  async myProfile(@Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.self.overview(providerId));
  }

  @Patch("me")
  @ApiOperation({ summary: "Update my provider profile" })
  @ApiEnvelopeResponse(ProviderOverviewDto, { description: "Profil mis à jour" })
  @ApiErrorResponse(400, "Dossier en cours de vérification (non modifiable sur le fond), ou photo de profil invalide")
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  @ApiErrorResponse(404, "Fichier d'avatar introuvable, ou ne vous appartenant pas")
  async updateProfile(@Body() dto: UpdateProviderProfileBodyDto, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.self.updateProfile(providerId, this.requireUserId(req), dto), undefined, "Profil mis à jour");
  }

  // POST /providers/me/submit — soumettre le dossier à la vérification.
  @Post("me/submit")
  @HttpCode(200)
  @ApiOperation({ summary: "Submit my provider file for review" })
  @ApiEnvelopeResponse(ProviderOverviewDto, { description: "Dossier soumis à la vérification" })
  @ApiErrorResponse(400, "Dossier incomplet (le détail figure dans errors), ou statut incompatible avec une soumission")
  @ApiErrorResponse(403, "Re-soumission bloquée par un agent, ou pas de profil prestataire")
  async submit(@Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    const result = await this.self.submit(providerId, this.requireUserId(req));
    return ok(result, undefined, "Dossier soumis à la vérification");
  }

  // === Services ===

  @Get("me/services")
  @ApiOperation({ summary: "List my declared services" })
  @ApiEnvelopeResponse(ProviderServiceListItemDto, { isArray: true, description: "Mes services déclarés, avec leurs formules" })
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  async listServices(@Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.self.listServices(providerId));
  }

  @Post("me/services")
  @ApiOperation({ summary: "Declare one of my services" })
  @ApiEnvelopeResponse(ProviderServiceDto, { status: 201, description: "Service déclaré" })
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  @ApiErrorResponse(404, "Type de service introuvable ou inactif")
  @ApiErrorResponse(409, "Un service actif de ce type existe déjà")
  async createService(@Body() dto: CreateProviderServiceBodyDto, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.self.createService(providerId, this.requireUserId(req), dto), undefined, "Service déclaré");
  }

  @Patch("me/services/:id")
  @ApiOperation({ summary: "Update or deactivate one of my services" })
  @ApiEnvelopeResponse(ProviderServiceDto, { description: "Service mis à jour" })
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  @ApiErrorResponse(404, "Service introuvable pour ce prestataire")
  async updateService(
    @Param("id") id: string,
    @Body() dto: UpdateProviderServiceBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.self.updateService(providerId, this.requireUserId(req), id, dto), undefined, "Service mis à jour");
  }

  // === Documents (§6) ===

  @Get("me/documents")
  @ApiOperation({ summary: "List my documents, their status and rejection reasons" })
  @ApiEnvelopeResponse(ProviderDocumentsOverviewDto, { description: "Mes justificatifs et ceux qui manquent encore" })
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  async listDocuments(@Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.documents.list(providerId));
  }

  /**
   * POST /providers/me/documents — soumettre un justificatif.
   *
   * Le fichier est d'abord envoyé par `POST /files/upload`, puis rattaché ici.
   * Ce découpage permet à l'application mobile de gérer l'envoi (barre de
   * progression, reprise) indépendamment de la règle métier.
   */
  @Post("me/documents")
  @ApiOperation({ summary: "Submit one of my supporting documents" })
  @ApiEnvelopeResponse(ProviderDocumentDto, { status: 201, description: "Justificatif transmis" })
  @ApiErrorResponse(400, "Type de document vide, ou ce justificatif est déjà validé")
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  @ApiErrorResponse(404, "Fichier introuvable, ou ne vous appartenant pas")
  async submitDocument(@Body() dto: SubmitDocumentBodyDto, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    const document = await this.documents.submit(providerId, this.requireUserId(req), dto);
    return ok(document, undefined, "Justificatif transmis");
  }

  // === Zones (§6) ===

  @Get("me/zones")
  @ApiOperation({ summary: "List my intervention zones" })
  @ApiEnvelopeResponse(ProviderZoneDto, { isArray: true, description: "Mes zones d'intervention" })
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  async listZones(@Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.self.listZones(providerId));
  }

  @Put("me/zones")
  @ApiOperation({ summary: "Replace the whole list of my intervention zones" })
  @ApiEnvelopeResponse(ProviderZoneDto, { isArray: true, description: "Zones d'intervention mises à jour" })
  @ApiErrorResponse(400, "Plus de 15 zones demandées, ou zone inconnue/inactive")
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  async replaceZones(@Body() dto: ReplaceProviderZonesBodyDto, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    const zones = await this.self.replaceZones(providerId, this.requireUserId(req), dto.zoneIds);
    return ok(zones, undefined, "Zones d'intervention mises à jour");
  }

  // === Portfolio (§6) ===

  @Get("me/portfolio")
  @ApiOperation({ summary: "List my portfolio items" })
  @ApiEnvelopeResponse(ProviderPortfolioItemListDto, { isArray: true, description: "Mes réalisations" })
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  async listPortfolio(@Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.self.listPortfolio(providerId));
  }

  @Post("me/portfolio")
  @ApiOperation({ summary: "Add one of my portfolio items" })
  @ApiEnvelopeResponse(ProviderPortfolioItemDto, { status: 201, description: "Réalisation ajoutée" })
  @ApiErrorResponse(400, "Portfolio limité à 20 réalisations, ou le fichier n'est pas une image")
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  @ApiErrorResponse(404, "Fichier introuvable, ou ne vous appartenant pas")
  async addPortfolioItem(@Body() dto: CreatePortfolioItemBodyDto, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    const item = await this.self.addPortfolioItem(providerId, this.requireUserId(req), dto);
    return ok(item, undefined, "Réalisation ajoutée");
  }

  @Patch("me/portfolio/:id")
  @ApiOperation({ summary: "Update one of my portfolio items" })
  @ApiEnvelopeResponse(ProviderPortfolioItemDto, { description: "Réalisation mise à jour" })
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  @ApiErrorResponse(404, "Réalisation introuvable")
  async updatePortfolioItem(
    @Param("id") id: string,
    @Body() dto: UpdatePortfolioItemBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.self.updatePortfolioItem(providerId, this.requireUserId(req), id, dto));
  }

  @Delete("me/portfolio/:id")
  @ApiOperation({ summary: "Remove one of my portfolio items" })
  @ApiEnvelopeResponse(RemovedResultDto, { description: "Réalisation retirée" })
  @ApiErrorResponse(403, NO_PROVIDER_PROFILE)
  @ApiErrorResponse(404, "Réalisation introuvable")
  async removePortfolioItem(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    const providerId = await this.context.requireProviderId(req.user?.id);
    return ok(await this.self.removePortfolioItem(providerId, this.requireUserId(req), id), undefined, "Réalisation retirée");
  }
}
