import { Body, Controller, Get, HttpCode, Param, Post, Req } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { DisputesService } from "./disputes.service.js";
import { OpenDisputeBodyDto } from "./dto.js";
import { MissionAccessService } from "../missions/mission-access.service.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { ok } from "../../common/contracts/api-response.js";

// Ouverture d'un litige par un client ou un prestataire (CDC §6.2 : « un
// client, un prestataire ou un agent ouvre un litige »).
@ApiTags("Disputes")
@ApiBearerAuth()
@Controller("disputes")
export class DisputesController {
  constructor(
    private readonly disputes: DisputesService,
    private readonly access: MissionAccessService
  ) {}

  // POST /disputes — ouvrir un litige sur SA mission.
  @Post()
  @HttpCode(201)
  @ApiOperation({ summary: "Open a dispute on one of my missions" })
  async open(@Body() dto: OpenDisputeBodyDto, @Req() req: AuthenticatedRequest) {
    // On n'ouvre un litige que sur une mission dont on est partie prenante.
    await this.access.requireParticipant(dto.missionId, req.user ?? {}, "admin.disputes.manage");
    return ok(await this.disputes.open(dto, req.user?.id), undefined, "Litige ouvert");
  }

  // GET /disputes/:id — suivre son litige.
  @Get(":id")
  @ApiOperation({ summary: "Follow one of my disputes" })
  async detail(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    // On charge d'abord SANS les commentaires internes : même si le contrôle
    // d'accès échouait juste après, aucune note d'agent n'aurait été lue.
    const dispute = await this.disputes.findById(id, false);
    await this.access.requireParticipant(dispute.missionId, req.user ?? {}, "admin.disputes.read");
    return ok(dispute);
  }
}
