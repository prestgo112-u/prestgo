import { Global, Module } from "@nestjs/common";
import { PrismaModule } from "../prisma/prisma.module.js";
import { IdempotencyService } from "./idempotency.service.js";

/**
 * Idempotence (§14.6), globale car toute route de création peut en avoir besoin.
 */
@Global()
@Module({
  imports: [PrismaModule],
  providers: [IdempotencyService],
  exports: [IdempotencyService]
})
export class IdempotencyModule {}
