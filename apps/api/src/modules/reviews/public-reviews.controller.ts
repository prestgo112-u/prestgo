import { Controller, Get, Param, Query } from "@nestjs/common";
import { ApiTags, ApiOperation } from "@nestjs/swagger";
import { ReviewsService } from "./reviews.service.js";
import { Public } from "../../common/decorators/public.decorator.js";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";
import { ok } from "../../common/contracts/api-response.js";
import { ApiEnvelopeResponse } from "../../common/openapi/api-envelope.decorator.js";
import { PublicReviewDto } from "./response-dto.js";

// Avis publics d'un prestataire : c'est sa réputation, elle doit être visible
// avant réservation, donc sans compte.
@ApiTags("Reviews")
@Controller("providers")
export class PublicReviewsController {
  constructor(private readonly reviews: ReviewsService) {}

  /**
   * GET /providers/:id/reviews — uniquement les avis PUBLIÉS.
   *
   * `data` est un tableau et la pagination tient dans `meta`, comme toute
   * autre liste de l'API. Cette route renvoyait auparavant un objet
   * `{ averageRating, totalReviews, reviews }` : elle imposait à elle seule un
   * modèle client à part. Les deux agrégats retirés faisaient doublon —
   * `totalReviews` avec `meta.total`, `averageRating` avec le `score` de la
   * fiche publique, d'où l'on ouvre cette liste.
   */
  @Public()
  @Get(":id/reviews")
  @ApiOperation({ summary: "List the published reviews of a provider" })
  @ApiEnvelopeResponse(PublicReviewDto, {
    isArray: true,
    paginated: true,
    description: "Avis publiés de ce prestataire, du plus récent au plus ancien"
  })
  async listForProvider(@Param("id") id: string, @Query() query: PaginationQueryDto) {
    const result = await this.reviews.listPublicForProvider(id, query);
    return ok(result.data, {
      page: result.page,
      limit: result.limit,
      total: result.total
    });
  }
}
