import { Logger } from "@nestjs/common";
import { Queue, Worker, type ConnectionOptions, type JobsOptions } from "bullmq";
import type { JobHandler, JobQueue } from "./job-queue.js";

/**
 * Traduit `redis://user:pass@hote:port/base` en options de connexion.
 *
 * On ne construit pas nous-mêmes le client ioredis : BullMQ le fait, avec les
 * réglages qu'il exige (notamment `maxRetriesPerRequest: null`, sans quoi le
 * worker abandonne ses commandes bloquantes). Lui passer des options plutôt
 * qu'une instance évite aussi d'imposer une version précise d'ioredis.
 */
export function parseRedisUrl(url: string): ConnectionOptions {
  try {
    const parsed = new URL(url);
    const database = parsed.pathname.replace("/", "");
    return {
      host: parsed.hostname || "localhost",
      port: parsed.port ? Number(parsed.port) : 6379,
      ...(parsed.username ? { username: decodeURIComponent(parsed.username) } : {}),
      ...(parsed.password ? { password: decodeURIComponent(parsed.password) } : {}),
      ...(database ? { db: Number(database) } : {}),
      ...(parsed.protocol === "rediss:" ? { tls: {} } : {})
    };
  } catch {
    // URL illisible : on retombe sur l'instance locale plutôt que de planter au
    // démarrage. L'échec de connexion sera visible dans les logs de la file.
    return { host: "localhost", port: 6379 };
  }
}

/**
 * File d'attente PERSISTANTE, adossée à Redis via BullMQ (§15.3).
 *
 * Différence essentielle avec `InMemoryQueue` : ce qui est mis en file survit
 * au redémarrage de l'API. Tant que les notifications étaient le seul usage,
 * la file en mémoire suffisait à peu près ; avec les notifications push et les
 * jobs planifiés du §14, perdre la file à chaque déploiement n'est plus
 * acceptable — une mission jamais expirée resterait bloquée pour toujours.
 *
 * Le code appelant ne voit que l'interface `JobQueue` : basculer d'un driver à
 * l'autre se fait par la variable `QUEUE_DRIVER`, sans toucher aux services.
 */
export class BullMqQueue<T> implements JobQueue<T> {
  private readonly logger: Logger;
  // `any` sur le paramètre de nom : BullMQ dérive le type du nom de tâche à
  // partir du type de données, ce qui empêche d'écrire une file générique.
  private readonly queue: Queue<any, any, any>;
  private readonly worker: Worker<any, any, any>;

  constructor(
    private readonly name: string,
    handler: JobHandler<T>,
    options: { redisUrl: string; maxAttempts?: number; concurrency?: number }
  ) {
    this.logger = new Logger(`Queue:${name}`);
    const connection = parseRedisUrl(options.redisUrl);

    this.queue = new Queue<any, any, any>(name, {
      connection,
      defaultJobOptions: {
        attempts: options.maxAttempts ?? 3,
        // Attente croissante entre deux tentatives : réessayer aussitôt
        // n'aiderait pas si le fournisseur en face est momentanément indisponible.
        backoff: { type: "exponential", delay: 2_000 },
        removeOnComplete: 1_000,
        removeOnFail: 5_000
      }
    });

    this.worker = new Worker<any, any, any>(name, async (job) => handler(job.data), {
      connection,
      concurrency: options.concurrency ?? 5
    });

    this.worker.on("failed", (job, error) => {
      this.logger.warn(`Tâche ${job?.id ?? "?"} en échec (${job?.attemptsMade ?? 0} tentatives) : ${error.message}`);
    });

    // Une erreur de connexion non écoutée ferait tomber le processus.
    this.worker.on("error", (error) => {
      this.logger.error(`File « ${name} » : ${error.message}`);
    });
    this.queue.on("error", (error) => {
      this.logger.error(`File « ${name} » : ${error.message}`);
    });
  }

  async add(data: T, options?: JobsOptions): Promise<void> {
    await this.queue.add(this.name, data, options);
  }

  /**
   * Programme une tâche répétée (jobs planifiés du §14).
   *
   * `jobId` fixe l'identité de la répétition : redémarrer l'API ne crée pas une
   * deuxième planification du même job.
   */
  async schedule(data: T, pattern: string, key: string): Promise<void> {
    await this.queue.add(key, data, {
      repeat: { pattern },
      jobId: `repeat:${key}`
    });
    this.logger.log(`Tâche répétée « ${key} » programmée (${pattern})`);
  }

  /**
   * Avec BullMQ, le worker traite en continu : il n'y a rien à « vider ».
   * La méthode existe pour respecter l'interface commune.
   */
  async drain(): Promise<void> {
    // Rien à faire : le worker BullMQ consomme la file en permanence.
  }

  async close(): Promise<void> {
    await this.worker.close();
    await this.queue.close();
  }
}
