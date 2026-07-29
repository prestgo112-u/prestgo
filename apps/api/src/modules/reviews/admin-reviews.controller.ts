import { Body, Controller, Get, Param, Patch, Query, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { ReviewsService } from "./reviews.service.js";
import { ReviewListQueryDto, ReviewStatusChangeBodyDto } from "./dto.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";

@ApiTags("Reviews")
@ApiBearerAuth()
@Controller("admin/reviews")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminReviewsController {
  constructor(private readonly reviews: ReviewsService) {}

  // GET /admin/reviews?status=reported
  @Get()
  @Permissions("admin.reviews.read")
  @ApiOperation({ summary: "List reviews" })
  async list(@Query() query: ReviewListQueryDto) {
    const result = await this.reviews.list(query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  // PATCH /admin/reviews/:id/status  { status, reason }
  @Patch(":id/status")
  @Permissions("admin.reviews.moderate")
  @ApiOperation({ summary: "Moderate review" })
  async moderate(
    @Param("id") id: string,
    @Body() body: ReviewStatusChangeBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    return ok(await this.reviews.moderate(id, body.status, body.reason, req.user?.id));
  }
}
