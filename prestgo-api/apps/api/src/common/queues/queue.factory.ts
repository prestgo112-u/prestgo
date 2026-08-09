import { Logger } from "@nestjs/common";
import { BullMqQueue } from "./bullmq-queue.js";
import { InMemoryQueue, type JobHandler, type JobQueue } from "./job-queue.js";

export type QueueDriver = "bullmq" | "memory" | "inline";

export interface CreateQueueOptions {
  maxAttempts?: number;
  intervalMs?: number;
  concurrency?: number;
}

/**
 * Choisit le driver de file d'attente.
 *
 *   - `bullmq` : file persistante sur Redis. C'est le mode de production
 *     (§15.3) : ce qui est en attente survit à un redémarrage.
 *   - `memory` : file en mémoire avec minuteur. Repli de développement quand
 *     Redis n'est pas installé.
 *   - `inline` : traitement immédiat, sans attente. Réservé aux tests.
 *
 * Par défaut on prend `bullmq` dès qu'une `REDIS_URL` est configurée : c'est le
 * bon comportement en production, et le développement sans Redis retombe
 * automatiquement en mémoire.
 */
export function resolveQueueDriver(): QueueDriver {
  const explicit = process.env.QUEUE_DRIVER?.trim().toLowerCase();
  if (explicit === "bullmq" || explicit === "memory" || explicit === "inline") {
    return explicit;
  }
  return process.env.REDIS_URL ? "bullmq" : "memory";
}

export function createQueue<T>(name: string, handler: JobHandler<T>, options: CreateQueueOptions = {}): JobQueue<T> {
  const driver = resolveQueueDriver();
  const logger = new Logger("QueueFactory");

  if (driver === "bullmq") {
    try {
      return new BullMqQueue<T>(name, handler, {
        redisUrl: process.env.REDIS_URL ?? "redis://localhost:6379",
        maxAttempts: options.maxAttempts,
        concurrency: options.concurrency
      });
    } catch (error) {
      // Redis injoignable au démarrage : mieux vaut une file dégradée qu'une
      // API qui refuse de démarrer. L'avertissement doit rester visible.
      logger.error(
        `File « ${name} » : bascule en mémoire, Redis indisponible (${error instanceof Error ? error.message : String(error)})`
      );
    }
  }

  return new InMemoryQueue<T>(name, handler, {
    immediate: driver === "inline",
    intervalMs: options.intervalMs ?? 5_000,
    maxAttempts: options.maxAttempts ?? 3
  });
}
