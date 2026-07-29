import { Controller, HttpCode, Param, Post, Req } from "@nestjs/common";
import { ApiBearerAuth, ApiOperation, ApiTags } from "@nestjs/swagger";
import { ok } from "../../common/contracts/api-response.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { SCHEDULED_JOBS, ScheduledJobsService, type ScheduledJobName } from "./scheduled-jobs.service.js";
import { BadRequestException } from "@nestjs/common";

/**
 * Déclenchement manuel des jobs planifiés (§14).
 *
 * Pourquoi cette route existe : un job qui ne tourne que sur minuterie est
 * impossible à vérifier autrement qu'en attendant. Elle sert au diagnostic
 * (« l'expiration a-t-elle vraiment lieu ? ») et au rattrapage après une
 * indisponibilité de Redis.
 *
 * Réservée à la permission d'administration : déclencher une clôture massive
 * n'est pas une action anodine.
 */
@ApiTags("Admin jobs")
@ApiBearerAuth()
@Controller("admin/jobs")
export class AdminJobsController {
  constructor(private readonly jobs: ScheduledJobsService) {}

  @Post(":name/run")
  @HttpCode(200)
  @Permissions("admin.settings.update")
  @ApiOperation({ summary: "Run a scheduled job now (diagnosis and catch-up)" })
  async run(@Param("name") name: string, @Req() req: AuthenticatedRequest) {
    if (!(name in SCHEDULED_JOBS)) {
      throw new BadRequestException(`Job inconnu : « ${name} ». Jobs : ${Object.keys(SCHEDULED_JOBS).join(", ")}`);
    }
    const result = await this.jobs.run(name as ScheduledJobName);
    return ok({ job: name, result, triggeredBy: req.user?.id }, undefined, "Job exécuté");
  }
}
