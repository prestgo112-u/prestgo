import { ExecutionContext, HttpException, HttpStatus, Injectable } from "@nestjs/common";
import { ThrottlerGuard, type ThrottlerLimitDetail } from "@nestjs/throttler";

/**
 * Même comportement que le limiteur standard, mais avec un message lisible.
 *
 * Par défaut la librairie renvoie « ThrottlerException: Too Many Requests »,
 * ce qui n'aide pas l'utilisateur. Le CDC (§10) demande des messages d'erreur
 * explicites : on renvoie donc une phrase en français.
 */
@Injectable()
export class FriendlyThrottlerGuard extends ThrottlerGuard {
  protected async throwThrottlingException(_context: ExecutionContext, _detail: ThrottlerLimitDetail): Promise<void> {
    throw new HttpException(
      "Trop de tentatives en peu de temps. Merci de réessayer dans une minute.",
      HttpStatus.TOO_MANY_REQUESTS
    );
  }
}
