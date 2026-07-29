import { BadRequestException, ConflictException, Injectable, NotFoundException, UnauthorizedException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { verifyPassword } from "../../common/security/password.js";
import { AuditService } from "../audit/audit.service.js";
import { AccountService } from "../auth/account.service.js";
import { RefreshSessionService } from "../auth/refresh-session.service.js";

/**
 * Profil de l'utilisateur connecté (§3).
 *
 * Toutes les méthodes prennent l'identifiant issu du JETON, jamais de l'URL :
 * c'est ce qui garantit qu'on ne peut pas lire ou modifier le profil d'un
 * autre compte en changeant un identifiant.
 */
@Injectable()
export class MeService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly account: AccountService,
    private readonly sessions: RefreshSessionService
  ) {}

  /**
   * Profil complet.
   *
   * On renvoie l'EXISTENCE des profils client et prestataire, pas leur
   * contenu : c'est ce dont l'application mobile a besoin pour choisir quel
   * espace ouvrir au démarrage, sans un deuxième appel.
   */
  async profile(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        firstName: true,
        lastName: true,
        email: true,
        phone: true,
        status: true,
        emailVerifiedAt: true,
        phoneVerifiedAt: true,
        createdAt: true,
        clientProfile: { select: { id: true } },
        providerProfile: { select: { id: true, validationStatus: true } },
        roles: { select: { role: { select: { code: true } } } }
      }
    });

    if (!user) {
      throw new NotFoundException("Compte introuvable");
    }

    return {
      id: user.id,
      firstName: user.firstName,
      lastName: user.lastName,
      email: user.email,
      phone: user.phone,
      status: user.status,
      emailVerified: user.emailVerifiedAt !== null,
      phoneVerified: user.phoneVerifiedAt !== null,
      roles: user.roles.map((entry) => entry.role.code),
      hasClientProfile: user.clientProfile !== null,
      hasProviderProfile: user.providerProfile !== null,
      providerId: user.providerProfile?.id ?? null,
      providerValidationStatus: user.providerProfile?.validationStatus ?? null,
      createdAt: user.createdAt
    };
  }

  /**
   * Met à jour l'identité.
   *
   * Règle du §3 : changer son email ou son téléphone remet le champ en NON
   * VÉRIFIÉ et déclenche un nouveau code. Sans cela, il suffirait de modifier
   * son adresse après vérification pour se retrouver « vérifié » sur une
   * adresse dont on n'a jamais prouvé être propriétaire.
   */
  async updateProfile(
    userId: string,
    dto: { firstName?: string; lastName?: string; email?: string; phone?: string }
  ) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new NotFoundException("Compte introuvable");
    }

    const email = dto.email?.trim().toLowerCase();
    const phone = dto.phone?.trim();
    const emailChanged = email !== undefined && email !== user.email;
    const phoneChanged = phone !== undefined && phone !== user.phone;

    // Unicité vérifiée avant écriture, pour renvoyer un message clair plutôt
    // qu'une erreur de contrainte technique.
    if (emailChanged || phoneChanged) {
      const clash = await this.prisma.user.findFirst({
        where: {
          id: { not: userId },
          OR: [...(emailChanged ? [{ email }] : []), ...(phoneChanged ? [{ phone }] : [])]
        },
        select: { id: true }
      });
      if (clash) {
        throw new ConflictException("Cet email ou ce numéro est déjà utilisé");
      }
    }

    const updated = await this.prisma.user.update({
      where: { id: userId },
      data: {
        firstName: dto.firstName?.trim() ?? user.firstName,
        lastName: dto.lastName?.trim() ?? user.lastName,
        ...(emailChanged ? { email, emailVerifiedAt: null } : {}),
        ...(phoneChanged ? { phone, phoneVerifiedAt: null } : {})
      }
    });

    // Envoi du code de vérification sur le NOUVEAU destinataire.
    const verifications: { channel: string; target: string }[] = [];
    if (emailChanged && email) {
      await this.account.sendOtp(email, "email_verification");
      verifications.push({ channel: "email", target: email });
    }
    if (phoneChanged && phone) {
      await this.account.sendOtp(phone, "phone_verification");
      verifications.push({ channel: "sms", target: phone });
    }

    await this.audit.record({
      actorId: userId,
      action: "me.profile.update",
      entity: "User",
      entityId: userId,
      oldValue: { email: user.email, phone: user.phone, firstName: user.firstName, lastName: user.lastName },
      newValue: { email: updated.email, phone: updated.phone, firstName: updated.firstName, lastName: updated.lastName }
    });

    return { ...(await this.profile(userId)), pendingVerifications: verifications };
  }

  /** Changement de mot de passe : délégué au service de compte (§3). */
  async changePassword(userId: string, currentPassword: string, newPassword: string, keepSessionId?: string) {
    return this.account.changePassword(userId, currentPassword, newPassword, keepSessionId);
  }

  /**
   * Désactive son propre compte (§3).
   *
   * Rien n'est effacé : le statut passe à `deleted` (CDC §9.1) et les données
   * restent en base. C'est indispensable — les missions passées, les avis et
   * les factures d'AUTRES personnes référencent ce compte.
   *
   * Le refus en cas de mission en cours n'est pas une formalité : disparaître
   * alors qu'un prestataire s'est déplacé laisserait un engagement en l'air.
   */
  async deactivate(userId: string, password: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, passwordHash: true, status: true, providerProfile: { select: { id: true } } }
    });
    if (!user) {
      throw new NotFoundException("Compte introuvable");
    }
    if (!(await verifyPassword(password, user.passwordHash))) {
      throw new UnauthorizedException("Mot de passe incorrect");
    }
    if (user.status === "deleted") {
      throw new BadRequestException("Ce compte est déjà désactivé");
    }

    const blocking = await this.prisma.mission.count({
      where: {
        status: { in: ["confirmed", "in_progress"] },
        OR: [{ clientId: userId }, ...(user.providerProfile ? [{ providerId: user.providerProfile.id }] : [])]
      }
    });
    if (blocking > 0) {
      throw new BadRequestException(
        `Désactivation impossible : ${blocking} mission(s) confirmée(s) ou en cours. Terminez-les ou annulez-les d'abord.`
      );
    }

    await this.prisma.user.update({ where: { id: userId }, data: { status: "deleted" } });

    // Le compte ne doit plus pouvoir se reconnecter : toutes les sessions
    // tombent, et les jetons push sont désactivés pour ne plus rien recevoir.
    await this.sessions.revokeAllForUser(userId);
    await this.prisma.deviceToken.updateMany({ where: { userId }, data: { active: false } });

    await this.audit.record({
      actorId: userId,
      action: "me.account.deactivate",
      entity: "User",
      entityId: userId,
      oldValue: { status: user.status },
      newValue: { status: "deleted" }
    });

    return { status: "deleted" as const };
  }
}
