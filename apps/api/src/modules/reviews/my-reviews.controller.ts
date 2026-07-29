import { Body, Controller, ForbiddenException, Get, HttpCode, Param, Post, Query, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import { Throttle } from "@nestjs/throttler";
import { THROTTLE_REPORT } from "../../common/config/throttle.config.js";
import { ok } from "../../common/contracts/api-response.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { ReportReviewBodyDto } from "../missions/mobile-dto.js";
import { ReviewSubmissionService } from "./review-submission.service.js";

/** Les avis que j'ai déposés (§11). */
@ApiTags("Reviews")
@ApiBearerAuth()
@Controller("me")
export class MyReviewsController {
  constructor(private readonly reviews: ReviewSubmissionService) {}

  @Get("reviews")
  @ApiOperation({ summary: "List the reviews I posted" })
  async listMine(@Query() query: PaginationQueryDto, @Req() req: AuthenticatedRequest) {
    const authorId = req.user?.id;
    if (!authorId) {
      throw new ForbiddenException("Authentification requise");
    }
    const result = await this.reviews.listMine(authorId, query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }
}

/**
 * Signalement d'un avis (§11).
 *
 * Débit limité à 20 par jour (§14.5) : le signalement est un outil de
 * modération, pas une arme à répétition contre un concurrent.
 */
@ApiTags("Reviews")
@ApiBearerAuth()
@Controller("reviews")
export class ReviewReportsController {
  constructor(private readonly reviews: ReviewSubmissionService) {}

  @Throttle(THROTTLE_REPORT)
  @Post(":id/report")
  @HttpCode(200)
  @ApiOperation({ summary: "Report a review for moderation" })
  async report(@Param("id") id: string, @Body() dto: ReportReviewBodyDto, @Req() req: AuthenticatedRequest) {
    const reporterId = req.user?.id;
    if (!reporterId) {
      throw new ForbiddenException("Authentification requise");
    }
    const result = await this.reviews.report(id, reporterId, dto.reason);
    return ok(result, undefined, "Signalement enregistré. Un modérateur va l'examiner.");
  }
}
