import { Module } from "@nestjs/common";
import { AdminClientsController } from "./admin-clients.controller.js";
import { ClientsService } from "./clients.service.js";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuditModule } from "../audit/audit.module.js";

// Module Clients : consultation des comptes clients depuis le back-office.
@Module({
  imports: [PrismaModule, AuditModule],
  controllers: [AdminClientsController],
  providers: [ClientsService],
  exports: [ClientsService]
})
export class ClientsModule {}
