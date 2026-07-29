import { BadRequestException, ConflictException, Injectable, Logger, UnauthorizedException } from "@nestjs/common";
import { createHash, randomBytes, randomInt } from "node:crypto";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { hashPassword, verifyPassword } from "../../common/security/password.js";
import { AuditService } from "../audit/audit.service.js";
import { RefreshSessionService } from "./refresh-session.service.js";
import { DirectMessageService } from "../notifications/direct-message.service.js";

// Durées de vie des secrets temporaires.
const RESET_TOKEN_TTL_MINUTES = 30;
const OTP_TTL_MINUTES = 10;
const OTP_MAX_ATTEMPTS = 5;

/**
 * Empreinte d'un secret court (jeton de réinitialisation, code OTP).
 *
 * Pourquoi SHA-256 et pas scrypt comme pour les mots de passe : ces secrets
 * sont aléatoires et de courte durée de vie, il n'y a pas de dictionnaire à
 * craindre. Un hachage lent serait ici inutilement coûteux — et il tournerait
 * à chaque tentative, ce qui ouvrirait un angle de déni de service.
 */
function fingerprint(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

/**
 * En développement, aucun email ni SMS n'est réellement envoyé (le transport
 * arrive au Lot 5). Le code doit donc être récupérable autrement, sinon la
 * fonctionnalité est intestable.
 *
 * On le renvoie dans la réponse UNIQUEMENT si `AUTH_EXPOSE_DEV_CODES=true`.
 * Sans ce réglage explicite — donc en production — le secret n'apparaît jamais
 * dans une réponse HTTP ; il n'est visible que dans les logs du serveur.
 */
function exposeDevSecrets(): boolean {
  return process.env.AUTH_EXPOSE_DEV_CODES === "true";
}

export interface RegisterInput {
  email?: string;
  phone?: string;
  password: string;
  firstName?: string;
  lastName?: string;
}

@Injectable()
export class AccountService {
  private readonly logger = new Logger(AccountService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly sessions: RefreshSessionService,
    private readonly messages: DirectMessageService
  ) {}

  /**
   * Crée un compte utilisateur.
   *
   * Le compte naît au statut `pending` : il existe, mais ne pourra pas se
   * connecter tant qu'il n'est pas activé (vérification du téléphone ou de
   * l'email). C'est la règle du CDC §9.1.
   */
  async register(input: RegisterInput) {
    const email = input.email?.trim().toLowerCase();
    const phone = input.phone?.trim();

    if (!email && !phone) {
      throw new BadRequestException("Un email ou un numéro de téléphone est obligatoire");
    }

    // On vérifie l'unicité avant d'insérer, pour renvoyer un message clair
    // plutôt qu'une erreur de contrainte technique.
    const existing = await this.prisma.user.findFirst({
      where: { OR: [...(email ? [{ email }] : []), ...(phone ? [{ phone }] : [])] }
    });
    if (existing) {
      throw new ConflictException("Un compte existe déjà avec cet email ou ce numéro");
    }

    const user = await this.prisma.user.create({
      data: {
        email,
        phone,
        firstName: input.firstName?.trim(),
        lastName: input.lastName?.trim(),
        passwordHash: await hashPassword(input.password),
        status: "pending",
        // Écart n°1 du cahier des charges mobile : `GET /me` expose
        // `hasClientProfile`, mais aucune route mobile ne créait cette ligne —
        // le flag restait `false` pour tout compte, y compris un client actif
        // de longue date. Un compte naît « client » par défaut ; devenir
        // prestataire (POST /providers/me) ajoute une CAPACITÉ
        // supplémentaire, elle ne remplace jamais celle-ci.
        //
        // Créé dans la même écriture que le compte : ainsi il n'existe aucun
        // instant où un utilisateur existe sans son profil client.
        clientProfile: { create: {} }
      }
    });

    await this.audit.record({
      actorId: user.id,
      action: "auth.register",
      entity: "User",
      entityId: user.id,
      newValue: { email, phone }
    });

    // On ne renvoie jamais l'empreinte du mot de passe.
    return {
      id: user.id,
      email: user.email,
      phone: user.phone,
      status: user.status,
      createdAt: user.createdAt
    };
  }

  /**
   * Demande de réinitialisation du mot de passe.
   *
   * Règle de sécurité importante : la réponse est TOUJOURS la même, que le
   * compte existe ou non. Sinon cette route deviendrait un moyen de découvrir
   * quelles adresses sont inscrites sur la plateforme (CDC §5.2).
   */
  async forgotPassword(email: string) {
    const user = await this.prisma.user.findUnique({ where: { email: email.trim().toLowerCase() } });

    let devToken: string | undefined;
    if (user) {
      const token = randomBytes(32).toString("hex");
      const expiresAt = new Date(Date.now() + RESET_TOKEN_TTL_MINUTES * 60_000);

      // Les demandes précédentes encore valides sont annulées : un seul jeton
      // actif à la fois évite qu'un ancien email serve à reprendre la main.
      await this.prisma.passwordResetToken.updateMany({
        where: { userId: user.id, usedAt: null },
        data: { usedAt: new Date() }
      });

      await this.prisma.passwordResetToken.create({
        data: { userId: user.id, tokenHash: fingerprint(token), expiresAt }
      });

      this.logger.log(`Jeton de réinitialisation généré pour ${user.id} (valable ${RESET_TOKEN_TTL_MINUTES} min)`);

      if (user.email) {
        await this.messages.sendEmail(
          user.email,
          "Réinitialisation de votre mot de passe PRESTGO",
          `Utilisez ce code pour réinitialiser votre mot de passe : ${token}\n` +
            `Il est valable ${RESET_TOKEN_TTL_MINUTES} minutes. Si vous n'êtes pas à l'origine de cette demande, ignorez ce message.`
        );
      }

      if (exposeDevSecrets()) {
        devToken = token;
      }
    }

    return {
      message: "Si un compte existe pour cette adresse, un lien de réinitialisation a été envoyé.",
      ...(devToken ? { devToken } : {})
    };
  }

  // Consomme un jeton de réinitialisation et remplace le mot de passe.
  async resetPassword(token: string, newPassword: string) {
    const record = await this.prisma.passwordResetToken.findUnique({
      where: { tokenHash: fingerprint(token) }
    });

    // Un seul message pour tous les cas d'échec : ne rien apprendre à l'attaquant.
    if (!record || record.usedAt || record.expiresAt < new Date()) {
      throw new BadRequestException("Lien de réinitialisation invalide ou expiré");
    }

    await this.prisma.$transaction([
      this.prisma.user.update({
        where: { id: record.userId },
        data: { passwordHash: await hashPassword(newPassword) }
      }),
      // Marqué comme utilisé : un lien ne sert qu'une fois.
      this.prisma.passwordResetToken.update({
        where: { id: record.id },
        data: { usedAt: new Date() }
      })
    ]);

    // Une réinitialisation fait suite, la plupart du temps, à un mot de passe
    // oublié… ou compromis. Toutes les sessions ouvertes tombent, sans
    // exception : contrairement au changement volontaire (§3), l'appareil qui
    // fait la demande n'est pas nécessairement celui de l'utilisateur légitime.
    const revoked = await this.sessions.revokeAllForUser(record.userId);

    await this.audit.record({
      actorId: record.userId,
      action: "auth.password.reset",
      entity: "User",
      entityId: record.userId,
      newValue: { revokedSessions: revoked }
    });

    return { message: "Mot de passe mis à jour." };
  }

  /**
   * Changement de mot de passe par l'utilisateur connecté (§3).
   *
   * L'ancien mot de passe est exigé : sans lui, un jeton d'accès volé
   * suffirait à s'approprier définitivement le compte.
   */
  async changePassword(userId: string, currentPassword: string, newPassword: string, keepSessionId?: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { id: true, passwordHash: true }
    });
    if (!user) {
      throw new BadRequestException("Compte introuvable");
    }

    if (!(await verifyPassword(currentPassword, user.passwordHash))) {
      throw new UnauthorizedException("Mot de passe actuel incorrect");
    }

    if (currentPassword === newPassword) {
      throw new BadRequestException("Le nouveau mot de passe doit être différent de l'ancien");
    }

    await this.prisma.user.update({
      where: { id: userId },
      data: { passwordHash: await hashPassword(newPassword) }
    });

    // Toutes les autres sessions tombent, la session courante survit : c'est
    // exactement ce qu'on attend quand on change son mot de passe après avoir
    // perdu un téléphone.
    const revokedSessions = await this.sessions.revokeAllForUser(userId, keepSessionId);

    await this.audit.record({
      actorId: userId,
      action: "me.password.change",
      entity: "User",
      entityId: userId,
      newValue: { revokedSessions }
    });

    return { revokedSessions };
  }

  /**
   * Génère et « envoie » un code à usage unique.
   *
   * Comme pour l'oubli de mot de passe, la réponse ne dit pas si le
   * destinataire correspond à un compte connu.
   */
  async sendOtp(target: string, purpose: string) {
    const normalized = target.trim();
    const code = String(randomInt(0, 1_000_000)).padStart(6, "0");
    const expiresAt = new Date(Date.now() + OTP_TTL_MINUTES * 60_000);

    // On invalide les codes précédents : un seul code actif à la fois.
    await this.prisma.otpCode.updateMany({
      where: { target: normalized, purpose, usedAt: null },
      data: { usedAt: new Date() }
    });

    await this.prisma.otpCode.create({
      data: { target: normalized, purpose, codeHash: fingerprint(code), expiresAt }
    });

    // Envoi RÉEL (§16.2) : SMS si le destinataire est un numéro, email sinon.
    // Tant qu'aucun agrégateur n'est configuré, le transport de repli écrit le
    // message dans la boîte d'envoi — il reste donc récupérable, sans jamais
    // laisser croire qu'un SMS est parti.
    const isPhone = /^\+?[0-9\s-]{8,20}$/.test(normalized);
    const title = "Code de vérification PRESTGO";
    const body = `Votre code est ${code}. Il expire dans ${OTP_TTL_MINUTES} minutes. Ne le communiquez à personne.`;

    const delivered = isPhone
      ? await this.messages.sendSms(normalized, title, body)
      : await this.messages.sendEmail(normalized, title, body);

    if (!delivered) {
      // On ne remonte pas l'échec à l'appelant : la réponse doit rester
      // identique quel que soit le destinataire, sinon cette route dirait qui
      // est joignable et qui ne l'est pas.
      this.logger.warn(`Acheminement du code OTP en échec pour ${normalized} (${purpose})`);
    }

    return {
      message: "Un code de vérification a été envoyé.",
      expiresInMinutes: OTP_TTL_MINUTES,
      ...(exposeDevSecrets() ? { devCode: code } : {})
    };
  }

  /**
   * Vérifie un code OTP.
   *
   * Si le code correspond à un compte au statut `pending`, celui-ci devient
   * `active` : c'est le parcours normal d'activation après inscription.
   */
  async verifyOtp(target: string, code: string, purpose: string) {
    const normalized = target.trim();
    const record = await this.prisma.otpCode.findFirst({
      where: { target: normalized, purpose, usedAt: null },
      orderBy: { createdAt: "desc" }
    });

    if (!record || record.expiresAt < new Date()) {
      throw new BadRequestException("Code invalide ou expiré");
    }

    // Sans ce compteur, un code à 6 chiffres se devine en un million d'essais.
    if (record.attempts >= OTP_MAX_ATTEMPTS) {
      throw new UnauthorizedException("Trop de tentatives. Demandez un nouveau code.");
    }

    if (record.codeHash !== fingerprint(code)) {
      await this.prisma.otpCode.update({
        where: { id: record.id },
        data: { attempts: record.attempts + 1 }
      });
      throw new BadRequestException("Code invalide ou expiré");
    }

    await this.prisma.otpCode.update({ where: { id: record.id }, data: { usedAt: new Date() } });

    // Activation du compte correspondant, s'il en existe un en attente.
    const user = await this.prisma.user.findFirst({
      where: { OR: [{ phone: normalized }, { email: normalized.toLowerCase() }] }
    });

    let activated = false;
    if (user) {
      const verifiedField = user.phone === normalized ? "phoneVerifiedAt" : "emailVerifiedAt";
      await this.prisma.user.update({
        where: { id: user.id },
        data: {
          [verifiedField]: new Date(),
          // On n'active que depuis `pending` : un compte suspendu ne doit pas
          // pouvoir se réactiver tout seul en vérifiant son téléphone.
          ...(user.status === "pending" ? { status: "active" as const } : {})
        }
      });
      activated = user.status === "pending";

      await this.audit.record({
        actorId: user.id,
        action: "auth.otp.verify",
        entity: "User",
        entityId: user.id,
        newValue: { purpose, activated }
      });
    }

    return { verified: true, activated };
  }
}
