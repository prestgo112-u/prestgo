import { Body, Controller, Delete, Get, Param, Patch, Post, Req, UseGuards } from "@nestjs/common";
import { ApiTags, ApiOperation, ApiBearerAuth } from "@nestjs/swagger";
import { CatalogService } from "./catalog.service.js";
import { Permissions } from "../../common/decorators/permissions.decorator.js";
import { PermissionsGuard } from "../../common/guards/permissions.guard.js";
import type { AuthenticatedRequest } from "../../common/guards/permissions.guard.js";
import { JwtAuthGuard } from "../auth/jwt-auth.guard.js";
import { ok } from "../../common/contracts/api-response.js";
import {
  AttachProviderServiceBodyDto,
  CreateCategoryBodyDto,
  CreateServiceTypeBodyDto,
  UpdateCategoryBodyDto,
  UpdateServiceTypeBodyDto
} from "./dto.js";

@ApiTags("Catalog")
@ApiBearerAuth()
@Controller("admin")
@UseGuards(JwtAuthGuard, PermissionsGuard)
export class AdminCatalogController {
  constructor(private readonly catalog: CatalogService) {}

  // GET /admin/categories — catégories + leurs types de service.
  @Get("categories")
  @Permissions("admin.catalog.read")
  @ApiOperation({ summary: "List catalog categories" })
  async listCategories() {
    return ok(await this.catalog.listCategories());
  }

  @Post("categories")
  @Permissions("admin.catalog.manage")
  @ApiOperation({ summary: "Create category" })
  async createCategory(@Body() body: CreateCategoryBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.catalog.createCategory(body, req.user?.id), undefined, "Category created");
  }

  @Patch("categories/:id")
  @Permissions("admin.catalog.manage")
  @ApiOperation({ summary: "Update or (de)activate a category" })
  async updateCategory(@Param("id") id: string, @Body() body: UpdateCategoryBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.catalog.updateCategory(id, body, req.user?.id));
  }

  // DELETE /admin/categories/:id — désactive la catégorie.
  // On ne supprime jamais vraiment : les missions passées y font référence.
  @Delete("categories/:id")
  @Permissions("admin.catalog.manage")
  @ApiOperation({ summary: "Deactivate a category" })
  async deactivateCategory(@Param("id") id: string, @Req() req: AuthenticatedRequest) {
    return ok(await this.catalog.deactivateCategory(id, req.user?.id), undefined, "Catégorie désactivée");
  }

  @Post("service-types")
  @Permissions("admin.catalog.manage")
  @ApiOperation({ summary: "Create a service type" })
  async createServiceType(@Body() body: CreateServiceTypeBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.catalog.createServiceType(body, req.user?.id), undefined, "Service type created");
  }

  @Patch("service-types/:id")
  @Permissions("admin.catalog.manage")
  @ApiOperation({ summary: "Update or (de)activate a service type" })
  async updateServiceType(@Param("id") id: string, @Body() body: UpdateServiceTypeBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.catalog.updateServiceType(id, body, req.user?.id));
  }

  @Post("provider-services")
  @Permissions("admin.catalog.manage")
  @ApiOperation({ summary: "Attach a service type to a provider" })
  async attachProviderService(@Body() body: AttachProviderServiceBodyDto, @Req() req: AuthenticatedRequest) {
    return ok(await this.catalog.attachProviderService(body, req.user?.id), undefined, "Provider service created");
  }
}
