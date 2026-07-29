import { Module } from "@nestjs/common";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuditModule } from "../audit/audit.module.js";
import { AuthModule } from "../auth/auth.module.js";
import { AddressesService } from "./addresses.service.js";
import { FavoritesService } from "./favorites.service.js";
import { MeController } from "./me.controller.js";
import { MeService } from "./me.service.js";

/**
 * Module « espace personnel » (Lot 6.1 et 6.3).
 *
 * Il regroupe ce qui appartient à l'utilisateur connecté : son profil, son
 * carnet d'adresses et ses favoris. Les missions et notifications « me » vivent
 * dans leurs modules métier respectifs, pour ne pas dupliquer la logique.
 */
@Module({
  imports: [PrismaModule, AuditModule, AuthModule],
  controllers: [MeController],
  providers: [MeService, AddressesService, FavoritesService],
  exports: [MeService, AddressesService, FavoritesService]
})
export class MeModule {}
