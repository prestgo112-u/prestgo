import { Module } from "@nestjs/common";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuditModule } from "../audit/audit.module.js";
import { AuthModule } from "../auth/auth.module.js";
import { DevicesService } from "./devices.service.js";
import { MeNotificationsController } from "./me-notifications.controller.js";
import { NotificationDispatcher } from "./notification-dispatcher.service.js";
import { NotificationEventsService } from "./notification-events.service.js";
import { NotificationsService } from "./notifications.service.js";

/**
 * Module notifications.
 *
 * Extrait d'`AdministrationModule` au Lot 6 : les missions, les avis et les
 * jobs planifiés doivent tous pouvoir émettre une notification. Leur faire
 * importer le module d'administration entier créerait des cycles.
 */
@Module({
  imports: [PrismaModule, AuditModule, AuthModule],
  controllers: [MeNotificationsController],
  providers: [NotificationsService, NotificationDispatcher, NotificationEventsService, DevicesService],
  exports: [NotificationsService, NotificationDispatcher, NotificationEventsService, DevicesService]
})
export class NotificationsModule {}
