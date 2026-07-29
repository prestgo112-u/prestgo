import {
  Body,
  Controller,
  Delete,
  ForbiddenException,
  Get,
  HttpCode,
  Param,
  Patch,
  Post,
  Req
} from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import { THROTTLE_MODERATE } from "../../common/config/throttle.config.js";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse, ApiErrorResponse } from "../../common/openapi/api-envelope.decorator.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { ChangePasswordBodyDto } from "../auth/dto.js";
import { AddressesService } from "./addresses.service.js";
import { FavoritesService } from "./favorites.service.js";
import { MeService } from "./me.service.js";
import { AddressBodyDto, DeleteAccountBodyDto, UpdateAddressBodyDto, UpdateProfileBodyDto } from "./dto.js";
import {
  AddressDto,
  ChangePasswordResultDto,
  DeactivateAccountResultDto,
  FavoriteActionResultDto,
  FavoriteProviderDto,
  MeProfileDto,
  RemoveAddressResultDto,
  UpdateProfileResultDto
} from "./response-dto.js";

/**
 * Espace personnel, commun au client et au prestataire (§3 et §4).
 *
 * Aucune permission d'administration n'est requise : le contrôle d'accès est
 * l'APPARTENANCE. L'utilisateur est résolu depuis le jeton, jamais depuis
 * l'URL — c'est pourquoi ces routes n'ont pas de segment `:userId`.
 */
@ApiTags("Me")
@ApiBearerAuth()
@Controller("me")
export class MeController {
  constructor(
    private readonly me: MeService,
    private readonly addresses: AddressesService,
    private readonly favorites: FavoritesService
  ) {}

  // Chaque route lit l'identité dans le jeton. Un jeton valide a toujours un
  // `id` ; le vérifier explicitement évite un `undefined` silencieux si la
  // garde venait à changer.
  private requireUserId(req: AuthenticatedRequest): string {
    const id = req.user?.id;
    if (!id) {
      throw new ForbiddenException("Authentification requise");
    }
    return id;
  }

  @Get()
  @ApiOperation({ summary: "Get my profile" })
  @ApiEnvelopeResponse(MeProfileDto, { description: "Mon profil" })
  @ApiErrorResponse(401, "Authentification requise ou jeton invalide")
  async profile(@Req() req: AuthenticatedRequest) {
    return ok(await this.me.profile(this.requireUserId(req)));
  }

  @Patch()
  @ApiOperation({ summary: "Update my identity (name, email, phone)" })
  @ApiEnvelopeResponse(UpdateProfileResultDto, { description: "Profil mis à jour" })
  @ApiErrorResponse(401, "Authentification requise ou jeton invalide")
  @ApiErrorResponse(404, "Compte introuvable")
  @ApiErrorResponse(409, "Cet email ou ce numéro est déjà utilisé par un autre compte")
  async updateProfile(@Body() dto: UpdateProfileBodyDto, @Req() req: AuthenticatedRequest) {
    const profile = await this.me.updateProfile(this.requireUserId(req), dto);
    const message = profile.pendingVerifications.length
      ? "Profil mis à jour. Un code de vérification vous a été envoyé."
      : "Profil mis à jour";
    return ok(profile, undefined, message);
  }

  /**
   * POST /me/password — changer son mot de passe.
   *
   * Débit volontairement limité : cette route vérifie l'ancien mot de passe,
   * elle deviendrait sinon un oracle pour le deviner à partir d'un jeton volé.
   */
  @Throttle(THROTTLE_MODERATE)
  @Post("password")
  @HttpCode(200)
  @ApiOperation({ summary: "Change my password and revoke my other sessions" })
  @ApiEnvelopeResponse(ChangePasswordResultDto, { description: "Mot de passe mis à jour" })
  @ApiErrorResponse(400, "Compte introuvable, ou le nouveau mot de passe est identique à l'ancien")
  @ApiErrorResponse(401, "Mot de passe actuel incorrect, ou authentification requise")
  @ApiErrorResponse(429, "Trop de tentatives en peu de temps")
  async changePassword(@Body() dto: ChangePasswordBodyDto, @Req() req: AuthenticatedRequest) {
    const result = await this.me.changePassword(
      this.requireUserId(req),
      dto.currentPassword,
      dto.newPassword,
      // La session courante est épargnée : l'utilisateur reste connecté ici.
      req.user?.sessionId
    );
    return ok(result, undefined, `Mot de passe mis à jour. ${result.revokedSessions} autre(s) session(s) fermée(s).`);
  }

  @Delete()
  @ApiOperation({ summary: "Deactivate my account (status becomes deleted, data is kept)" })
  @ApiEnvelopeResponse(DeactivateAccountResultDto, { description: "Compte désactivé" })
  @ApiErrorResponse(400, "Compte déjà désactivé, ou mission confirmée/en cours en attente")
  @ApiErrorResponse(401, "Mot de passe incorrect, ou authentification requise")
  @ApiErrorResponse(404, "Compte introuvable")
  async deactivate(@Body() dto: DeleteAccountBodyDto, @Req() req: AuthenticatedRequest) {
    const result = await this.me.deactivate(this.requireUserId(req), dto.password);
    return ok(result, undefined, "Compte désactivé");
  }

  // === Adresses (§4) ===

  @Get("addresses")
  @ApiOperation({ summary: "List my addresses" })
  @ApiEnvelopeResponse(AddressDto, { isArray: true, description: "Mes adresses, la valeur par défaut en premier" })
  @ApiErrorResponse(401, "Authentification requise ou jeton invalide")
  async listAddresses(@Req() req: AuthenticatedRequest) {
    return ok(await this.addresses.list(this.requireUserId(req)));
  }

  @Post("addresses")
  @ApiOperation({ summary: "Create one of my addresses" })
  @ApiEnvelopeResponse(AddressDto, { status: 201, description: "Adresse enregistrée" })
  @ApiErrorResponse(400, "Limite de 10 adresses déjà atteinte")
  @ApiErrorResponse(401, "Authentification requise ou jeton invalide")
  async createAddress(@Body() dto: AddressBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.addresses.create(this.requireUserId(req), dto), undefined, "Adresse enregistrée");
  }

  @Patch("addresses/:id")
  @ApiOperation({ summary: "Update one of my addresses" })
  @ApiEnvelopeResponse(AddressDto, { description: "Adresse mise à jour" })
  @ApiErrorResponse(401, "Authentification requise ou jeton invalide")
  @ApiErrorResponse(404, "Adresse introuvable, ou n'appartenant pas à ce compte")
  async updateAddress(
    @Param("id") id: string,
    @Body() dto: UpdateAddressBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    return ok(await this.addresses.update(this.requireUserId(req), id, dto), undefined, "Adresse mise à jour");
  }

  @Delete("addresses/:id")
  @ApiOperation({ summary: "Delete one of my addresses" })
  @ApiEnvelopeResponse(RemoveAddressResultDto, {
    description: "Adresse supprimée, ou archivée si référencée par une mission passée"
  })
  @ApiErrorResponse(401, "Authentification requise ou jeton invalide")
  @ApiErrorResponse(404, "Adresse introuvable, ou n'appartenant pas à ce compte")
  async removeAddress(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    const result = await this.addresses.remove(this.requireUserId(req), id);
    return ok(result, undefined, result.removed ? "Adresse supprimée" : "Adresse retirée du carnet");
  }

  @Post("addresses/:id/default")
  @HttpCode(200)
  @ApiOperation({ summary: "Set one of my addresses as the default one" })
  @ApiEnvelopeResponse(AddressDto, { isArray: true, description: "Mes adresses, à jour de la nouvelle valeur par défaut" })
  @ApiErrorResponse(401, "Authentification requise ou jeton invalide")
  @ApiErrorResponse(404, "Adresse introuvable, ou n'appartenant pas à ce compte")
  async setDefaultAddress(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    return ok(await this.addresses.setDefault(this.requireUserId(req), id), undefined, "Adresse par défaut mise à jour");
  }

  // === Favoris (§4) ===

  @Get("favorites")
  @ApiOperation({ summary: "List my favorite providers" })
  @ApiEnvelopeResponse(FavoriteProviderDto, { isArray: true, description: "Mes prestataires favoris" })
  @ApiErrorResponse(401, "Authentification requise ou jeton invalide")
  async listFavorites(@Req() req: AuthenticatedRequest) {
    return ok(await this.favorites.list(this.requireUserId(req)));
  }

  @Post("favorites/:providerId")
  @HttpCode(200)
  @ApiOperation({ summary: "Add a provider to my favorites (idempotent)" })
  @ApiEnvelopeResponse(FavoriteActionResultDto, { description: "Ajouté aux favoris" })
  @ApiErrorResponse(400, "Ce prestataire n'est pas encore validé, ou il s'agit de mon propre compte")
  @ApiErrorResponse(401, "Authentification requise ou jeton invalide")
  @ApiErrorResponse(404, "Prestataire introuvable")
  async addFavorite(@Param("providerId") providerId: string, @Req() req: AuthenticatedRequest) {
    return ok(await this.favorites.add(this.requireUserId(req), providerId), undefined, "Ajouté aux favoris");
  }

  @Delete("favorites/:providerId")
  @ApiOperation({ summary: "Remove a provider from my favorites (idempotent)" })
  @ApiEnvelopeResponse(FavoriteActionResultDto, { description: "Retiré des favoris" })
  @ApiErrorResponse(401, "Authentification requise ou jeton invalide")
  async removeFavorite(@Param("providerId") providerId: string, @Req() req: AuthenticatedRequest) {
    return ok(await this.favorites.remove(this.requireUserId(req), providerId), undefined, "Retiré des favoris");
  }
}
