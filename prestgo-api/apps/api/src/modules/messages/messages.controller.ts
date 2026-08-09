import { Body, Controller, Get, Param, Post, Query, Req } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { MessagesService } from "./messages.service.js";
import { SendMessageBodyDto } from "./dto.js";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { MissionAccessService } from "../missions/mission-access.service.js";
import { NOTIFICATION, NotificationEventsService } from "../notifications/notification-events.service.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse, ApiErrorResponse } from "../../common/openapi/api-envelope.decorator.js";
import { MessageDto } from "./response-dto.js";

// Conversation d'une mission, côté client et prestataire.
@ApiTags("Messages")
@ApiBearerAuth()
@Controller("messages/threads")
export class MessagesController {
  constructor(
    private readonly messages: MessagesService,
    private readonly access: MissionAccessService,
    private readonly events: NotificationEventsService
  ) {}

  /**
   * GET /messages/threads/:id/messages — lire la conversation.
   *
   * PAGINÉE depuis la décision F (écart n°12 du cahier des charges mobile) :
   * cette route renvoyait AUPARAVANT `data` comme un TABLEAU SIMPLE, sans
   * `meta`, avec la conversation ENTIÈRE à chaque appel — aucune limite de
   * taille. `data` est désormais une PAGE de messages, et `meta` porte
   * `{ page, limit, total }`, exactement comme les autres listes de l'API
   * (`page`/`limit`/`sort`, via `PaginationQueryDto`).
   *
   * ⚠️ Changement de forme de réponse : un appelant qui lisait `data` comme
   * « tous les messages » doit désormais s'appuyer sur `meta.total` pour
   * savoir s'il reste des pages, et sur `page`/`limit` pour les parcourir.
   *
   * Le tri par défaut reste `createdAt` CROISSANT (le plus ancien d'abord) :
   * c'est le même ordre qu'avant ce changement, la page 1 correspond donc au
   * DÉBUT de la conversation, pas à ses messages les plus récents.
   * `?sort=-createdAt` inverse l'ordre si un écran veut charger la fin
   * d'abord.
   */
  @Get(":id/messages")
  @ApiOperation({ summary: "Read the messages of a thread I belong to (paginated)" })
  @ApiEnvelopeResponse(MessageDto, {
    isArray: true,
    paginated: true,
    description: "Une page de messages du fil, triés par défaut du plus ancien au plus récent"
  })
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Vous n'êtes pas partie à la mission de cette conversation")
  @ApiErrorResponse(404, "Conversation ou mission introuvable")
  async read(@Param("id") id: string, @Query() query: PaginationQueryDto, @Req() req: AuthenticatedRequest) {
    await this.access.requireThreadParticipant(id, req.user ?? {});
    const result = await this.messages.listMessages(id, query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  // POST /messages/threads/:id/messages — écrire dans la conversation.
  @Post(":id/messages")
  @ApiOperation({ summary: "Send a message in a thread I belong to" })
  @ApiEnvelopeResponse(MessageDto, { status: 201, description: "Message envoyé" })
  @ApiErrorResponse(400, "Conversation clôturée, ou pièce jointe introuvable/ne vous appartenant pas")
  @ApiErrorResponse(401, "Authentification requise")
  @ApiErrorResponse(403, "Vous n'êtes pas partie à la mission de cette conversation")
  @ApiErrorResponse(404, "Conversation ou mission introuvable")
  async send(@Param("id") id: string, @Body() dto: SendMessageBodyDto, @Req() req: AuthenticatedRequest) {
    // Sans ce contrôle, n'importe quel compte connecté pourrait écrire dans la
    // conversation de deux inconnus.
    const { thread, mission } = await this.access.requireThreadParticipant(id, req.user ?? {});
    const message = await this.messages.sendMessage(thread.id, dto.message, req.user?.id, dto.fileIds);

    // L'interlocuteur est prévenu (§12). Un message envoyé sans notification
    // n'est lu que si le destinataire pense à ouvrir l'application.
    const recipient = mission.clientId === req.user?.id ? mission.provider?.userId : mission.clientId;
    if (recipient && recipient !== req.user?.id) {
      await this.events.notify({
        userId: recipient,
        code: NOTIFICATION.chatMessage,
        variables: {
          senderName: await this.messages.senderName(req.user?.id),
          preview: preview(dto.message)
        },
        data: { missionId: mission.id, threadId: thread.id, type: "chat" },
        // Regroupement des push : au plus un par fil et par minute (§12).
        groupKey: `thread:${thread.id}`
      });
    }

    return ok(message, undefined, "Message envoyé");
  }
}

/**
 * Extrait affiché dans la notification.
 *
 * Volontairement court : le corps entier d'un message n'a pas à transiter par
 * un service de push tiers, et une notification tronquée incite à ouvrir
 * l'application — ce qui est le but.
 */
function preview(message: string): string {
  const clean = message.trim().replace(/\s+/g, " ");
  return clean.length > 80 ? `${clean.slice(0, 77)}…` : clean;
}
