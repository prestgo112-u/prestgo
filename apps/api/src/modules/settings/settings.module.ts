import { Module } from "@nestjs/common";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuditModule } from "../audit/audit.module.js";
import { SettingsService } from "./settings.service.js";

/**
 * Module dédié aux réglages système.
 *
 * `SettingsService` était jusqu'ici déclaré dans `AdministrationModule`. Les
 * règles métier du Lot 6 (délai de prévenance, fenêtre d'avis, documents
 * obligatoires…) doivent y accéder depuis les missions, les prestataires et
 * les jobs : les faire tous importer le module d'administration créerait des
 * cycles de dépendance. Un petit module autonome règle le problème.
 */
@Module({
  imports: [PrismaModule, AuditModule],
  providers: [SettingsService],
  exports: [SettingsService]
})
export class SettingsModule {}
