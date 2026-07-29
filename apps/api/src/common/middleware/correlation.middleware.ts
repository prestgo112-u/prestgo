import { Injectable, NestMiddleware } from "@nestjs/common";
import type { NextFunction, Request, Response } from "express";
import { randomUUID } from "node:crypto";
import { resolveClientIp, runWithRequestContext } from "./request-context.js";

/**
 * Pose un identifiant unique sur chaque requête (l'« id de corrélation ») et
 * ouvre le contexte de requête.
 *
 * À quoi sert l'id : quand un utilisateur signale une erreur, il donne cet id
 * (renvoyé dans la réponse et dans l'en-tête `x-correlation-id`) et on retrouve
 * immédiatement la ligne de log correspondante côté serveur.
 *
 * Si l'appelant fournit déjà un `x-correlation-id`, on le réutilise : cela
 * permet de suivre une même action à travers plusieurs services.
 *
 * Depuis le Lot 7, la suite du traitement s'exécute DANS un contexte
 * (`AsyncLocalStorage`) qui porte aussi l'adresse IP : c'est ce qui permet au
 * journal d'audit de la consigner sans que chaque service ait à recevoir la
 * requête HTTP en paramètre.
 */
@Injectable()
export class CorrelationMiddleware implements NestMiddleware {
  use(request: Request & { correlationId?: string }, response: Response, next: NextFunction): void {
    const incoming = request.header("x-correlation-id");
    const correlationId = incoming?.trim() || randomUUID();

    request.correlationId = correlationId;
    response.setHeader("x-correlation-id", correlationId);

    runWithRequestContext({ correlationId, ip: resolveClientIp(request) }, () => {
      next();
    });
  }
}
