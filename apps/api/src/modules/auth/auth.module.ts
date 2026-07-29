import { Module } from "@nestjs/common";
import { JwtModule } from "@nestjs/jwt";
import { AuthController } from "./auth.controller.js";
import { AuthService } from "./auth.service.js";
import { AccountService } from "./account.service.js";
import { RefreshSessionService } from "./refresh-session.service.js";
import { JwtStrategy } from "./jwt.strategy.js";
import { JwtAuthGuard } from "./jwt-auth.guard.js";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuditModule } from "../audit/audit.module.js";

@Module({
  imports: [
    PrismaModule,
    AuditModule,
    JwtModule.register({
      secret: process.env.ACCESS_TOKEN_SECRET ?? "development-access-token-secret",
      signOptions: { expiresIn: "15m" }
    })
  ],
  controllers: [AuthController],
  providers: [AuthService, AccountService, RefreshSessionService, JwtStrategy, JwtAuthGuard],
  exports: [AuthService, AccountService, RefreshSessionService, JwtStrategy, JwtAuthGuard, JwtModule]
})
export class AuthModule {}
