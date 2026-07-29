import { Module } from "@nestjs/common";
import { AuditService } from "./audit.service.js";
import { PrismaModule } from "../../common/prisma/prisma.module.js";

@Module({
  imports: [PrismaModule],
  providers: [AuditService],
  exports: [AuditService]
})
export class AuditModule {}
