import { Controller, ForbiddenException, Get, Param, Patch, Query, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse, ApiErrorResponse } from "../../common/openapi/api-envelope.decorator.js";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { MissionAccessService } from "../missions/mission-access.service.js";
import { MessagesService } from "./messages.service.js";
import { MarkThreadReadResultDto, MyThreadListItemDto, ThreadsUnreadCountDto } from "./response-dto.js";

/**
 * Mes conversations (§12).
 *
 * Confort mobile : l'application a besoin d'une liste « toutes mes
 * discussions » avec le dernier message et le nombre de non-lus, pour afficher
 * l'onglet messagerie sans interroger mission par mission.
 */
@ApiTags("Messages")
@ApiBearerAuth()
@Controller("me")
export class MyThreadsController {
  constructor(private readonly messages: MessagesService) {}

  @Get("threads")
  @ApiOperation({ summary: "List my conversations with their last message and unread count" })
  @ApiEnvelopeResponse(MyThreadListItemDto, { isArray: true, paginated: true, description: "Mes conversations" })
  @ApiErrorResponse(401, "Authentification requise")
  async listMine(@Query() query: PaginationQueryDto, @Req() req: AuthenticatedRequest) {
    const userId = req.user?.id;
    if (!userId) {
      throw new ForbiddenException("Authentification requise");
    }
    const result = await this.messages.listThreadsForUser(userId, query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  /**
   * Pastille de l'onglet messagerie : un compteur, sans charger les fils.
   *
   * Déclarée AVANT tout segment dynamique du même préfixe, et distincte de
   * `notifications/unread-count` : les deux compteurs ne mesurent pas la même
   * chose (une notification `chat.message` peut être lue sans que le message
   * lui-même le soit).
   */
  @Get("threads/unread-count")
  @ApiOperation({ summary: "Count my unread messages across all my conversations" })
  @ApiEnvelopeResponse(ThreadsUnreadCountDto, { description: "Nombre de messages non lus, tous fils confondus" })
  @ApiErrorResponse(401, "Authentification requise")
  async unreadCount(@Req() req: AuthenticatedRequest) {
    const userId = req.user?.id;
    if (!userId) {
      throw new ForbiddenException("Authentification requise");
    }
    return ok(await this.messages.unreadCountForUser(userId));
  }
}

/** Marquage « lu » d'une conversation (§12). */
@ApiTags("Messages")
@ApiBearerAuth()
@Controller("messages/threads")
export class ThreadReadController {
  constructor(
    private readonly messages: MessagesService,
    private readonly access: MissionAccessService
  ) {}

  @Patch(":id/read")
  @ApiOperation({ summary: "Mark the messages of a thread as read" })
  @ApiEnvelopeResponse(MarkThreadReadResultDto, { description: "Messages marqués lus" })
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Vous n'êtes pas partie à la mission de cette conversation")
  @ApiErrorResponse(404, "Conversation ou mission introuvable")
  async markRead(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    const userId = req.user?.id;
    if (!userId) {
      throw new ForbiddenException("Authentification requise");
    }
    // Le contrôle d'appartenance passe par le même service que la lecture et
    // l'écriture des messages : une seule règle, un seul endroit.
    await this.access.requireThreadParticipant(id, req.user ?? {});
    const result = await this.messages.markThreadRead(id, userId);
    return ok(result, undefined, `${result.updated} message(s) marqué(s) lu(s)`);
  }
}
