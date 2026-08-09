import { Global, Injectable, Logger, Module } from "@nestjs/common";
import { buildTransports, type NotificationTransport } from "./transports.js";

/**
 * Envoi IMMÉDIAT d'un message, sans passer par la table `notifications`.
 *
 * Un code OTP n'est pas une notification comme les autres : il s'adresse à un
 * numéro ou à une adresse qui n'appartient pas forcément encore à un compte
 * (inscription, changement de téléphone). Il ne peut donc pas être rattaché à
 * un `userId`, et il n'a aucune raison d'apparaître dans la liste
 * « mes notifications ».
 *
 * Il est aussi le seul message dont la valeur s'évapore : le mettre en file
 * d'attente, avec réessais espacés, ferait arriver le code après son
 * expiration. D'où cet envoi direct.
 *
 * Le module est autonome et global : `AccountService` en dépend, et
 * `NotificationsModule` dépend d'`AuthModule` — les faire s'importer
 * mutuellement créerait un cycle.
 */
@Injectable()
export class DirectMessageService {
  private readonly logger = new Logger(DirectMessageService.name);
  private readonly transports: Map<string, NotificationTransport>;

  constructor() {
    // Sans `pushHooks` : ce service n'envoie jamais de push, un OTP par
    // notification poussée n'aurait aucun sens.
    this.transports = buildTransports();
  }

  /**
   * Envoie un SMS. Renvoie `false` en cas d'échec au lieu de lever.
   *
   * L'appelant décide quoi en faire : pour un OTP, l'échec d'envoi ne doit pas
   * faire échouer la requête HTTP, sinon on révélerait au passage si le
   * destinataire est valide. Le code reste utilisable si l'utilisateur le
   * reçoit par un autre biais, et le support le retrouve dans la boîte d'envoi.
   */
  async sendSms(to: string, title: string, body: string): Promise<boolean> {
    return this.send("sms", to, title, body);
  }

  async sendEmail(to: string, title: string, body: string): Promise<boolean> {
    return this.send("email", to, title, body);
  }

  private async send(channel: string, to: string, title: string, body: string): Promise<boolean> {
    const transport = this.transports.get(channel);
    if (!transport) {
      this.logger.warn(`Canal « ${channel} » non configuré`);
      return false;
    }

    try {
      await transport.send({ channel, to, title, body });
      return true;
    } catch (error) {
      this.logger.error(
        `Envoi « ${channel} » en échec : ${error instanceof Error ? error.message : String(error)}`
      );
      return false;
    }
  }
}

@Global()
@Module({
  providers: [DirectMessageService],
  exports: [DirectMessageService]
})
export class DirectMessageModule {}
