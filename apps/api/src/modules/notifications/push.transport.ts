import { Logger } from "@nestjs/common";
import type { NotificationTransport, OutgoingMessage } from "./transports.js";

/**
 * Jeton refusé par le fournisseur : l'appareil n'existe plus.
 *
 * On la distingue d'une panne réseau parce que les deux appellent des réponses
 * opposées : une panne se réessaie, un jeton mort doit être désactivé et ne
 * plus jamais être réessayé.
 */
export class InvalidPushTokenError extends Error {
  constructor(readonly token: string) {
    super("Jeton push refusé par le fournisseur");
  }
}

export interface PushTarget {
  token: string;
  platform: string;
}

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

/**
 * Ce que sait faire un fournisseur de push, et rien de plus.
 *
 * Le §16.1 le dit explicitement : « écrire le code contre l'interface, jamais
 * contre le fournisseur ». Changer de FCM à un autre service ne doit toucher
 * que l'implémentation, pas le répartiteur ni les services métier.
 */
export interface PushProvider {
  readonly name: string;
  send(target: PushTarget, payload: PushPayload): Promise<void>;
}

/**
 * Firebase Cloud Messaging (HTTP v1).
 *
 * Android et iOS passent tous deux par FCM : Firebase relaie vers APNs pour
 * iOS, ce qui évite d'entretenir deux intégrations et deux jeux de certificats.
 *
 * L'authentification utilise un compte de service Google. On ne dépend
 * volontairement d'aucun SDK : un simple appel HTTPS suffit, et cela évite
 * d'embarquer `firebase-admin` (et ses dizaines de dépendances transitives)
 * pour une seule requête.
 */
export class FcmPushProvider implements PushProvider {
  readonly name = "fcm";
  private readonly logger = new Logger("Push:FCM");
  private accessToken: { value: string; expiresAt: number } | null = null;

  constructor(
    private readonly config: {
      projectId: string;
      clientEmail: string;
      privateKey: string;
    }
  ) {}

  async send(target: PushTarget, payload: PushPayload): Promise<void> {
    const token = await this.authorize();

    const response = await fetch(`https://fcm.googleapis.com/v1/projects/${this.config.projectId}/messages:send`, {
      method: "POST",
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      body: JSON.stringify({
        message: {
          token: target.token,
          notification: { title: payload.title, body: payload.body },
          // FCM n'accepte que des chaînes dans `data` : on sérialise ce qui ne
          // l'est pas, sans quoi la requête est rejetée en bloc.
          data: Object.fromEntries(
            Object.entries(payload.data ?? {}).map(([key, value]) => [
              key,
              typeof value === "string" ? value : JSON.stringify(value)
            ])
          )
        }
      })
    });

    if (response.ok) {
      return;
    }

    const detail = await response.text();

    // 404 = `UNREGISTERED`, 400 = `INVALID_ARGUMENT` sur le jeton. Dans les
    // deux cas le jeton est mort : le réessayer ferait monter le taux d'échec,
    // ce que les fournisseurs sanctionnent.
    if (response.status === 404 || (response.status === 400 && detail.includes("INVALID_ARGUMENT"))) {
      throw new InvalidPushTokenError(target.token);
    }

    this.logger.warn(`FCM ${response.status} : ${detail.slice(0, 300)}`);
    throw new Error(`Échec d'envoi FCM (${response.status})`);
  }

  /**
   * Obtient un jeton d'accès Google, mis en cache jusqu'à son expiration.
   *
   * Redemander un jeton à chaque notification ajouterait un aller-retour
   * réseau par message, pour rien : il est valable une heure.
   */
  private async authorize(): Promise<string> {
    if (this.accessToken && this.accessToken.expiresAt > Date.now() + 60_000) {
      return this.accessToken.value;
    }

    const assertion = await this.buildJwtAssertion();
    const response = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion
      })
    });

    if (!response.ok) {
      throw new Error(`Authentification FCM impossible (${response.status})`);
    }

    const payload = (await response.json()) as { access_token: string; expires_in: number };
    this.accessToken = {
      value: payload.access_token,
      expiresAt: Date.now() + payload.expires_in * 1000
    };
    return payload.access_token;
  }

  /** JWT signé avec la clé privée du compte de service (RS256). */
  private async buildJwtAssertion(): Promise<string> {
    const { createSign } = await import("node:crypto");
    const now = Math.floor(Date.now() / 1000);

    const header = base64Url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
    const claims = base64Url(
      JSON.stringify({
        iss: this.config.clientEmail,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600
      })
    );

    const signer = createSign("RSA-SHA256");
    signer.update(`${header}.${claims}`);
    // Les clés de compte de service arrivent souvent avec des `\n` littéraux
    // quand elles transitent par une variable d'environnement.
    const signature = signer.sign(this.config.privateKey.replace(/\\n/g, "\n"), "base64url");

    return `${header}.${claims}.${signature}`;
  }
}

function base64Url(value: string): string {
  return Buffer.from(value, "utf8").toString("base64url");
}

/**
 * Transport push branché sur un fournisseur.
 *
 * Il ne connaît pas les jetons : c'est le répartiteur qui les lui fournit,
 * parce que lui seul sait à quel utilisateur la notification s'adresse.
 */
export class PushTransport implements NotificationTransport {
  readonly name = "push";

  constructor(
    private readonly provider: PushProvider,
    private readonly resolveTargets: (userId: string) => Promise<PushTarget[]>,
    private readonly onInvalidToken: (token: string) => Promise<void>
  ) {}

  async send(message: OutgoingMessage): Promise<void> {
    const targets = await this.resolveTargets(message.to);

    if (targets.length === 0) {
      // Aucun appareil : ce n'est pas une erreur. L'utilisateur retrouvera la
      // notification en ouvrant l'application (canal in-app).
      return;
    }

    const failures: string[] = [];

    for (const target of targets) {
      try {
        await this.provider.send(target, {
          title: message.title,
          body: message.body,
          data: message.data
        });
      } catch (error) {
        if (error instanceof InvalidPushTokenError) {
          await this.onInvalidToken(error.token);
          continue; // jeton mort : ce n'est pas un échec à réessayer
        }
        failures.push(error instanceof Error ? error.message : String(error));
      }
    }

    // On ne relance que si TOUS les appareils ont échoué. Un téléphone
    // injoignable ne doit pas provoquer un nouvel envoi vers les autres, qui
    // recevraient la notification en double.
    if (failures.length > 0 && failures.length === targets.length) {
      throw new Error(`Push non délivré : ${failures[0]}`);
    }
  }
}
