import { CanActivate, ExecutionContext, Injectable } from "@nestjs/common";
import { Reflector } from "@nestjs/core";
import { JwtStrategy } from "./jwt.strategy.js";
import { IS_PUBLIC_KEY } from "../../common/decorators/public.decorator.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";

/**
 * Un "guard" NestJS = un videur à l'entrée d'une route : il décide si la requête
 * a le droit de passer. Ici il lit le token Bearer envoyé par le navigateur,
 * le vérifie, puis attache l'utilisateur décodé sur `request.user`.
 * Ainsi le PermissionsGuard qui vient juste après peut vérifier les permissions.
 *
 * Cette garde est branchée globalement (voir app.module.ts) : elle s'applique
 * donc à TOUTES les routes, sauf celles marquées avec le décorateur @Public().
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly jwtStrategy: JwtStrategy,
    private readonly reflector: Reflector
  ) {}

  // canActivate renvoie true = requête autorisée à continuer ; sinon elle est bloquée.
  async canActivate(context: ExecutionContext): Promise<boolean> {
    // Route ouverte au public (login, refresh...) : on laisse passer sans token.
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass()
    ]);
    if (isPublic) {
      return true;
    }

    const request = context.switchToHttp().getRequest<AuthenticatedRequest & { headers: Record<string, string | undefined> }>();
    const payload = await this.jwtStrategy.validateAuthorizationHeader(request.headers.authorization);

    request.user = {
      id: payload.sub,
      roles: payload.roles,
      permissions: payload.permissions,
      sessionId: payload.sid
    };

    return true;
  }
}
