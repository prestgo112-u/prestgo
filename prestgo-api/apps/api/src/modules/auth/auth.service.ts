import { Injectable, Logger, UnauthorizedException } from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { hashPassword, needsRehash, verifyPassword } from "../../common/security/password.js";
import { AuditService } from "../audit/audit.service.js";
import { RefreshSessionService } from "./refresh-session.service.js";

export interface AuthTokenPayload {
  sub: string;
  roles: string[];
  permissions: string[];
  /**
   * Identifiant de la session de rafraîchissement dont ce jeton d'accès est
   * issu. C'est lui qui permet à `POST /me/password` de couper toutes les
   * sessions SAUF celle qui fait la demande (§3).
   */
  sid?: string;
}

export interface AuthTokenPair {
  accessToken: string;
  refreshToken: string;
}

export interface LoginDto {
  email: string;
  password: string;
}

export interface RefreshDto {
  refreshToken: string;
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly jwtService: JwtService,
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly sessions: RefreshSessionService
  ) {}

  async login(dto: LoginDto, userAgent?: string): Promise<AuthTokenPair> {
    const user = await this.prisma.user.findUnique({
      where: { email: dto.email },
      include: {
        roles: {
          include: {
            role: {
              include: {
                permissions: {
                  include: {
                    permission: true
                  }
                }
              }
            }
          }
        }
      }
    });

    if (!user) {
      throw new UnauthorizedException("Invalid credentials");
    }

    const passwordValid = await verifyPassword(dto.password, user.passwordHash);
    if (!passwordValid) {
      throw new UnauthorizedException("Invalid credentials");
    }

    if (user.status !== "active") {
      throw new UnauthorizedException("Account is not active");
    }

    // Ré-encodage silencieux : le compte a été créé avec des paramètres de coût
    // dépassés (§15.2). On profite d'avoir le mot de passe en clair, une seule
    // fois, pour remettre l'empreinte au niveau courant.
    if (needsRehash(user.passwordHash)) {
      try {
        await this.prisma.user.update({
          where: { id: user.id },
          data: { passwordHash: await hashPassword(dto.password) }
        });
      } catch (error) {
        // Un échec ici ne doit pas empêcher la connexion : l'empreinte
        // existante reste valable, elle sera reprise au prochain passage.
        this.logger.warn(`Ré-encodage du mot de passe impossible pour ${user.id} : ${String(error)}`);
      }
    }

    const roles = user.roles.map((ur: any) => ur.role.code);
    const permissions = user.roles.flatMap((ur: any) =>
      ur.role.permissions.map((rp: any) => rp.permission.code)
    );

    const session = await this.sessions.issue(user.id, userAgent);

    const payload: AuthTokenPayload = {
      sub: user.id,
      roles,
      permissions: [...new Set(permissions)] as string[],
      sid: session.sessionId
    };

    await this.audit.record({
      actorId: user.id,
      action: "auth.login",
      entity: "User",
      entityId: user.id
    });

    return { accessToken: this.jwtService.sign(payload), refreshToken: session.refreshToken };
  }

  /**
   * Renouvelle un jeton d'accès à partir d'un jeton de rafraîchissement.
   *
   * Les droits sont RELUS en base à chaque passage. C'est essentiel : un compte
   * suspendu ou un rôle retiré doit produire son effet au bout de quinze
   * minutes au plus, pas au bout de sept jours. Recopier les permissions du
   * jeton précédent — ce que faisait la version JWT — les figeait.
   */
  async refresh(dto: RefreshDto, userAgent?: string): Promise<AuthTokenPair> {
    const session = await this.sessions.verify(dto.refreshToken);

    const user = await this.prisma.user.findUnique({
      where: { id: session.userId },
      include: { roles: { include: { role: { include: { permissions: { include: { permission: true } } } } } } }
    });

    if (!user || user.status !== "active") {
      // Le compte n'est plus utilisable : on ferme la session au passage.
      await this.sessions.revoke(session.id);
      throw new UnauthorizedException("Session expirée ou invalide");
    }

    const rotated = await this.sessions.rotate(session.id, user.id, userAgent);

    const payload: AuthTokenPayload = {
      sub: user.id,
      roles: user.roles.map((ur: any) => ur.role.code),
      permissions: [
        ...new Set(user.roles.flatMap((ur: any) => ur.role.permissions.map((rp: any) => rp.permission.code)))
      ] as string[],
      sid: rotated.sessionId
    };

    return { accessToken: this.jwtService.sign(payload), refreshToken: rotated.refreshToken };
  }

  /**
   * Déconnexion : la session de rafraîchissement est réellement fermée.
   *
   * Le jeton d'accès, lui, reste valable jusqu'à son expiration (quinze
   * minutes) — c'est le compromis assumé d'un JWT court. Ce qui change depuis
   * le Lot 6, c'est qu'aucun NOUVEAU jeton ne pourra être obtenu.
   */
  async logout(authorization?: string, refreshToken?: string): Promise<void> {
    if (refreshToken) {
      await this.sessions.revokeByToken(refreshToken);
    }

    const [scheme, token] = authorization?.split(" ") ?? [];
    if (scheme === "Bearer" && token) {
      try {
        const payload = await this.verifyAccessToken(token);
        // Sans refresh token fourni, on se rabat sur la session portée par le
        // jeton d'accès : la déconnexion reste effective.
        if (!refreshToken && payload.sid) {
          await this.sessions.revoke(payload.sid);
        }
        await this.audit.record({ actorId: payload.sub, action: "auth.logout", entity: "User", entityId: payload.sub });
      } catch {
        // Token invalide : on ignore, la déconnexion réussit quand même (idempotent).
      }
    }
  }

  /**
   * Émet un couple de jetons pour un utilisateur déjà authentifié autrement.
   *
   * Utilisé après un changement de mot de passe : l'appelant conserve une
   * session valide alors que toutes les autres viennent d'être coupées.
   */
  async issueTokensFor(userId: string, userAgent?: string): Promise<AuthTokenPair & { sessionId: string }> {
    const user = await this.prisma.user.findUniqueOrThrow({
      where: { id: userId },
      include: { roles: { include: { role: { include: { permissions: { include: { permission: true } } } } } } }
    });

    const session = await this.sessions.issue(user.id, userAgent);
    const payload: AuthTokenPayload = {
      sub: user.id,
      roles: user.roles.map((ur: any) => ur.role.code),
      permissions: [
        ...new Set(user.roles.flatMap((ur: any) => ur.role.permissions.map((rp: any) => rp.permission.code)))
      ] as string[],
      sid: session.sessionId
    };

    return {
      accessToken: this.jwtService.sign(payload),
      refreshToken: session.refreshToken,
      sessionId: session.sessionId
    };
  }

  async verifyAccessToken(token: string): Promise<AuthTokenPayload> {
    try {
      return await this.jwtService.verifyAsync<AuthTokenPayload>(token);
    } catch {
      throw new UnauthorizedException("Invalid access token");
    }
  }
}
