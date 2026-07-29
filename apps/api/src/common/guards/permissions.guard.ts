import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import { PERMISSIONS_KEY } from "../decorators/permissions.decorator.js";

export interface AuthenticatedRequest {
  user?: {
    id: string;
    roles?: string[];
    permissions?: string[];
    /** Session de rafraîchissement d'où vient ce jeton (voir `AuthTokenPayload.sid`). */
    sessionId?: string;
  };
  /** En-têtes bruts, pour les routes qui lisent `Idempotency-Key` ou `User-Agent`. */
  headers?: Record<string, string | string[] | undefined>;
}

@Injectable()
export class PermissionsGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  canActivate(context: ExecutionContext): boolean {
    const required = this.reflector.getAllAndOverride<string[]>(PERMISSIONS_KEY, [
      context.getHandler(),
      context.getClass()
    ]);

    // Aucune permission déclarée sur la route : on laisse passer.
    // Ce n'est plus un trou de sécurité depuis le Lot 0, car la garde JWT est
    // branchée globalement : la requête a donc déjà prouvé qu'elle est connectée.
    if (!required?.length) {
      return true;
    }

    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const userPermissions = new Set(request.user?.permissions ?? []);
    const allowed = required.every((permission) => userPermissions.has(permission));

    if (!allowed) {
      throw new ForbiddenException("Permission denied");
    }

    return true;
  }
}
