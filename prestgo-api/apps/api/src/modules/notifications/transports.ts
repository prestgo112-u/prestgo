import { Logger } from "@nestjs/common";
import { appendFile, mkdir } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { FcmPushProvider, PushTransport, type PushProvider, type PushTarget } from "./push.transport.js";
import {
  AfricasTalkingSmsProvider,
  SmsTransport,
  TermiiSmsProvider,
  type SmsProvider
} from "./sms.transport.js";

export interface OutgoingMessage {
  channel: string;
  to: string;
  title: string;
  body: string;
  /** Données structurées, transmises telles quelles au push (§12). */
  data?: Record<string, unknown>;
}

/**
 * Un transport sait acheminer un message vers un canal (email, SMS...).
 *
 * L'interface est volontairement minimale : le jour où un vrai fournisseur
 * (SMTP, Twilio, Orange SMS...) sera branché, seule une implémentation
 * s'ajoute — le reste du code ne bouge pas.
 */
export interface NotificationTransport {
  readonly name: string;
  send(message: OutgoingMessage): Promise<void>;
}

/**
 * Transport « in_app » : la notification vit uniquement en base, l'utilisateur
 * la lira dans l'application. Il n'y a donc rien à acheminer.
 */
export class InAppTransport implements NotificationTransport {
  readonly name = "in_app";

  async send(): Promise<void> {
    // Rien à faire : l'enregistrement en base EST la livraison.
  }
}

/**
 * Transport de secours : écrit le message dans un fichier et dans les logs.
 *
 * C'est ce qui est utilisé tant qu'aucun fournisseur d'email ou de SMS n'est
 * configuré. Ce n'est pas un simulacre : le message est réellement produit,
 * horodaté et conservé — on peut vérifier ce qui aurait été envoyé, et à qui.
 * Cela évite surtout de faire croire qu'un envoi a eu lieu alors que rien ne
 * partait, ce qui était le cas avant ce lot.
 */
export class FileTransport implements NotificationTransport {
  private readonly logger = new Logger("NotificationOutbox");

  constructor(readonly name: string) {}

  async send(message: OutgoingMessage): Promise<void> {
    const path = resolve(process.env.NOTIFICATION_OUTBOX ?? "storage/outbox", `${this.name}.log`);
    await mkdir(dirname(path), { recursive: true });

    const line = JSON.stringify({ at: new Date().toISOString(), ...message });
    await appendFile(path, `${line}\n`, "utf8");

    this.logger.log(`[${this.name}] -> ${message.to} : ${message.title}`);
  }
}

/**
 * Choisit le transport de chaque canal.
 *
 * Le principe est le même pour le SMS (§16.2) et le push (§16.1) : si un
 * fournisseur est CONFIGURÉ, on l'utilise ; sinon on retombe sur le transport
 * fichier. Le repli n'est pas un faux-semblant — le message est réellement
 * produit et horodaté, on peut vérifier ce qui serait parti et à qui. C'est ce
 * qui permet de développer sans compte fournisseur, sans jamais faire croire
 * qu'un envoi a eu lieu.
 *
 * `pushHooks` est fourni par le répartiteur : lui seul sait résoudre un
 * utilisateur en jetons d'appareil et désactiver un jeton refusé.
 */
export function buildTransports(pushHooks?: PushHooks): Map<string, NotificationTransport> {
  const transports = new Map<string, NotificationTransport>();
  const logger = new Logger("NotificationTransports");

  transports.set("in_app", new InAppTransport());
  transports.set("email", new FileTransport("email"));

  const smsProvider = buildSmsProvider();
  if (smsProvider) {
    transports.set("sms", new SmsTransport(smsProvider, new FileTransport("sms")));
    logger.log(`Canal SMS : fournisseur « ${smsProvider.name} »`);
  } else {
    transports.set("sms", new FileTransport("sms"));
    logger.warn("Canal SMS : aucun fournisseur configuré, repli sur la boîte d'envoi fichier");
  }

  if (pushHooks) {
    const pushProvider = buildPushProvider();
    if (pushProvider) {
      transports.set("push", new PushTransport(pushProvider, pushHooks.resolveTargets, pushHooks.onInvalidToken));
      logger.log(`Canal push : fournisseur « ${pushProvider.name} »`);
    } else {
      transports.set("push", new FileTransport("push"));
      logger.warn("Canal push : aucun fournisseur configuré, repli sur la boîte d'envoi fichier");
    }
  }

  return transports;
}

export interface PushHooks {
  resolveTargets: (userId: string) => Promise<PushTarget[]>;
  onInvalidToken: (token: string) => Promise<void>;
}

/** Fournisseur SMS déduit de la configuration (`SMS_PROVIDER`). */
function buildSmsProvider(): SmsProvider | null {
  const provider = process.env.SMS_PROVIDER?.trim().toLowerCase();

  if (provider === "termii") {
    const apiKey = process.env.TERMII_API_KEY;
    const senderId = process.env.TERMII_SENDER_ID;
    if (!apiKey || !senderId) {
      return null; // configuration incomplète : on ne prétend pas pouvoir envoyer
    }
    return new TermiiSmsProvider({ apiKey, senderId, baseUrl: process.env.TERMII_BASE_URL });
  }

  if (provider === "africastalking") {
    const apiKey = process.env.AT_API_KEY;
    const username = process.env.AT_USERNAME;
    if (!apiKey || !username) {
      return null;
    }
    return new AfricasTalkingSmsProvider({
      apiKey,
      username,
      senderId: process.env.AT_SENDER_ID,
      baseUrl: process.env.AT_BASE_URL
    });
  }

  return null;
}

/** Fournisseur push déduit de la configuration (compte de service Firebase). */
function buildPushProvider(): PushProvider | null {
  const projectId = process.env.FCM_PROJECT_ID;
  const clientEmail = process.env.FCM_CLIENT_EMAIL;
  const privateKey = process.env.FCM_PRIVATE_KEY;

  if (!projectId || !clientEmail || !privateKey) {
    return null;
  }
  return new FcmPushProvider({ projectId, clientEmail, privateKey });
}
