import { Injectable, UnauthorizedException } from "@nestjs/common";
import { AuthService, type AuthTokenPayload } from "./auth.service.js";

@Injectable()
export class JwtStrategy {
  constructor(private readonly authService: AuthService) {}

  async validateAuthorizationHeader(header: string | undefined): Promise<AuthTokenPayload> {
    const [scheme, token] = header?.split(" ") ?? [];

    if (scheme !== "Bearer" || !token) {
      throw new UnauthorizedException("Bearer token required");
    }

    return this.authService.verifyAccessToken(token);
  }
}
