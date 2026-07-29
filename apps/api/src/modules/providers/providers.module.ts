import { Module } from "@nestjs/common";
import { AdminProvidersController } from "./admin-providers.controller.js";
import { ProvidersService } from "./providers.service.js";
import { ProviderContextService } from "./provider-context.service.js";
import { ProviderSelfController } from "./provider-self.controller.js";
import { ProviderSelfService } from "./provider-self.service.js";
import { ProviderSearchController } from "./provider-search.controller.js";
import { ProviderSearchService } from "./provider-search.service.js";
import { AdminVerificationsController } from "../documents/admin-verifications.controller.js";
import { ProviderDocumentsService } from "../documents/provider-documents.service.js";
import { ProviderDocumentsSelfService } from "../documents/provider-documents-self.service.js";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuditModule } from "../audit/audit.module.js";
import { AuthModule } from "../auth/auth.module.js";
import { FilesModule } from "../files/files.module.js";
import { SettingsModule } from "../settings/settings.module.js";
import { NotificationsModule } from "../notifications/notifications.module.js";

// Ce module gère toute l'US2 : profils prestataires + revue de leurs documents.
// FilesModule permet de stocker les justificatifs joints aux documents.
//
// Le Lot 6 y ajoute deux faces nouvelles :
//   - l'espace prestataire en libre-service (§5, §6), qui corrige l'inversion
//     du workflow §6.1 ;
//   - la recherche publique et la fiche publique (§7), moteur de l'écran
//     d'accueil client.
@Module({
  imports: [PrismaModule, AuditModule, AuthModule, FilesModule, SettingsModule, NotificationsModule],
  controllers: [
    AdminProvidersController,
    AdminVerificationsController,
    // La recherche est déclarée AVANT l'espace prestataire : `/providers/search`
    // doit être reconnue avant tout segment dynamique.
    ProviderSearchController,
    ProviderSelfController
  ],
  providers: [
    ProvidersService,
    ProviderDocumentsService,
    ProviderDocumentsSelfService,
    ProviderContextService,
    ProviderSelfService,
    ProviderSearchService
  ],
  exports: [
    ProvidersService,
    ProviderDocumentsService,
    ProviderContextService,
    ProviderSelfService,
    ProviderSearchService
  ]
})
export class ProvidersModule {}
