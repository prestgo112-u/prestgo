import { ConflictException, Injectable } from "@nestjs/common";
import { PrismaService } from "../prisma/prisma.service.js";

/** Durée pendant laquelle une clé rejouée renvoie le même résultat (§14.6). */
const IDEMPOTENCY_TTL_MINUTES = 10;

/**
 * Idempotence des créations (§14.6).
 *
 * Le problème concret : une application mobile envoie `POST /missions`, perd le
 * réseau avant la réponse, et réessaie. Sans garde-fou, le client se retrouve
 * avec deux missions identiques — et deux prestataires prévenus.
 *
 * Le fonctionnement retenu :
 *   1. on RÉSERVE la clé (insertion, protégée par une contrainte d'unicité) ;
 *   2. l'appelant fait son travail et enregistre l'identifiant produit ;
 *   3. un rejeu de la même clé retrouve la réservation et renvoie ce même
 *      identifiant, sans rien recréer.
 *
 * La contrainte d'unicité en base est ce qui tient face à deux requêtes
 * simultanées : une vérification en amont laisserait passer les deux.
 */
@Injectable()
export class IdempotencyService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Tente de réserver une clé.
   *
   * Renvoie `{ replay: true, resourceId }` si la clé a déjà servi. Un
   * `resourceId` encore nul signifie qu'un premier appel est EN COURS : on
   * répond 409 plutôt que de lancer un second traitement en parallèle.
   */
  async reserve(
    userId: string,
    endpoint: string,
    key: string
  ): Promise<{ replay: false } | { replay: true; resourceId: string }> {
    const now = new Date();

    const existing = await this.prisma.idempotencyRecord.findUnique({
      where: { userId_endpoint_key: { userId, endpoint, key } }
    });

    if (existing) {
      // Clé périmée : elle est réutilisable, comme une clé jamais vue.
      if (existing.expiresAt <= now) {
        await this.prisma.idempotencyRecord.delete({ where: { id: existing.id } });
      } else if (existing.resourceId) {
        return { replay: true, resourceId: existing.resourceId };
      } else {
        throw new ConflictException(
          "Une requête identique est déjà en cours de traitement. Réessayez dans quelques instants."
        );
      }
    }

    try {
      await this.prisma.idempotencyRecord.create({
        data: {
          userId,
          endpoint,
          key,
          expiresAt: new Date(now.getTime() + IDEMPOTENCY_TTL_MINUTES * 60_000)
        }
      });
    } catch {
      // Course entre deux requêtes simultanées : l'autre a gagné l'insertion.
      throw new ConflictException(
        "Une requête identique est déjà en cours de traitement. Réessayez dans quelques instants."
      );
    }

    return { replay: false };
  }

  /** Attache l'identifiant produit à la clé, pour que le rejeu le retrouve. */
  async complete(userId: string, endpoint: string, key: string, resourceId: string): Promise<void> {
    await this.prisma.idempotencyRecord.updateMany({
      where: { userId, endpoint, key },
      data: { resourceId }
    });
  }

  /**
   * Libère la clé après un échec.
   *
   * Indispensable : sans cela, une réservation refusée pour une raison
   * temporaire (créneau pris entre-temps) bloquerait la clé dix minutes, et le
   * client ne pourrait pas réessayer après correction.
   */
  async release(userId: string, endpoint: string, key: string): Promise<void> {
    await this.prisma.idempotencyRecord.deleteMany({ where: { userId, endpoint, key, resourceId: null } });
  }

  /** Purge des clés périmées (job d'entretien). */
  async purgeExpired(): Promise<number> {
    const result = await this.prisma.idempotencyRecord.deleteMany({ where: { expiresAt: { lt: new Date() } } });
    return result.count;
  }
}
