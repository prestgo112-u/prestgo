import { Controller, Get, Query, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { AuditService } from "./audit.service.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";
import { AuditListQueryDto } from "./dto.js";

@ApiTags("Audit")
@ApiBearerAuth()
@Controller("admin/audit-logs")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminAuditController {
  constructor(private readonly audit: AuditService) {}

  // GET /admin/audit-logs?page=1&entity=Mission&action=... — journal filtrable.
  @Get()
  @Permissions("audit.read")
  @ApiOperation({ summary: "List audit logs with filters" })
  async list(@Query() query: AuditListQueryDto) {
    const result = await this.audit.listPaginated(query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }
}
