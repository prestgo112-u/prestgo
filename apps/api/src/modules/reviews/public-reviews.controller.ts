import { Controller, Get, Param, Query } from "@nestjs/common";
import { ApiTags, ApiOperation } from "@nestjs/swagger";
import { ReviewsService } from "./reviews.service.js";
import { Public } from "../../common/decorators/public.decorator.js";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { ok } from "../../common/contracts/api-response.js";

// Avis publics d'un prestataire : c'est sa réputation, elle doit être visible
// avant réservation, donc sans compte.
@ApiTags("Reviews")
@Controller("providers")
export class PublicReviewsController {
  constructor(private readonly reviews: ReviewsService) {}

  // GET /providers/:id/reviews — uniquement les avis PUBLIÉS.
  @Public()
  @Get(":id/reviews")
  @ApiOperation({ summary: "List the published reviews of a provider" })
  async listForProvider(@Param("id") id: string, @Query() query: PaginationQueryDto) {
    const result = await this.reviews.listPublicForProvider(id, query);
    return ok(result.data, {
      page: result.page,
      limit: result.limit,
      total: result.total
    });
  }
}
