import { Logger } from "@nestjs/common";
import type { NotificationTransport, OutgoingMessage } from "./transports.js";

/**
 * Transport SMS réel (§16.2).
 *
 * En Côte d'Ivoire, l'inscription passera massivement par le téléphone : l'OTP
 * doit partir par un vrai SMS, pas dans un journal fichier. Le marché local
 * impose un agrégateur couvrant Orange, MTN et Moov.
 *
 * Deux fournisseurs sont câblés ici parce qu'ils couvrent le marché visé et
 * exposent tous deux une API HTTP simple. Le choix se fait par `SMS_PROVIDER` ;
 * en ajouter un troisième revient à écrire une classe de plus, sans toucher au
 * reste.
 */
export interface SmsProvider {
  readonly name: string;
  send(to: string, message: string): Promise<void>;
}

/** Termii — agrégateur très présent en Afrique de l'Ouest. */
export class TermiiSmsProvider implements SmsProvider {
  readonly name = "termii";
  private readonly logger = new Logger("SMS:Termii");

  constructor(
    private readonly config: { apiKey: string; senderId: string; baseUrl?: string }
  ) {}

  async send(to: string, message: string): Promise<void> {
    const baseUrl = this.config.baseUrl ?? "https://api.ng.termii.com";

    const response = await fetch(`${baseUrl}/api/sms/send`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        to: normalizeMsisdn(to),
        from: this.config.senderId,
        sms: message,
        type: "plain",
        channel: "generic",
        api_key: this.config.apiKey
      })
    });

    if (!response.ok) {
      const detail = await response.text();
      this.logger.warn(`Termii ${response.status} : ${detail.slice(0, 200)}`);
      throw new Error(`Échec d'envoi SMS (${response.status})`);
    }
  }
}

/** Africa's Talking — second agrégateur couvrant les opérateurs ivoiriens. */
export class AfricasTalkingSmsProvider implements SmsProvider {
  readonly name = "africastalking";
  private readonly logger = new Logger("SMS:AfricasTalking");

  constructor(
    private readonly config: { apiKey: string; username: string; senderId?: string; baseUrl?: string }
  ) {}

  async send(to: string, message: string): Promise<void> {
    const baseUrl =
      this.config.baseUrl ??
      (this.config.username === "sandbox"
        ? "https://api.sandbox.africastalking.com"
        : "https://api.africastalking.com");

    const body = new URLSearchParams({
      username: this.config.username,
      to: normalizeMsisdn(to),
      message,
      ...(this.config.senderId ? { from: this.config.senderId } : {})
    });

    const response = await fetch(`${baseUrl}/version1/messaging`, {
      method: "POST",
      headers: {
        apiKey: this.config.apiKey,
        "content-type": "application/x-www-form-urlencoded",
        accept: "application/json"
      },
      body
    });

    if (!response.ok) {
      const detail = await response.text();
      this.logger.warn(`Africa's Talking ${response.status} : ${detail.slice(0, 200)}`);
      throw new Error(`Échec d'envoi SMS (${response.status})`);
    }
  }
}

/**
 * Transport SMS avec REPLI.
 *
 * Si le fournisseur échoue, le message est écrit dans la boîte d'envoi
 * fichier. Ce n'est pas un pansement cosmétique : cela garantit qu'un code OTP
 * reste retrouvable en exploitation, et donc qu'un utilisateur bloqué peut
 * être dépanné par le support pendant une panne de l'agrégateur.
 *
 * L'échec est tout de même relancé pour que la file réessaie : le repli sert à
 * ne rien perdre, pas à faire croire que l'envoi a réussi.
 */
export class SmsTransport implements NotificationTransport {
  readonly name = "sms";
  private readonly logger = new Logger("SMS");

  constructor(
    private readonly provider: SmsProvider,
    private readonly fallback: NotificationTransport
  ) {}

  async send(message: OutgoingMessage): Promise<void> {
    try {
      await this.provider.send(message.to, `${message.title}\n${message.body}`.trim());
    } catch (error) {
      this.logger.error(
        `Envoi SMS via ${this.provider.name} en échec, message consigné dans la boîte d'envoi : ${
          error instanceof Error ? error.message : String(error)
        }`
      );
      await this.fallback.send(message);
      throw error;
    }
  }
}

/**
 * Met un numéro au format international.
 *
 * Un numéro ivoirien saisi localement (« 0700000000 ») est refusé tel quel par
 * les agrégateurs, qui attendent l'indicatif pays.
 */
function normalizeMsisdn(raw: string): string {
  const cleaned = raw.replace(/[\s-]/g, "");
  if (cleaned.startsWith("+")) {
    return cleaned;
  }
  if (cleaned.startsWith("00")) {
    return `+${cleaned.slice(2)}`;
  }
  const defaultCountryCode = process.env.SMS_DEFAULT_COUNTRY_CODE ?? "225";
  return `+${defaultCountryCode}${cleaned.replace(/^0+/, "")}`;
}
