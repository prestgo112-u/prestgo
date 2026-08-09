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
import { ApiEnvelopeResponse, ApiErrorResponse } from "../../common/openapi/api-envelope.decorator.js";
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
import {
  MissionDetailDto,
  MissionListItemDto,
  MissionThreadDto,
  MissionTransitionResultDto,
  RescheduleAcceptResultDto,
  RescheduleListItemDto,
  RescheduleRejectResultDto,
  RescheduleRequestResultDto,
  ReviewSubmitResultDto
} from "./response-dto.js";

/** 403/404 communs à toute route qui vérifie l'appartenance à une mission. */
const NOT_A_PARTICIPANT = "Vous n'êtes pas partie à cette mission";
const MISSION_NOT_FOUND = "Mission introuvable";

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
  @ApiEnvelopeResponse(MissionDetailDto, { status: 201, description: "Réservation créée (ou déjà enregistrée si Idempotency-Key rejouée)" })
  @ApiErrorResponse(400, "Date invalide, prestataire indisponible, formule ne correspondant pas, créneau non couvert, ou doublon")
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(404, "Prestataire, formule ou adresse introuvable")
  @ApiErrorResponse(409, "Une requête avec la même Idempotency-Key est déjà en cours de traitement")
  @ApiErrorResponse(429, "Plus de 10 réservations en une heure")
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
  @ApiEnvelopeResponse(MissionDetailDto, { description: "Détail de la mission" })
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, NOT_A_PARTICIPANT)
  @ApiErrorResponse(404, MISSION_NOT_FOUND)
  async detail(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    await this.access.requireParticipant(id, req.user ?? {});
    return ok(await this.booking.detail(id));
  }

  // === Actions du prestataire (§9) ===

  @Post(":id/accept")
  @HttpCode(200)
  @ApiOperation({ summary: "Accept a mission (provider)" })
  @ApiEnvelopeResponse(MissionTransitionResultDto, { description: "Mission acceptée" })
  @ApiErrorResponse(400, "La mission n'est pas au statut pending_provider")
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Vous n'êtes pas le prestataire de cette mission")
  @ApiErrorResponse(404, MISSION_NOT_FOUND)
  async accept(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    const result = await this.lifecycle.accept(id, this.requireUserId(req));
    return ok(result, undefined, "Mission acceptée");
  }

  @Post(":id/refuse")
  @HttpCode(200)
  @ApiOperation({ summary: "Refuse a mission (provider)" })
  @ApiEnvelopeResponse(MissionTransitionResultDto, { description: "Mission refusée" })
  @ApiErrorResponse(400, "La mission n'est pas au statut pending_provider")
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Vous n'êtes pas le prestataire de cette mission")
  @ApiErrorResponse(404, MISSION_NOT_FOUND)
  async refuse(@Param("id") id: string, @Body() dto: MissionReasonBodyDto, @Req() req: AuthenticatedRequest) {
    const result = await this.lifecycle.refuse(id, this.requireUserId(req), dto.reason);
    return ok(result, undefined, "Mission refusée");
  }

  @Post(":id/start")
  @HttpCode(200)
  @ApiOperation({ summary: "Start a mission (provider)" })
  @ApiEnvelopeResponse(MissionTransitionResultDto, { description: "Intervention démarrée" })
  @ApiErrorResponse(400, "La mission n'est pas au statut confirmed, ou trop tôt par rapport à la fenêtre de démarrage")
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Vous n'êtes pas le prestataire de cette mission")
  @ApiErrorResponse(404, MISSION_NOT_FOUND)
  async start(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    const result = await this.lifecycle.start(id, this.requireUserId(req));
    return ok(result, undefined, "Intervention démarrée");
  }

  @Post(":id/complete")
  @HttpCode(200)
  @ApiOperation({ summary: "Complete a mission (provider)" })
  @ApiEnvelopeResponse(MissionTransitionResultDto, { description: "Mission terminée" })
  @ApiErrorResponse(400, "La mission n'est pas au statut in_progress")
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Vous n'êtes pas le prestataire de cette mission")
  @ApiErrorResponse(404, MISSION_NOT_FOUND)
  async complete(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    const result = await this.lifecycle.complete(id, this.requireUserId(req));
    return ok(result, undefined, "Mission terminée");
  }

  // === Annulation, des deux côtés (§8 et §9) ===

  @Post(":id/cancel")
  @HttpCode(200)
  @ApiOperation({ summary: "Cancel a mission I take part in (reason required)" })
  @ApiEnvelopeResponse(MissionTransitionResultDto, { description: "Mission annulée (late: true si moins de X heures avant l'horaire)" })
  @ApiErrorResponse(400, "Motif manquant, transition impossible depuis le statut actuel, ou le prestataire doit utiliser /refuse avant acceptation")
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, NOT_A_PARTICIPANT)
  @ApiErrorResponse(404, MISSION_NOT_FOUND)
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
  @ApiEnvelopeResponse(RescheduleListItemDto, { isArray: true, description: "Historique des demandes de report" })
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, NOT_A_PARTICIPANT)
  @ApiErrorResponse(404, MISSION_NOT_FOUND)
  async listReschedules(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    await this.access.requireParticipant(id, req.user ?? {});
    return ok(await this.reschedules.list(id));
  }

  @Post(":id/reschedule")
  @HttpCode(200)
  @ApiOperation({ summary: "Propose a new date for a mission" })
  @ApiEnvelopeResponse(RescheduleRequestResultDto, { description: "Demande de report envoyée" })
  @ApiErrorResponse(400, "Statut incompatible, date invalide/trop proche/identique, demande déjà en attente, ou créneau non couvert")
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, NOT_A_PARTICIPANT)
  @ApiErrorResponse(404, MISSION_NOT_FOUND)
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
  @ApiEnvelopeResponse(RescheduleAcceptResultDto, { description: "Report accepté, la mission est déplacée" })
  @ApiErrorResponse(400, "Demande déjà traitée, ou le prestataire n'est plus disponible sur ce créneau")
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Vous n'êtes pas partie à cette mission, ou vous êtes l'auteur de cette demande")
  @ApiErrorResponse(404, "Mission ou demande de report introuvable")
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
  @ApiEnvelopeResponse(RescheduleRejectResultDto, { description: "Report refusé, la date reste inchangée" })
  @ApiErrorResponse(400, "Motif manquant, ou demande déjà traitée")
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Vous n'êtes pas partie à cette mission, ou vous êtes l'auteur de cette demande")
  @ApiErrorResponse(404, "Mission ou demande de report introuvable")
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
  @ApiEnvelopeResponse(ReviewSubmitResultDto, { status: 201, description: "Avis publié" })
  @ApiErrorResponse(400, "La mission n'est pas encore terminée, ou la fenêtre de dépôt est dépassée")
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Vous n'êtes pas partie à cette mission, ou seul le client peut déposer un avis en V1")
  @ApiErrorResponse(404, MISSION_NOT_FOUND)
  @ApiErrorResponse(409, "Vous avez déjà déposé un avis sur cette mission")
  async submitReview(@Param("id") id: string, @Body() dto: SubmitReviewBodyDto, @Req() req: AuthenticatedRequest) {
    const review = await this.reviews.submit(id, this.requireUserId(req), dto);
    return ok(review, undefined, "Merci, votre avis est publié");
  }

  // === Conversation de la mission (§12) ===

  @Get(":id/thread")
  @ApiOperation({ summary: "Get the chat thread of a mission I take part in" })
  @ApiEnvelopeResponse(MissionThreadDto, { description: "Fil de discussion de la mission" })
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, NOT_A_PARTICIPANT)
  @ApiErrorResponse(404, "Mission introuvable, ou cette mission n'a pas de conversation")
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
  @ApiEnvelopeResponse(MissionListItemDto, { isArray: true, paginated: true, description: "Mes missions, la plus récente d'abord" })
  @ApiErrorResponse(401, "Authentification requise")
  async listMine(@Query() query: MyMissionsQueryDto, @Req() req: AuthenticatedRequest) {
    const clientId = req.user?.id;
    if (!clientId) {
      throw new ForbiddenException("Authentification requise");
    }
    const result = await this.booking.listForClient(clientId, query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }
}
