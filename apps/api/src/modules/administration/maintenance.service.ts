import { Injectable, Logger, type OnModuleInit } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { NotificationDispatcher } from "../notifications/notification-dispatcher.service.js";

const ONE_HOUR_MS = 3_600_000;

/**
 * Tâches d'entretien périodiques.
 *
 * Deux besoins jusqu'ici non couverts :
 *
 *  1. **Purger les secrets expirés.** Les jetons de réinitialisation et les
 *     codes OTP s'accumulaient sans que rien ne les supprime. Même hachés,
 *     garder indéfiniment des secrets périmés n'a aucun intérêt et grossit la
 *     base pour rien.
 *
 *  2. **Reprendre les notifications en attente.** La file vivant en mémoire,
 *     un redémarrage de l'API laisserait pour toujours en `queued` ce qui
 *     n'avait pas encore été traité.
 */
@Injectable()
export class MaintenanceService implements OnModuleInit {
  private readonly logger = new Logger(MaintenanceService.name);
  private timer: NodeJS.Timeout | null = null;

  constructor(
    private readonly prisma: PrismaService,
    private readonly dispatcher: NotificationDispatcher
  ) {}

  async onModuleInit(): Promise<void> {
    // En test, on ne veut aucune tâche de fond : elle rendrait les résultats
    // imprévisibles selon le moment où le minuteur se déclenche.
    if (process.env.QUEUE_DRIVER === "inline") {
      return;
    }

    await this.runOnce();

    this.timer = setInterval(() => {
      void this.runOnce();
    }, ONE_HOUR_MS);
    // `unref` : cette tâche ne doit pas empêcher le processus de s'arrêter.
    this.timer.unref();
  }

  async runOnce(): Promise<{ tokens: number; codes: number; requeued: number }> {
    const now = new Date();

    const [tokens, codes] = await Promise.all([
      this.prisma.passwordResetToken.deleteMany({
        // Expirés, ou déjà utilisés : dans les deux cas ils ne servent plus.
        where: { OR: [{ expiresAt: { lt: now } }, { usedAt: { not: null } }] }
      }),
      this.prisma.otpCode.deleteMany({
        where: { OR: [{ expiresAt: { lt: now } }, { usedAt: { not: null } }] }
      })
    ]);

    const requeued = await this.dispatcher.requeuePending();

    if (tokens.count || codes.count || requeued) {
      this.logger.log(
        `Entretien : ${tokens.count} jeton(s) et ${codes.count} code(s) purgés, ${requeued} notification(s) reprise(s)`
      );
    }

    return { tokens: tokens.count, codes: codes.count, requeued };
  }
}
