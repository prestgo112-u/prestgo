import { AsyncLocalStorage } from "node:async_hooks";
import type { Request } from "express";

export interface RequestContext {
  correlationId: string;
  /** Adresse IP réelle de l'appelant (déjà dé-proxyfiée). */
  ip?: string;
}

/**
 * Contexte de la requête en cours, accessible sans le faire descendre de main
 * en main.
 *
 * Pourquoi : le journal d'audit doit consigner l'adresse IP de l'auteur d'une
 * action sensible (§15.5). Le champ `audit_logs.ip` existait depuis le début
 * mais restait toujours vide, faute d'un chemin entre la requête HTTP et
 * `AuditService.record()` — qui est appelé depuis 46 endroits, tous dans des
 * services qui ne connaissent pas la requête.
 *
 * `AsyncLocalStorage` résout ça proprement : la valeur posée au début de la
 * requête reste visible dans tout ce qui en découle, y compris après un `await`,
 * et deux requêtes simultanées ne se marchent jamais dessus.
 */
const storage = new AsyncLocalStorage<RequestContext>();

export function runWithRequestContext<T>(context: RequestContext, callback: () => T): T {
  return storage.run(context, callback);
}

export function currentRequestContext(): RequestContext | undefined {
  return storage.getStore();
}

/** Raccourci : l'IP de la requête en cours, ou `undefined` hors requête (job planifié). */
export function currentIp(): string | undefined {
  return storage.getStore()?.ip;
}

/**
 * Extrait l'adresse IP réelle de l'appelant.
 *
 * Derrière un proxy (Nginx, load balancer, Cloudflare), `request.ip` est
 * l'adresse du proxy — la même pour tout le monde, donc inutile dans un
 * journal. Le premier élément de `X-Forwarded-For` est l'adresse d'origine.
 *
 * Cet en-tête est déclaratif : n'importe qui peut l'écrire. On ne le lit donc
 * que si `TRUST_PROXY=true`, c'est-à-dire quand on sait que l'application est
 * bien derrière un proxy qui le réécrit. Sinon on retombe sur l'adresse de la
 * connexion, qui elle ne se falsifie pas.
 */
export function resolveClientIp(request: Request): string | undefined {
  if (process.env.TRUST_PROXY === "true") {
    const forwarded = request.header("x-forwarded-for");
    const first = forwarded?.split(",")[0]?.trim();
    if (first) {
      return normalize(first);
    }
    const realIp = request.header("x-real-ip")?.trim();
    if (realIp) {
      return normalize(realIp);
    }
  }

  return normalize(request.ip ?? request.socket?.remoteAddress ?? undefined);
}

// `::ffff:127.0.0.1` est la façon dont une pile IPv6 représente une adresse
// IPv4. On la ramène à sa forme lisible.
function normalize(ip: string | undefined): string | undefined {
  if (!ip) return undefined;
  return ip.startsWith("::ffff:") ? ip.slice(7) : ip;
}
