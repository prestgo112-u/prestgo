import { Module } from "@nestjs/common";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuditModule } from "../audit/audit.module.js";
import { AuthModule } from "../auth/auth.module.js";
import { AdminSettingsController } from "../settings/admin-settings.controller.js";
import { MaintenanceService } from "./maintenance.service.js";
import { AdminNotificationsController } from "../notifications/admin-notifications.controller.js";
import { AdminNotificationTemplatesController } from "../notifications/admin-notification-templates.controller.js";
import { ExportsService } from "../reports/exports.service.js";
import { AdminExportsController } from "../reports/admin-exports.controller.js";
import { AdminAuditController } from "../audit/admin-audit.controller.js";
import { FilesModule } from "../files/files.module.js";
import { SettingsModule } from "../settings/settings.module.js";
import { NotificationsModule } from "../notifications/notifications.module.js";

/**
 * Module US5 : réglages, notifications, exports et journal d'audit.
 *
 * `FilesModule` sert aux exports, qui écrivent leurs CSV sur le disque.
 *
 * `NotificationsService` et `NotificationDispatcher` sont désormais IMPORTÉS
 * depuis `NotificationsModule` au lieu d'être déclarés ici. Les déclarer aux
 * deux endroits aurait créé deux instances du répartiteur — donc deux files
 * d'attente indépendantes, chacune ignorant ce que l'autre a déjà traité.
 */
@Module({
  imports: [PrismaModule, AuditModule, AuthModule, FilesModule, SettingsModule, NotificationsModule],
  controllers: [
    AdminSettingsController,
    AdminNotificationsController,
    AdminNotificationTemplatesController,
    AdminExportsController,
    AdminAuditController
  ],
  providers: [ExportsService, MaintenanceService],
  exports: [ExportsService]
})
export class AdministrationModule {}
