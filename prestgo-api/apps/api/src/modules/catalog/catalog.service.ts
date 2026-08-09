import { Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";

@Injectable()
export class CatalogService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  // Liste les catégories avec leurs types de service.
  async listCategories() {
    return this.prisma.catalogCategory.findMany({
      include: { serviceTypes: true },
      orderBy: [{ displayOrder: "asc" }, { name: "asc" }]
    });
  }

  /**
   * Catalogue public : uniquement ce qui est ACTIF.
   *
   * Une catégorie désactivée reste en base pour l'historique des missions
   * passées, mais elle ne doit plus apparaître dans l'application publique.
   */
  async listPublicCategories() {
    return this.prisma.catalogCategory.findMany({
      where: { active: true },
      include: {
        serviceTypes: {
          where: { active: true },
          select: { id: true, name: true, slug: true, description: true },
          orderBy: { name: "asc" }
        }
      },
      orderBy: [{ displayOrder: "asc" }, { name: "asc" }]
    });
  }

  // Formules vendables d'un prestataire (vue publique : uniquement les actives).
  async listProviderPacks(providerId: string) {
    const packs = await this.prisma.servicePack.findMany({
      where: { active: true, providerService: { providerId, active: true } },
      include: { providerService: { select: { id: true, title: true, serviceType: { select: { name: true } } } } },
      orderBy: { price: "asc" }
    });

    return packs.map((pack) => ({
      id: pack.id,
      title: pack.title,
      description: pack.description,
      price: pack.price,
      durationMinutes: pack.durationMinutes,
      serviceId: pack.providerService.id,
      serviceTitle: pack.providerService.title,
      serviceType: pack.providerService.serviceType.name
    }));
  }

  /**
   * Un prestataire crée une de ses formules.
   *
   * Le contrôle essentiel est ici : on vérifie que le `providerServiceId`
   * appartient bien AU prestataire connecté. Sans cela, n'importe quel
   * prestataire pourrait ajouter une formule dans le catalogue d'un confrère.
   */
  async createPackForProvider(
    providerId: string,
    dto: { providerServiceId: string; title: string; description?: string; price: number; durationMinutes: number },
    actorId?: string
  ) {
    const service = await this.prisma.providerService.findFirst({
      where: { id: dto.providerServiceId, providerId }
    });
    if (!service) {
      throw new NotFoundException("Service introuvable pour ce prestataire");
    }

    const pack = await this.prisma.servicePack.create({
      data: {
        providerServiceId: service.id,
        title: dto.title,
        description: dto.description,
        price: dto.price,
        durationMinutes: dto.durationMinutes
      }
    });

    await this.audit.record({
      actorId,
      action: "providers.service-pack.create",
      entity: "ServicePack",
      entityId: pack.id,
      newValue: { providerId, ...dto }
    });
    return pack;
  }

  // Un prestataire modifie une de SES formules (même contrôle d'appartenance).
  async updatePackForProvider(
    providerId: string,
    packId: string,
    dto: { title?: string; description?: string; price?: number; durationMinutes?: number; active?: boolean },
    actorId?: string
  ) {
    const existing = await this.prisma.servicePack.findFirst({
      where: { id: packId, providerService: { providerId } }
    });
    if (!existing) {
      throw new NotFoundException("Formule introuvable pour ce prestataire");
    }

    const pack = await this.prisma.servicePack.update({
      where: { id: packId },
      data: {
        title: dto.title ?? existing.title,
        description: dto.description ?? existing.description,
        price: dto.price ?? existing.price,
        durationMinutes: dto.durationMinutes ?? existing.durationMinutes,
        active: dto.active ?? existing.active
      }
    });

    await this.audit.record({
      actorId,
      action: "providers.service-pack.update",
      entity: "ServicePack",
      entityId: packId,
      oldValue: { price: existing.price, active: existing.active },
      newValue: dto
    });
    return pack;
  }

  /**
   * Options payantes d'une formule, côté prestataire.
   *
   * Le §8 permet au client de choisir des `optionIds` à la réservation. Sans
   * route pour les créer, la fonctionnalité serait inatteignable : le
   * prestataire n'aurait aucun moyen de proposer un supplément.
   *
   * Même contrôle d'appartenance que pour les formules : la vérification porte
   * sur le couple (formule, prestataire).
   */
  async listPackOptionsForProvider(providerId: string, packId: string) {
    const pack = await this.prisma.servicePack.findFirst({
      where: { id: packId, providerService: { providerId } },
      select: { id: true }
    });
    if (!pack) {
      throw new NotFoundException("Formule introuvable pour ce prestataire");
    }

    return this.prisma.servicePackOption.findMany({
      where: { packId },
      orderBy: { price: "asc" },
      select: { id: true, title: true, price: true, durationMinutes: true, active: true, createdAt: true }
    });
  }

  async createPackOptionForProvider(
    providerId: string,
    packId: string,
    dto: { title: string; price: number; durationMinutes?: number },
    actorId?: string
  ) {
    const pack = await this.prisma.servicePack.findFirst({
      where: { id: packId, providerService: { providerId } },
      select: { id: true }
    });
    if (!pack) {
      throw new NotFoundException("Formule introuvable pour ce prestataire");
    }

    const option = await this.prisma.servicePackOption.create({
      data: {
        packId,
        title: dto.title.trim(),
        price: dto.price,
        durationMinutes: dto.durationMinutes ?? 0
      }
    });

    await this.audit.record({
      actorId,
      action: "providers.service-pack.option.create",
      entity: "ServicePackOption",
      entityId: option.id,
      newValue: { providerId, packId, ...dto }
    });

    return option;
  }

  async updatePackOptionForProvider(
    providerId: string,
    optionId: string,
    dto: { title?: string; price?: number; durationMinutes?: number; active?: boolean },
    actorId?: string
  ) {
    const existing = await this.prisma.servicePackOption.findFirst({
      where: { id: optionId, pack: { providerService: { providerId } } }
    });
    if (!existing) {
      throw new NotFoundException("Option introuvable pour ce prestataire");
    }

    const option = await this.prisma.servicePackOption.update({
      where: { id: optionId },
      data: {
        title: dto.title?.trim() ?? existing.title,
        price: dto.price ?? existing.price,
        durationMinutes: dto.durationMinutes ?? existing.durationMinutes,
        active: dto.active ?? existing.active
      }
    });

    await this.audit.record({
      actorId,
      action: "providers.service-pack.option.update",
      entity: "ServicePackOption",
      entityId: optionId,
      oldValue: { price: existing.price, active: existing.active },
      newValue: dto
    });

    return option;
  }

  /**
   * Désactive une catégorie (CDC : `DELETE /admin/categories/{id}` = « Désactiver »).
   *
   * On ne supprime jamais réellement : les missions passées y font référence.
   */
  async deactivateCategory(id: string, actorId?: string) {
    const existing = await this.prisma.catalogCategory.findUnique({ where: { id } });
    if (!existing) {
      throw new NotFoundException("Catégorie introuvable");
    }

    const category = await this.prisma.catalogCategory.update({ where: { id }, data: { active: false } });
    await this.audit.record({
      actorId,
      action: "admin.catalog.category.deactivate",
      entity: "CatalogCategory",
      entityId: id,
      oldValue: { active: existing.active },
      newValue: { active: false }
    });
    return category;
  }

  // Crée une catégorie.
  async createCategory(dto: { name: string; slug: string; description?: string; displayOrder?: number }, actorId?: string) {
    const category = await this.prisma.catalogCategory.create({
      data: { name: dto.name, slug: dto.slug, description: dto.description, displayOrder: dto.displayOrder ?? 0 }
    });
    await this.audit.record({ actorId, action: "admin.catalog.category.create", entity: "CatalogCategory", entityId: category.id, newValue: dto });
    return category;
  }

  // Met à jour une catégorie (permet aussi de l'activer/désactiver).
  // Désactiver garde la catégorie dans l'historique mais la rend indisponible.
  async updateCategory(id: string, dto: { name?: string; description?: string; active?: boolean; displayOrder?: number }, actorId?: string) {
    const existing = await this.prisma.catalogCategory.findUnique({ where: { id } });
    if (!existing) {
      throw new NotFoundException("Catégorie introuvable");
    }
    const category = await this.prisma.catalogCategory.update({
      where: { id },
      data: { name: dto.name ?? existing.name, description: dto.description ?? existing.description, active: dto.active ?? existing.active, displayOrder: dto.displayOrder ?? existing.displayOrder }
    });
    await this.audit.record({ actorId, action: "admin.catalog.category.update", entity: "CatalogCategory", entityId: id, newValue: dto });
    return category;
  }

  // Crée un type de service rattaché à une catégorie.
  async createServiceType(dto: { categoryId: string; name: string; slug: string; description?: string }, actorId?: string) {
    const type = await this.prisma.serviceType.create({
      data: { categoryId: dto.categoryId, name: dto.name, slug: dto.slug, description: dto.description }
    });
    await this.audit.record({ actorId, action: "admin.catalog.type.create", entity: "ServiceType", entityId: type.id, newValue: dto });
    return type;
  }

  // Active/désactive ou renomme un type de service.
  async updateServiceType(id: string, dto: { name?: string; description?: string; active?: boolean }, actorId?: string) {
    const existing = await this.prisma.serviceType.findUnique({ where: { id } });
    if (!existing) {
      throw new NotFoundException("Type de service introuvable");
    }
    const type = await this.prisma.serviceType.update({
      where: { id },
      data: { name: dto.name ?? existing.name, description: dto.description ?? existing.description, active: dto.active ?? existing.active }
    });
    await this.audit.record({ actorId, action: "admin.catalog.type.update", entity: "ServiceType", entityId: id, newValue: dto });
    return type;
  }

  // Rattache un type de service à un prestataire (le prestataire "propose" ce service).
  async attachProviderService(dto: { providerId: string; serviceTypeId: string; title: string; description?: string }, actorId?: string) {
    const service = await this.prisma.providerService.create({
      data: { providerId: dto.providerId, serviceTypeId: dto.serviceTypeId, title: dto.title, description: dto.description }
    });
    await this.audit.record({ actorId, action: "admin.catalog.providerService.create", entity: "ProviderService", entityId: service.id, newValue: dto });
    return service;
  }
}
