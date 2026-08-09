import { Global, Module } from "@nestjs/common";

export const QUEUE_CONNECTION = Symbol("QUEUE_CONNECTION");

export interface QueueConnectionOptions {
  redisUrl: string;
}

@Global()
@Module({
  providers: [
    {
      provide: QUEUE_CONNECTION,
      useFactory: (): QueueConnectionOptions => ({
        redisUrl: process.env.REDIS_URL ?? "redis://localhost:6379"
      })
    }
  ],
  exports: [QUEUE_CONNECTION]
})
export class QueueModule {}
