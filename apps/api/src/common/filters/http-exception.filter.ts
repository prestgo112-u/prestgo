import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from "@nestjs/common";
import type { Request, Response } from "express";
import { fail, type ApiErrorDetail } from "../contracts/api-response.js";

/**
 * Attrape TOUTES les erreurs de l'application et les renvoie dans le format
 * standard du cahier des charges : { success, message, data, errors, meta }.
 *
 * Règle de sécurité importante (CDC §5.2) : « les erreurs API ne doivent jamais
 * révéler d'informations sensibles ». Un message d'erreur Prisma ou SQL brut
 * dévoilerait les noms de tables et de colonnes. Donc :
 *   - erreur HTTP volontaire (401, 403, 404...) -> on renvoie son message ;
 *   - toute autre erreur (bug, panne base...)   -> message générique côté client,
 *     et trace complète côté serveur uniquement.
 */
@Catch()
export class HttpExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(HttpExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request & { correlationId?: string }>();
    const correlationId = request.correlationId;

    const isHttpException = exception instanceof HttpException;
    const status = isHttpException ? exception.getStatus() : HttpStatus.INTERNAL_SERVER_ERROR;

    const message = isHttpException ? readMessage(exception) : "Erreur interne du serveur";
    const errors = isHttpException ? readErrors(exception) : [];

    // On journalise le détail technique seulement pour les vraies erreurs serveur.
    // L'id de corrélation fait le lien entre ce log et la réponse reçue par le client.
    if (!isHttpException || status >= HttpStatus.INTERNAL_SERVER_ERROR) {
      this.logger.error(
        `[${correlationId ?? "-"}] ${request.method} ${request.originalUrl} -> ${status}`,
        exception instanceof Error ? exception.stack : String(exception)
      );
    }

    response.status(status).json(fail(message, errors, { correlationId }));
  }
}

// Récupère le message lisible d'une exception HTTP.
// Nest range parfois la réponse dans un objet { message, error, statusCode }.
function readMessage(exception: HttpException): string {
  const body = exception.getResponse();
  if (typeof body === "string") {
    return body;
  }
  const message = (body as { message?: string | string[] }).message;
  if (Array.isArray(message)) {
    return message[0] ?? exception.message;
  }
  return message ?? exception.message;
}

/**
 * Construit la liste `errors` du format de réponse standard.
 *
 * Deux sources :
 *   - un tableau `errors` posé explicitement par une règle métier. C'est ce
 *     qui permet au refus de soumission d'un dossier prestataire (§5) de dire
 *     CE QUI manque, et pas seulement « dossier incomplet » ;
 *   - un tableau de messages produit par le `ValidationPipe`.
 */
function readErrors(exception: HttpException): ApiErrorDetail[] {
  const body = exception.getResponse();
  if (typeof body === "string") {
    return [];
  }

  const explicit = (body as { errors?: unknown }).errors;
  if (Array.isArray(explicit)) {
    return explicit
      .filter((item): item is Record<string, unknown> => typeof item === "object" && item !== null)
      .map((item) => ({
        field: typeof item.field === "string" ? item.field : undefined,
        code: typeof item.code === "string" ? item.code : "error",
        message: typeof item.message === "string" ? item.message : ""
      }));
  }

  const message = (body as { message?: string | string[] }).message;
  if (!Array.isArray(message)) {
    return [];
  }
  return message.map((item) => ({ code: "validation_error", message: item }));
}
