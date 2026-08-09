import { Module } from "@nestjs/common";
import { AdminUsersController } from "./admin-users.controller.js";
import { UsersService } from "./users.service.js";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuditModule } from "../audit/audit.module.js";
import { AuthModule } from "../auth/auth.module.js";

// Un module regroupe ce qui va ensemble : ici le contrôleur users, son service,
// et les modules dont il dépend (base de données, audit, authentification).
@Module({
  imports: [PrismaModule, AuditModule, AuthModule],
  controllers: [AdminUsersController],
  providers: [UsersService],
  exports: [UsersService]
})
export class UsersModule {}