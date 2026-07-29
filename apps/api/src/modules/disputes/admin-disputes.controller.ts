import { Body, Controller, Get, HttpCode, Param, Patch, Post, Query, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { DisputesService } from "./disputes.service.js";
import {
  AttachDisputeFileBodyDto,
  AssignDisputeBodyDto,
  DisputeListQueryDto,
  DisputeMessageBodyDto,
  DisputeStatusChangeBodyDto,
  OpenDisputeBodyDto
} from "./dto.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";

@ApiTags("Disputes")
@ApiBearerAuth()
@Controller("admin/disputes")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminDisputesController {
  constructor(private readonly disputes: DisputesService) {}

  @Get()
  @Permissions("admin.disputes.read")
  @ApiOperation({ summary: "List disputes" })
  async list(@Query() query: DisputeListQueryDto) {
    const result = await this.disputes.list(query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  @Get(":id")
  @Permissions("admin.disputes.read")
  @ApiOperation({ summary: "Get dispute detail" })
  async detail(@Param("id") id: string) {
    // Le back-office voit tout, commentaires internes compris.
    return ok(await this.disputes.findById(id, true));
  }

  // POST /admin/disputes  { missionId, reason, description? } — ouvrir un litige.
  @Post()
  @Permissions("admin.disputes.manage")
  @ApiOperation({ summary: "Open a dispute" })
  async open(@Body() body: OpenDisputeBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.disputes.open(body, req.user?.id), undefined, "Dispute opened");
  }

  // PATCH /admin/disputes/:id/assign  { assignedTo }
  @Patch(":id/assign")
  @Permissions("admin.disputes.manage")
  @ApiOperation({ summary: "Assign dispute" })
  async assign(@Param("id") id: string, @Body() body: AssignDisputeBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.disputes.assign(id, body.assignedTo, req.user?.id));
  }

  // PATCH /admin/disputes/:id/status  { status, reason?, decision? }
  @Patch(":id/status")
  @Permissions("admin.disputes.manage")
  @ApiOperation({ summary: "Change dispute status" })
  async changeStatus(
    @Param("id") id: string,
    @Body() body: DisputeStatusChangeBodyDto,
    @Req() req: AuthenticatedRequest
  ) {
    return ok(await this.disputes.changeStatus(id, body.status, body.reason, body.decision, req.user?.id));
  }

  // POST /admin/disputes/:id/messages  { message } — ajouter un message au litige.
  @Post(":id/messages")
  @HttpCode(200)
  @Permissions("admin.disputes.manage")
  @ApiOperation({ summary: "Add a message to a dispute" })
  async addMessage(@Param("id") id: string, @Body() body: DisputeMessageBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.disputes.addMessage(id, body.message, req.user?.id, body.internalOnly ?? false));
  }

  // POST /admin/disputes/:id/files — rattache une preuve déjà téléversée.
  @Post(":id/files")
  @Permissions("admin.disputes.manage")
  @ApiOperation({ summary: "Attach an evidence file to a dispute" })
  async attachFile(@Param("id") id: string, @Body() body: AttachDisputeFileBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.disputes.attachFile(id, body.fileId, req.user?.id), undefined, "Preuve rattachée");
  }
}
