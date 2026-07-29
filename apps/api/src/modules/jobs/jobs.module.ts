import { Module } from "@nestjs/common";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuditModule } from "../audit/audit.module.js";
import { AuthModule } from "../auth/auth.module.js";
import { NotificationsModule } from "../notifications/notifications.module.js";
import { OperationsModule } from "../operations/operations.module.js";
import { SettingsModule } from "../settings/settings.module.js";
import { AdminJobsController } from "./admin-jobs.controller.js";
import { ScheduledJobsService } from "./scheduled-jobs.service.js";

/**
 * Jobs planifiés (Lot 7.1, §14).
 *
 * Le module dépend d'`OperationsModule` pour réutiliser
 * `MissionLifecycleService` : un job qui expire une mission emprunte le MÊME
 * chemin de transition qu'un prestataire qui la refuse. C'est le principe du
 * §14.1 appliqué aux traitements automatiques — sinon la machine à états
 * aurait une porte dérobée.
 */
@Module({
  imports: [PrismaModule, AuditModule, AuthModule, SettingsModule, NotificationsModule, OperationsModule],
  controllers: [AdminJobsController],
  providers: [ScheduledJobsService],
  exports: [ScheduledJobsService]
})
export class JobsModule {}
