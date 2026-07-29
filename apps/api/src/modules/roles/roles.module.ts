import { Module } from "@nestjs/common";
import { AdminRolesController } from "./admin-roles.controller.js";
import { RolesService } from "./roles.service.js";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuditModule } from "../audit/audit.module.js";
import { AuthModule } from "../auth/auth.module.js";

@Module({
  imports: [PrismaModule, AuditModule, AuthModule],
  controllers: [AdminRolesController],
  providers: [RolesService],
  exports: [RolesService]
})
export class RolesModule {}