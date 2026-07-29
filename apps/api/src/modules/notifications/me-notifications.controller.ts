import { Body, Controller, Delete, ForbiddenException, Get, HttpCode, Param, Patch, Post, Query, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import { THROTTLE_DEVICE } from "../../common/config/throttle.config.js";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse, ApiErrorResponse } from "../../common/openapi/api-envelope.decorator.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { DevicesService } from "./devices.service.js";
import { MyNotificationsQueryDto, RegisterDeviceBodyDto } from "./me-dto.js";
import { NotificationsService } from "./notifications.service.js";
import {
  DeviceDto,
  MarkReadResultDto,
  MyNotificationDto,
  UnreadCountDto,
  UnregisterDeviceResultDto
} from "./response-dto.js";

/**
 * Notifications et appareils de l'utilisateur connecté (§12).
 *
 * Toutes ces routes travaillent sur l'identité du jeton : il n'existe aucun
 * moyen de lire la boîte de notifications de quelqu'un d'autre.
 */
@ApiTags("My notifications")
@ApiBearerAuth()
@Controller("me")
export class MeNotificationsController {
  constructor(
    private readonly notifications: NotificationsService,
    private readonly devices: DevicesService
  ) {}

  private requireUserId(req: AuthenticatedRequest): string {
    const id = req.user?.id;
    if (!id) {
      throw new ForbiddenException("Authentification requise");
    }
    return id;
  }

  @Get("notifications")
  @ApiOperation({ summary: "List my notifications" })
  @ApiEnvelopeResponse(MyNotificationDto, { isArray: true, paginated: true, description: "Mes notifications" })
  @ApiErrorResponse(401, "Authentification requise")
  async list(@Query() query: MyNotificationsQueryDto, @Req() req: AuthenticatedRequest) {
    const result = await this.notifications.listForUser(this.requireUserId(req), query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  /** Pastille de l'application : un compteur, sans charger la liste. */
  @Get("notifications/unread-count")
  @ApiOperation({ summary: "Count my unread notifications" })
  @ApiEnvelopeResponse(UnreadCountDto, { description: "Nombre de notifications non lues" })
  @ApiErrorResponse(401, "Authentification requise")
  async unreadCount(@Req() req: AuthenticatedRequest) {
    return ok(await this.notifications.unreadCount(this.requireUserId(req)));
  }

  /**
   * Idempotente : marquer lue une notification déjà lue, inexistante ou
   * appartenant à un autre compte renvoie simplement `updated: 0` — jamais
   * d'erreur (le filtre `updateMany` est posé sur le propriétaire).
   */
  @Patch("notifications/:id/read")
  @ApiOperation({ summary: "Mark one of my notifications as read" })
  @ApiEnvelopeResponse(MarkReadResultDto, { description: "Notification marquée lue (ou déjà lue / non trouvée : updated=0)" })
  @ApiErrorResponse(401, "Authentification requise")
  async markRead(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    return ok(await this.notifications.markRead(this.requireUserId(req), id), undefined, "Notification marquée lue");
  }

  @Post("notifications/read-all")
  @HttpCode(200)
  @ApiOperation({ summary: "Mark all my notifications as read" })
  @ApiEnvelopeResponse(MarkReadResultDto, { description: "Toutes mes notifications sont marquées lues" })
  @ApiErrorResponse(401, "Authentification requise")
  async markAllRead(@Req() req: AuthenticatedRequest) {
    const result = await this.notifications.markAllRead(this.requireUserId(req));
    return ok(result, undefined, `${result.updated} notification(s) marquée(s) lue(s)`);
  }

  // === Appareils (push) ===

  @Get("devices")
  @ApiOperation({ summary: "List my registered devices" })
  @ApiEnvelopeResponse(DeviceDto, { isArray: true, description: "Mes appareils actifs (le jeton lui-même n'est jamais renvoyé)" })
  @ApiErrorResponse(401, "Authentification requise")
  async listDevices(@Req() req: AuthenticatedRequest) {
    return ok(await this.devices.list(this.requireUserId(req)));
  }

  /**
   * POST /me/devices — enregistrer un jeton push.
   *
   * Débit limité à 30 par JOUR (§14.5) — voir `throttle.config.ts`.
   */
  @Throttle(THROTTLE_DEVICE)
  @Post("devices")
  @HttpCode(200)
  @ApiOperation({ summary: "Register one of my push device tokens (idempotent)" })
  @ApiEnvelopeResponse(DeviceDto, { description: "Appareil enregistré (réaffecté si le jeton existait déjà)" })
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(429, "Plus de 30 enregistrements en un jour")
  async registerDevice(@Body() dto: RegisterDeviceBodyDto, @Req() req: AuthenticatedRequest) {
    const device = await this.devices.register(this.requireUserId(req), dto.platform, dto.token);
    return ok(device, undefined, "Appareil enregistré");
  }

  /** Idempotente : désenregistrer un jeton absent ou d'un autre compte renvoie `unregistered: false`, jamais d'erreur. */
  @Delete("devices/:token")
  @ApiOperation({ summary: "Unregister one of my push device tokens" })
  @ApiEnvelopeResponse(UnregisterDeviceResultDto, { description: "Appareil désenregistré (ou déjà absent : unregistered=false)" })
  @ApiErrorResponse(401, "Authentification requise")
  async unregisterDevice(@Param("token") token: string, @Req() req: AuthenticatedRequest) {
    return ok(await this.devices.unregister(this.requireUserId(req), token), undefined, "Appareil désenregistré");
  }
}
