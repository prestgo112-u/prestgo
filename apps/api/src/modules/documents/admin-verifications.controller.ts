import {
  BadRequestException,
  Body,
  Controller,
  Get,
  HttpCode,
  Param,
  Post,
  Query,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import { ApiTags, ApiOperation, ApiBearerAuth, ApiConsumes } from "@nestjs/swagger";
import { ProviderDocumentsService } from "./provider-documents.service.js";
import { ALLOWED_MIME_TYPES, MAX_UPLOAD_BYTES } from "../files/files.controller.js";
import { RejectDocumentBodyDto, VerificationQueueQueryDto } from "./dto.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";

// Routes de vérification : /api/v1/admin/verifications/...
@ApiTags("Providers")
@ApiBearerAuth()
@Controller("admin/verifications")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminVerificationsController {
  constructor(private readonly documents: ProviderDocumentsService) {}

  // GET /admin/verifications/providers — la file d'attente transverse :
  // tous les dossiers à traiter, tous prestataires confondus.
  @Get("providers")
  @Permissions("admin.verifications.documents.review")
  @ApiOperation({ summary: "List provider dossiers awaiting verification" })
  async queue(@Query() query: VerificationQueueQueryDto) {
    const result = await this.documents.verificationQueue(query);
    return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
  }

  // GET /admin/verifications/documents/:id — consulter un document soumis.
  @Get("documents/:id")
  @Permissions("admin.verifications.documents.review")
  @ApiOperation({ summary: "Get a submitted document" })
  async findOne(@Param("id") id: string) {
    return ok(await this.documents.findById(id));
  }

  // POST /admin/verifications/documents/:id/file — joindre le justificatif.
  // C'est ce qui permet ensuite de le CONSULTER avant de décider.
  @Post("documents/:id/file")
  @Permissions("admin.verifications.documents.review")
  @ApiOperation({ summary: "Attach the supporting file to a document" })
  @ApiConsumes("multipart/form-data")
  @UseInterceptors(FileInterceptor("file", { limits: { fileSize: MAX_UPLOAD_BYTES } }))
  async attach(
    @Param("id") id: string,
    @UploadedFile() upload: Express.Multer.File | undefined,
    @Req() req: AuthenticatedRequest
  ) {
    if (!upload) {
      throw new BadRequestException("Aucun fichier reçu (champ attendu : « file »)");
    }
    if (!ALLOWED_MIME_TYPES.includes(upload.mimetype)) {
      throw new BadRequestException(`Type de fichier non autorisé : ${upload.mimetype}`);
    }
    return ok(await this.documents.attachFile(id, upload, req.user?.id), undefined, "Justificatif enregistré");
  }

  // POST /admin/verifications/documents/:id/approve
  @Post("documents/:id/approve")
  @HttpCode(200)
  @Permissions("admin.verifications.documents.review")
  @ApiOperation({ summary: "Approve a provider document" })
  async approve(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    await this.documents.approve(id, req.user?.id);
    return ok({ approved: true });
  }

  // POST /admin/verifications/documents/:id/reject  (motif obligatoire)
  @Post("documents/:id/reject")
  @HttpCode(200)
  @Permissions("admin.verifications.documents.review")
  @ApiOperation({ summary: "Reject a provider document with a reason" })
  async reject(@Param("id") id: string, @Body() body: RejectDocumentBodyDto, @Req() req: AuthenticatedRequest) {
    await this.documents.reject(id, body?.reason, req.user?.id);
    return ok({ rejected: true });
  }
}
