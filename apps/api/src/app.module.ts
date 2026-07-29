import { MiddlewareConsumer, Module, NestModule } from "@nestjs/common";
import { APP_GUARD } from "@nestjs/core";
import { ThrottlerModule } from "@nestjs/throttler";
import { CorrelationMiddleware } from "./common/middleware/correlation.middleware.js";
import { FriendlyThrottlerGuard } from "./common/guards/throttler.guard.js";
import { THROTTLE_DEFAULT } from "./common/config/throttle.config.js";
import { PermissionsGuard } from "./common/guards/permissions.guard.js";
import { JwtAuthGuard } from "./modules/auth/jwt-auth.guard.js";
import { PrismaModule } from "./common/prisma/prisma.module.js";
import { QueueModule } from "./common/queues/queue.module.js";
import { AuditModule } from "./modules/audit/audit.module.js";
import { AuthModule } from "./modules/auth/auth.module.js";
import { FilesModule } from "./modules/files/files.module.js";
import { UsersModule } from "./modules/users/users.module.js";
import { RolesModule } from "./modules/roles/roles.module.js";
import { AdminModule } from "./modules/admin/admin.module.js";
import { ProvidersModule } from "./modules/providers/providers.module.js";
import { ClientsModule } from "./modules/clients/clients.module.js";
import { OperationsModule } from "./modules/operations/operations.module.js";
import { CatalogModule } from "./modules/catalog/catalog.module.js";
import { AdministrationModule } from "./modules/administration/administration.module.js";
import { SettingsModule } from "./modules/settings/settings.module.js";
import { NotificationsModule } from "./modules/notifications/notifications.module.js";
import { DirectMessageModule } from "./modules/notifications/direct-message.service.js";
import { IdempotencyModule } from "./common/idempotency/idempotency.module.js";
import { MeModule } from "./modules/me/me.module.js";
import { JobsModule } from "./modules/jobs/jobs.module.js";

// AppModule est le module racine : il importe tous les autres modules de l'app.
// Ajouter un module ici l'active dans l'application (ses routes deviennent accessibles).
@Module({
  imports: [
    // Limite le nombre d'appels par adresse IP (CDC §10 : « rate limiting »).
    // Plafond général large : il protège d'un emballement sans gêner le
    // back-office. Les routes sensibles comme /auth/login sont bien plus
    // strictes grâce au décorateur @Throttle posé sur le contrôleur.
    ThrottlerModule.forRoot([THROTTLE_DEFAULT]),
    PrismaModule,
    // Déclaré avant AuthModule : `AccountService` s'en sert pour acheminer les
    // codes OTP, et le module est global pour éviter un cycle d'imports.
    DirectMessageModule,
    AuthModule,
    AuditModule,
    FilesModule,
    QueueModule,
    UsersModule,
    RolesModule,
    AdminModule,
    ProvidersModule,
    ClientsModule,
    OperationsModule,
    CatalogModule,
    AdministrationModule,
    // Lot 6 : surface mobile.
    SettingsModule,
    NotificationsModule,
    IdempotencyModule,
    MeModule,
    JobsModule
  ],
  controllers: [],
  // APP_GUARD = garde appliquée à TOUTES les routes de l'application.
  // L'ordre compte : on vérifie d'abord le token (JwtAuthGuard), ce qui remplit
  // request.user, puis les permissions (PermissionsGuard) qui s'appuient dessus.
  // Avant le Lot 0, ces gardes n'étaient posées qu'au cas par cas sur chaque
  // contrôleur : un contrôleur ajouté sans @UseGuards était donc public.
  // Le limiteur passe en premier : une attaque par force brute est ainsi
  // bloquée avant même qu'on tente de vérifier un token.
  providers: [
    { provide: APP_GUARD, useClass: FriendlyThrottlerGuard },
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: PermissionsGuard }
  ]
})
export class AppModule implements NestModule {
  // Un "middleware" s'exécute AVANT les gardes : c'est pour ça que l'id de
  // corrélation est posé ici et pas dans un interceptor. Sinon une requête
  // refusée par une garde (401/403) n'aurait aucun id dans sa réponse.
  configure(consumer: MiddlewareConsumer): void {
    consumer.apply(CorrelationMiddleware).forRoutes("*");
  }
}
