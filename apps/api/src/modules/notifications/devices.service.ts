import { Injectable, Logger } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";

export const DEVICE_PLATFORMS = ["android", "ios", "web"] as const;
export type DevicePlatform = (typeof DEVICE_PLATFORMS)[number];

/**
 * Jetons d'appareil pour les notifications push (§12).
 *
 * Le point délicat est la RÉAFFECTATION : un jeton FCM/APNs identifie une
 * installation, pas un compte. Sur un téléphone prêté ou revendu, le même
 * jeton peut se présenter avec un autre compte. S'il restait attaché à
 * l'ancien propriétaire, celui-ci recevrait les notifications du nouveau — une
 * fuite de données bien réelle. D'où la contrainte d'unicité sur `token` et
 * l'écrasement du `userId` à chaque enregistrement.
 */
@Injectable()
export class DevicesService {
  private readonly logger = new Logger(DevicesService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  async list(userId: string) {
    return this.prisma.deviceToken.findMany({
      where: { userId, active: true },
      orderBy: { lastSeenAt: "desc" },
      // Le jeton lui-même n'est pas renvoyé : c'est un secret d'envoi, pas une
      // information utile à l'application.
      select: { id: true, platform: true, active: true, lastSeenAt: true, createdAt: true }
    });
  }

  /** Enregistrement idempotent : réappeler avec le même jeton met simplement à jour. */
  async register(userId: string, platform: DevicePlatform, token: string) {
    const device = await this.prisma.deviceToken.upsert({
      where: { token },
      update: { userId, platform, active: true, lastSeenAt: new Date() },
      create: { userId, platform, token },
      select: { id: true, platform: true, active: true, lastSeenAt: true }
    });

    await this.audit.record({
      actorId: userId,
      action: "me.devices.register",
      entity: "DeviceToken",
      entityId: device.id,
      newValue: { platform }
    });

    return device;
  }

  async unregister(userId: string, token: string) {
    // On filtre sur le propriétaire : sans ça, connaître le jeton d'un autre
    // appareil suffirait à le faire taire.
    const result = await this.prisma.deviceToken.updateMany({
      where: { token, userId },
      data: { active: false }
    });

    await this.audit.record({
      actorId: userId,
      action: "me.devices.unregister",
      entity: "DeviceToken",
      newValue: { removed: result.count }
    });

    return { unregistered: result.count > 0 };
  }

  /**
   * Désactive un jeton refusé par FCM/APNs.
   *
   * Appelé par le transport push quand le fournisseur répond « jeton inconnu ».
   * Continuer à pousser vers un jeton mort fait grimper le taux d'échec, ce que
   * les fournisseurs sanctionnent.
   */
  async deactivateToken(token: string, reason: string): Promise<void> {
    const result = await this.prisma.deviceToken.updateMany({
      where: { token, active: true },
      data: { active: false }
    });
    if (result.count > 0) {
      this.logger.log(`Jeton push désactivé (${reason})`);
    }
  }

  /** Jetons actifs d'un utilisateur, pour l'envoi. */
  async activeTokensFor(userId: string): Promise<{ token: string; platform: string }[]> {
    return this.prisma.deviceToken.findMany({
      where: { userId, active: true },
      select: { token: true, platform: true }
    });
  }

  /**
   * Nettoyage hebdomadaire : désactive les jetons inactifs depuis 90 jours (§14).
   *
   * Une application désinstallée ne se désenregistre pas. Sans purge, la table
   * grossit indéfiniment et chaque envoi paie le coût de jetons morts.
   */
  async deactivateStale(days = 90): Promise<number> {
    const threshold = new Date(Date.now() - days * 24 * 60 * 60_000);
    const result = await this.prisma.deviceToken.updateMany({
      where: { active: true, lastSeenAt: { lt: threshold } },
      data: { active: false }
    });
    return result.count;
  }
}
