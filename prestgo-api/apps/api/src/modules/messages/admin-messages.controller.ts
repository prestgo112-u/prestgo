import { Controller, Get, Param, Query, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { MessagesService } from "./messages.service.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";
import { PaginationQueryDto } from "../../common/dto/pagination.dto.js";

@ApiTags("Messages")
@ApiBearerAuth()
@Controller("admin/messages")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminMessagesController {
  constructor(private readonly messages: MessagesService) {}

  // GET /admin/messages/threads — liste des fils de discussion.
  @Get("threads")
  @Permissions("admin.messages.read")
  @ApiOperation({ summary: "List message threads" })
  async listThreads(@Query() query: PaginationQueryDto) {
    const result = await this.messages.listThreads(query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  // GET /admin/messages/threads/:id — détail d'un fil (ses messages).
  @Get("threads/:id")
  @Permissions("admin.messages.read")
  @ApiOperation({ summary: "Get thread detail" })
  async threadDetail(@Param("id") id: string) {
    return ok(await this.messages.threadDetail(id));
  }
}
