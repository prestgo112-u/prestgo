import { Module } from "@nestjs/common";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuditModule } from "../audit/audit.module.js";
import { AuthModule } from "../auth/auth.module.js";
import { CatalogService } from "./catalog.service.js";
import { AdminCatalogController } from "./admin-catalog.controller.js";
import { PublicCategoriesController, ProviderServicePacksController } from "./public-catalog.controller.js";
import { ZonesService } from "../zones/zones.service.js";
import { AdminZonesController } from "../zones/admin-zones.controller.js";
import { PublicZonesController } from "../zones/public-zones.controller.js";
import { AvailabilityService } from "../availability/availability.service.js";
import { AdminAvailabilityController } from "../availability/admin-availability.controller.js";
import { ProviderAvailabilityController } from "../availability/provider-availability.controller.js";
import { ProviderContextService } from "../providers/provider-context.service.js";

// Module US4 : catalogue (catégories/types), zones et disponibilités.
// Depuis le Lot 3, il expose aussi la vitrine publique et l'espace prestataire.
@Module({
  imports: [PrismaModule, AuditModule, AuthModule],
  controllers: [
    AdminCatalogController,
    AdminZonesController,
    AdminAvailabilityController,
    PublicCategoriesController,
    PublicZonesController,
    ProviderServicePacksController,
    ProviderAvailabilityController
  ],
  providers: [CatalogService, ZonesService, AvailabilityService, ProviderContextService],
  exports: [CatalogService, ZonesService, AvailabilityService]
})
export class CatalogModule {}
