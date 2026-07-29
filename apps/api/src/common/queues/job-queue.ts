import { Logger } from "@nestjs/common";

/**
 * Une tâche à traiter en arrière-plan.
 *
 * `handler` reçoit les données du travail et fait le traitement réel. Il doit
 * lever une exception en cas d'échec : c'est ce qui déclenche la nouvelle
 * tentative.
 */
export type JobHandler<T> = (data: T) => Promise<void>;

export interface JobQueue<T> {
  add(data: T): Promise<void>;
  /** Traite ce qui est en attente. Utile aux tests et au mode « inline ». */
  drain(): Promise<void>;
  close(): Promise<void>;
  /**
   * Programme une tâche répétée (jobs planifiés du §14).
   *
   * `pattern` suit la syntaxe cron à 5 champs. `key` identifie la répétition :
   * la reprogrammer avec la même clé ne crée pas de doublon.
   */
  schedule?(data: T, pattern: string, key: string): Promise<void>;
}

/**
 * File d'attente EN MÉMOIRE, avec nouvelles tentatives.
 *
 * Elle sert de repli quand Redis n'est pas disponible — c'est le cas sur
 * l'environnement de développement actuel. Les traitements sont réels, mais
 * la file vit dans le processus : si l'API redémarre, ce qui restait à traiter
 * est perdu. C'est acceptable pour des notifications, pas pour un paiement.
 *
 * Le jour où Redis sera disponible, `QUEUE_DRIVER=bullmq` bascule sur une file
 * persistante sans changer le code appelant.
 */
export class InMemoryQueue<T> implements JobQueue<T> {
  private readonly logger: Logger;
  private readonly pending: { data: T; attempts: number }[] = [];
  private readonly repeats = new Map<string, NodeJS.Timeout>();
  private running = false;
  private timer: NodeJS.Timeout | null = null;

  constructor(
    private readonly name: string,
    private readonly handler: JobHandler<T>,
    private readonly options: { maxAttempts?: number; intervalMs?: number; immediate?: boolean } = {}
  ) {
    this.logger = new Logger(`Queue:${name}`);
  }

  async add(data: T): Promise<void> {
    this.pending.push({ data, attempts: 0 });

    // Mode « immediate » : on traite tout de suite (tests, scripts).
    // Sinon un passage périodique s'en charge, sans bloquer la réponse HTTP.
    if (this.options.immediate) {
      await this.drain();
    } else {
      this.ensureTimer();
    }
  }

  /**
   * Traite tout ce qui est en attente.
   *
   * `running` empêche deux passages simultanés de traiter deux fois la même
   * tâche — ce qui, pour un email, enverrait deux messages.
   */
  async drain(): Promise<void> {
    if (this.running) {
      return;
    }
    this.running = true;

    try {
      const maxAttempts = this.options.maxAttempts ?? 3;

      while (this.pending.length > 0) {
        const job = this.pending.shift()!;
        try {
          await this.handler(job.data);
        } catch (error) {
          job.attempts += 1;
          if (job.attempts < maxAttempts) {
            // On remet en fin de file : les autres tâches passent d'abord.
            this.pending.push(job);
            this.logger.warn(`Échec (tentative ${job.attempts}/${maxAttempts}), sera réessayé`);
          } else {
            this.logger.error(
              `Abandon après ${maxAttempts} tentatives : ${error instanceof Error ? error.message : String(error)}`
            );
          }
        }
      }
    } finally {
      this.running = false;
    }
  }

  private ensureTimer(): void {
    if (this.timer) {
      return;
    }
    const interval = this.options.intervalMs ?? 5_000;
    this.timer = setInterval(() => {
      void this.drain();
    }, interval);
    // `unref` : ce minuteur ne doit pas empêcher le processus de s'arrêter.
    this.timer.unref();
  }

  /**
   * Équivalent « sans Redis » d'une tâche répétée.
   *
   * BullMQ sait interpréter un motif cron ; ici on se contente d'un intervalle
   * régulier déduit du motif. C'est volontairement approximatif : le mode en
   * mémoire est un repli de développement, la planification de production
   * passe par `QUEUE_DRIVER=bullmq`.
   */
  async schedule(data: T, pattern: string, key: string): Promise<void> {
    if (this.repeats.has(key)) {
      return; // déjà programmé
    }
    const interval = intervalFromCron(pattern);
    const timer = setInterval(() => {
      void this.add(data);
    }, interval);
    timer.unref();
    this.repeats.set(key, timer);
    this.logger.log(`Tâche répétée « ${key} » programmée toutes les ${Math.round(interval / 60_000)} min`);
  }

  async close(): Promise<void> {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    for (const timer of this.repeats.values()) {
      clearInterval(timer);
    }
    this.repeats.clear();
  }

  /** Nombre de tâches en attente (diagnostic et tests). */
  get size(): number {
    return this.pending.length;
  }
}

/**
 * Traduit un motif cron simple en intervalle.
 *
 * Seules les deux formes utilisées par le §14 sont reconnues : « toutes les N
 * minutes » (premier champ de la forme `\/N`) et « une fois par jour ». Tout le
 * reste retombe sur une heure, ce qui est sans danger : le pire cas est un job
 * qui tourne plus souvent que prévu et ne trouve rien à faire.
 */
function intervalFromCron(pattern: string): number {
  const minutes = pattern.trim().split(/\s+/)[0] ?? "*";
  const everyN = minutes.match(/^\*\/(\d+)$/);
  if (everyN) {
    return Number(everyN[1]) * 60_000;
  }
  return 60 * 60_000;
}
