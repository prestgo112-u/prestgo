import {
  Body,
  Controller,
  ForbiddenException,
  Get,
  Headers,
  HttpCode,
  Param,
  Post,
  Query,
  Req
} from "@nestjs/common";
import { ApiBearerAuth, ApiHeader, ApiOperation, ApiTags } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import { THROTTLE_BOOKING } from "../../common/config/throttle.config.js";
import { ok } from "../../common/contracts/api-response.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { IdempotencyService } from "../../common/idempotency/idempotency.service.js";
import { ReviewSubmissionService } from "../reviews/review-submission.service.js";
import { MissionAccessService } from "./mission-access.service.js";
import { MissionBookingService } from "./mission-booking.service.js";
import { MissionLifecycleService } from "./mission-lifecycle.service.js";
import { MissionRescheduleService } from "./mission-reschedule.service.js";
import {
  CreateMissionBodyDto,
  MissionReasonBodyDto,
  MyMissionsQueryDto,
  RequestRescheduleBodyDto,
  SubmitReviewBodyDto
} from "./mobile-dto.js";

const CREATE_MISSION_ENDPOINT = "POST /missions";

/**
 * Cycle de vie d'une mission, côté client et côté prestataire (§8, §9, §10, §11).
 *
 * Aucune de ces routes ne réécrit la logique métier : elles appellent le
 * service de transition commun (§14.1), celui-là même qu'utilise
 * `PATCH /admin/missions/:id/status`. Une transition interdite est donc refusée
 * avec exactement le même message des deux côtés.
 */
@ApiTags("Missions")
@ApiBearerAuth()
@Controller("missions")
export class MissionActionsController {
  constructor(
    private readonly booking: MissionBookingService,
    private readonly lifecycle: MissionLifecycleService,
    private readonly reschedules: MissionRescheduleService,
    private readonly reviews: ReviewSubmissionService,
    private readonly access: MissionAccessService,
    private readonly idempotency: IdempotencyService
  ) {}

  private requireUserId(req: AuthenticatedRequest): string {
    const id = req.user?.id;
    if (!id) {
      throw new ForbiddenException("Authentification requise");
    }
    return id;
  }

  /**
   * POST /missions — réserver une prestation (§8).
   *
   * Débit limité à 10 par heure et par utilisateur (§14.5) : une application en
   * boucle ne doit pas pouvoir saturer l'agenda des prestataires.
   *
   * `Idempotency-Key` (§14.6) : renvoyer la même clé dans les dix minutes
   * renvoie la MÊME mission au lieu d'en créer une seconde. C'est ce qui
   * protège d'un réseau mobile qui coupe entre l'envoi et la réponse.
   */
  @Throttle(THROTTLE_BOOKING)
  @Post()
  @ApiOperation({ summary: "Book a service (create a mission)" })
  @ApiHeader({
    name: "Idempotency-Key",
    required: false,
    description: "Rejouer la même clé sous 10 minutes renvoie la mission déjà créée."
  })
  async create(
    @Body() dto: CreateMissionBodyDto,
    @Req() req: AuthenticatedRequest,
    @Headers("idempotency-key") idempotencyKey?: string
  ) {
    const clientId = this.requireUserId(req);
    const key = idempotencyKey?.trim();

    if (!key) {
      const mission = await this.booking.create(clientId, dto);
      return ok(mission, undefined, "Réservation créée");
    }

    const reservation = await this.idempotency.reserve(clientId, CREATE_MISSION_ENDPOINT, key);
    if (reservation.replay) {
      // Rejeu : on renvoie la mission d'origine, avec le même code de succès.
      return ok(await this.booking.detail(reservation.resourceId), undefined, "Réservation déjà enregistrée");
    }

    try {
      const mission = await this.booking.create(clientId, dto);
      await this.idempotency.complete(clientId, CREATE_MISSION_ENDPOINT, key, mission.id);
      return ok(mission, undefined, "Réservation créée");
    } catch (error) {
      // La clé est libérée : un refus corrigeable (créneau pris, adresse hors
      // zone) ne doit pas condamner la clé pendant dix minutes.
      await this.idempotency.release(clientId, CREATE_MISSION_ENDPOINT, key);
      throw error;
    }
  }

  /** GET /missions/:id — détail, réservé aux parties prenantes et au support. */
  @Get(":id")
  @ApiOperation({ summary: "Get a mission I take part in" })
  async detail(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    await this.access.requireParticipant(id, req.user ?? {});
    return ok(await this.booking.detail(id));
  }

  // === Actions du prestataire (§9) ===

  @Post(":id/accept")
  @HttpCode(200)
  @ApiOperation({ summary: "Accept a mission (provider)" })
  async accept(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    const result = await this.lifecycle.accept(id, this.requireUserId(req));
    return ok(result, undefined, "Mission acceptée");
  }

  @Post(":id/refuse")
  @HttpCode(200)
  @ApiOperation({ summary: "Refuse a mission (provider)" })
  async refuse(@Param("id") id: string, @Body() dto: MissionReasonBodyDto, @Req() req: AuthenticatedRequest) {
    const result = await this.lifecycle.refuse(id, this.requireUserId(req), dto.reason);
    return ok(result, undefined, "Mission refusée");
  }

  @Post(":id/start")
  @HttpCode(200)
  @ApiOperation({ summary: "Start a mission (provider)" })
  async start(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    const result = await this.lifecycle.start(id, this.requireUserId(req));
    return ok(result, undefined, "Intervention démarrée");
  }

  @Post(":id/complete")
  @HttpCode(200)
  @ApiOperation({ summary: "Complete a mission (provider)" })
  async complete(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    const result = await this.lifecycle.complete(id, this.requireUserId(req));
    return ok(result, undefined, "Mission terminée");
  }

  // === Annulation, des deux côtés (§8 et §9) ===

  @Post(":id/cancel")
  @HttpCode(200)
  @ApiOperation({ summary: "Cancel a mission I take part in (reason required)" })
  async cancel(@Param("id") id: string, @Body() dto: MissionReasonBodyDto, @Req() req: AuthenticatedRequest) {
    const result = await this.lifecycle.cancelByParticipant(id, this.requireUserId(req), dto.reason, dto.details);
    return ok(
      result,
      undefined,
      result.late
        ? "Mission annulée. L'annulation est enregistrée comme tardive."
        : "Mission annulée"
    );
  }

  // === Reprogrammation à deux parties (§10) ===

  @Get(":id/reschedules")
  @ApiOperation({ summary: "List the reschedule requests of a mission" })
  async listReschedules(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    await this.access.requireParticipant(id, req.user ?? {});
    return ok(await this.reschedules.list(id));
  }

  @Post(":id/reschedule")
  @HttpCode(200)
  @ApiOperation({ summary: "Propose a new date for a mission" })
  async requestReschedule(
    @Param("id") id: string,
    @Body() dto: RequestRescheduleBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    const result = await this.reschedules.request(id, this.requireUserId(req), dto.newDate, dto.reason);
    return ok(result, undefined, "Demande de report envoyée. Elle doit être acceptée par l'autre partie.");
  }

  @Post(":id/reschedule/:rid/accept")
  @HttpCode(200)
  @ApiOperation({ summary: "Accept a reschedule request made by the other party" })
  async acceptReschedule(
    @Param("id") id: string,
    @Param("rid") rid: string,
    @Req() req: AuthenticatedRequest
  ) {
    const result = await this.reschedules.accept(id, rid, this.requireUserId(req));
    return ok(result, undefined, "Report accepté : la mission est déplacée");
  }

  @Post(":id/reschedule/:rid/reject")
  @HttpCode(200)
  @ApiOperation({ summary: "Reject a reschedule request made by the other party" })
  async rejectReschedule(
    @Param("id") id: string,
    @Param("rid") rid: string,
    @Body() dto: MissionReasonBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    const result = await this.reschedules.reject(id, rid, this.requireUserId(req), dto.reason);
    return ok(result, undefined, "Report refusé : la date reste inchangée");
  }

  // === Avis (§11) ===

  @Post(":id/review")
  @HttpCode(201)
  @ApiOperation({ summary: "Post my review of a completed mission" })
  async submitReview(@Param("id") id: string, @Body() dto: SubmitReviewBodyDto, @Req() req: AuthenticatedRequest) {
    const review = await this.reviews.submit(id, this.requireUserId(req), dto);
    return ok(review, undefined, "Merci, votre avis est publié");
  }

  // === Conversation de la mission (§12) ===

  @Get(":id/thread")
  @ApiOperation({ summary: "Get the chat thread of a mission I take part in" })
  async thread(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    await this.access.requireParticipant(id, req.user ?? {}, "admin.messages.read");
    return ok(await this.booking.thread(id));
  }
}

/**
 * Missions du client connecté (§8).
 *
 * Contrôleur distinct parce que le préfixe diffère (`/me` et non `/missions`) ;
 * la logique, elle, est la même — celle de `MissionBookingService`.
 */
@ApiTags("Missions")
@ApiBearerAuth()
@Controller("me")
export class ClientMissionsController {
  constructor(private readonly booking: MissionBookingService) {}

  @Get("missions")
  @ApiOperation({ summary: "List my missions as a client" })
  async listMine(@Query() query: MyMissionsQueryDto, @Req() req: AuthenticatedRequest) {
    const clientId = req.user?.id;
    if (!clientId) {
      throw new ForbiddenException("Authentification requise");
    }
    const result = await this.booking.listForClient(clientId, query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }
}
