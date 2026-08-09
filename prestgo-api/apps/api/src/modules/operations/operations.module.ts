import { Module } from "@nestjs/common";
import { PrismaModule } from "../../common/prisma/prisma.module.js";
import { AuditModule } from "../audit/audit.module.js";
import { AuthModule } from "../auth/auth.module.js";
import { NotificationsModule } from "../notifications/notifications.module.js";
import { SettingsModule } from "../settings/settings.module.js";
import { ProvidersModule } from "../providers/providers.module.js";
import { AdminMissionsController } from "../missions/admin-missions.controller.js";
import { MissionsController } from "../missions/missions.controller.js";
import { MissionsService } from "../missions/missions.service.js";
import { MissionAccessService } from "../missions/mission-access.service.js";
import { MissionBookingService } from "../missions/mission-booking.service.js";
import { MissionLifecycleService } from "../missions/mission-lifecycle.service.js";
import { MissionRescheduleService } from "../missions/mission-reschedule.service.js";
import { ClientMissionsController, MissionActionsController } from "../missions/mission-actions.controller.js";
import { ProviderMissionsController } from "../missions/provider-missions.controller.js";
import { AdminMessagesController } from "../messages/admin-messages.controller.js";
import { MessagesController } from "../messages/messages.controller.js";
import { MyThreadsController, ThreadReadController } from "../messages/me-threads.controller.js";
import { MessagesService } from "../messages/messages.service.js";
import { AdminReviewsController } from "../reviews/admin-reviews.controller.js";
import { PublicReviewsController } from "../reviews/public-reviews.controller.js";
import { MyReviewsController, ReviewReportsController } from "../reviews/my-reviews.controller.js";
import { ReviewsService } from "../reviews/reviews.service.js";
import { ReviewSubmissionService } from "../reviews/review-submission.service.js";
import { ProviderRatingService } from "../reviews/provider-rating.service.js";
import { AdminDisputesController } from "../disputes/admin-disputes.controller.js";
import { DisputesController } from "../disputes/disputes.controller.js";
import { DisputesService } from "../disputes/disputes.service.js";

/**
 * Module « opérations » : missions, messages, avis, litiges (US3).
 *
 * Depuis le Lot 3 il expose les routes destinées aux clients et prestataires,
 * protégées par le contrôle d'appartenance (`MissionAccessService`).
 *
 * Le Lot 6 y ajoute la boucle de valeur complète (§8 à §11) : réservation,
 * cycle prestataire, reprogrammation à deux parties, dépôt d'avis. Toutes ces
 * routes passent par `MissionLifecycleService`, le service de transition
 * UNIQUE — c'est la garantie du §14.1 : aucune logique métier n'est dupliquée
 * entre la surface mobile et le back-office.
 */
@Module({
  imports: [PrismaModule, AuditModule, AuthModule, SettingsModule, NotificationsModule, ProvidersModule],
  controllers: [
    AdminMissionsController,
    AdminMessagesController,
    AdminReviewsController,
    AdminDisputesController,
    MissionsController,
    MissionActionsController,
    ClientMissionsController,
    ProviderMissionsController,
    MessagesController,
    MyThreadsController,
    ThreadReadController,
    PublicReviewsController,
    MyReviewsController,
    ReviewReportsController,
    DisputesController
  ],
  providers: [
    MissionsService,
    MissionBookingService,
    MissionLifecycleService,
    MissionRescheduleService,
    MessagesService,
    ReviewsService,
    ReviewSubmissionService,
    ProviderRatingService,
    DisputesService,
    MissionAccessService
  ],
  exports: [
    MissionsService,
    MissionBookingService,
    MissionLifecycleService,
    MessagesService,
    ReviewsService,
    ProviderRatingService,
    DisputesService,
    MissionAccessService
  ]
})
export class OperationsModule {}
