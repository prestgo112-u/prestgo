import { Injectable, UnauthorizedException } from "@nestjs/common";
import { createHash, randomBytes } from "node:crypto";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { currentRequestContext } from "../../common/middleware/request-context.js";

// Durée de vie d'une session de rafraîchissement.
const REFRESH_TTL_DAYS = 7;

/**
 * Empreinte du jeton de rafraîchissement.
 *
 * Même raisonnement que pour les jetons de réinitialisation : le secret est
 * aléatoire et de courte durée, un SHA-256 suffit et reste rapide — ce qui
 * compte, puisque cette fonction tourne à chaque renouvellement de jeton.
 */
function fingerprint(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export interface IssuedSession {
  sessionId: string;
  refreshToken: string;
}

/**
 * Gère les sessions de rafraîchissement.
 *
 * Avant le Lot 6, le refresh token était un JWT autoportant : rien, côté
 * serveur, ne permettait de l'annuler. Concrètement, changer son mot de passe
 * après un vol de téléphone ne coupait RIEN — le voleur gardait un accès
 * valable une semaine. Le §3 exige l'inverse : « révoque tous les refresh
 * tokens sauf la session courante ».
 *
 * Le jeton est désormais une valeur aléatoire opaque, dont seule l'empreinte
 * est stockée. Une session peut donc être révoquée, listée, et elle expire
 * réellement.
 */
@Injectable()
export class RefreshSessionService {
  constructor(private readonly prisma: PrismaService) {}

  /** Ouvre une session et renvoie le jeton en clair (seul moment où il existe). */
  async issue(userId: string, userAgent?: string): Promise<IssuedSession> {
    const token = randomBytes(48).toString("hex");
    const context = currentRequestContext();

    const session = await this.prisma.refreshSession.create({
      data: {
        userId,
        tokenHash: fingerprint(token),
        userAgent: userAgent?.slice(0, 255),
        ip: context?.ip,
        expiresAt: new Date(Date.now() + REFRESH_TTL_DAYS * 24 * 60 * 60_000)
      },
      select: { id: true }
    });

    return { sessionId: session.id, refreshToken: token };
  }

  /**
   * Vérifie un jeton de rafraîchissement et renvoie la session correspondante.
   *
   * Un jeton révoqué ou expiré est traité exactement comme un jeton inconnu :
   * l'appelant n'apprend pas si le jeton a existé.
   */
  async verify(token: string): Promise<{ id: string; userId: string }> {
    const session = await this.prisma.refreshSession.findUnique({
      where: { tokenHash: fingerprint(token) },
      select: { id: true, userId: true, revokedAt: true, expiresAt: true }
    });

    if (!session || session.revokedAt || session.expiresAt < new Date()) {
      throw new UnauthorizedException("Session expirée ou invalide");
    }

    return { id: session.id, userId: session.userId };
  }

  /**
   * Fait tourner le jeton : l'ancien est révoqué, un nouveau est émis.
   *
   * La rotation limite les dégâts d'un jeton intercepté : il ne sert qu'une
   * fois, et le vrai propriétaire s'en aperçoit à la déconnexion suivante.
   */
  async rotate(sessionId: string, userId: string, userAgent?: string): Promise<IssuedSession> {
    await this.prisma.refreshSession.update({
      where: { id: sessionId },
      data: { revokedAt: new Date(), lastUsedAt: new Date() }
    });
    return this.issue(userId, userAgent);
  }

  /** Ferme une session précise (déconnexion). */
  async revoke(sessionId: string): Promise<void> {
    await this.prisma.refreshSession.updateMany({
      where: { id: sessionId, revokedAt: null },
      data: { revokedAt: new Date() }
    });
  }

  async revokeByToken(token: string): Promise<void> {
    await this.prisma.refreshSession.updateMany({
      where: { tokenHash: fingerprint(token), revokedAt: null },
      data: { revokedAt: new Date() }
    });
  }

  /**
   * Révoque toutes les sessions d'un compte, sauf éventuellement une.
   *
   * C'est l'effet attendu d'un changement de mot de passe (§3) : les autres
   * appareils sont déconnectés, celui qui vient de faire la manipulation reste
   * connecté — sinon on punirait l'utilisateur d'avoir fait le bon geste.
   *
   * Renvoie le nombre de sessions effectivement coupées, pour le journal.
   */
  async revokeAllForUser(userId: string, exceptSessionId?: string): Promise<number> {
    const result = await this.prisma.refreshSession.updateMany({
      where: {
        userId,
        revokedAt: null,
        ...(exceptSessionId ? { id: { not: exceptSessionId } } : {})
      },
      data: { revokedAt: new Date() }
    });
    return result.count;
  }

  /** Purge les sessions expirées depuis longtemps (job d'entretien). */
  async purgeExpired(olderThanDays = 30): Promise<number> {
    const threshold = new Date(Date.now() - olderThanDays * 24 * 60 * 60_000);
    const result = await this.prisma.refreshSession.deleteMany({
      where: { expiresAt: { lt: threshold } }
    });
    return result.count;
  }
}
