import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import { SettingsService } from "../settings/settings.service.js";
import { MAX_PORTFOLIO_ITEMS, MAX_PROVIDER_ZONES, SETTING, SETTING_DEFAULT } from "../settings/settings.keys.js";
import { buildChecklist, checklistErrors, isChecklistComplete } from "./provider-checklist.js";

/**
 * Espace prestataire en libre-service (§5 et §6).
 *
 * Ce service corrige l'inversion de rôles du workflow §6.1 : jusqu'ici, seul un
 * agent pouvait créer un profil et joindre des justificatifs à la place du
 * prestataire. C'était contraire au processus voulu — le prestataire construit
 * et soumet son dossier, l'agent décide.
 *
 * La décision reste entièrement du côté admin : les seules transitions ouvertes
 * ici sont `profile_incomplete → pending_review` et
 * `changes_requested → pending_review`.
 */
@Injectable()
export class ProviderSelfService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly settings: SettingsService
  ) {}

  /** Crée le profil prestataire du compte connecté. */
  async createProfile(userId: string, dto: { publicName: string; bio?: string; experienceYears?: number }) {
    const existing = await this.prisma.providerProfile.findUnique({ where: { userId }, select: { id: true } });
    if (existing) {
      throw new ConflictException("Ce compte a déjà un profil prestataire");
    }

    const profile = await this.prisma.providerProfile.create({
      data: {
        userId,
        publicName: dto.publicName.trim(),
        bio: dto.bio?.trim(),
        experienceYears: dto.experienceYears,
        // Le dossier naît incomplet : c'est l'état de départ du §5, il ne
        // devient visible des agents qu'à la soumission.
        validationStatus: "profile_incomplete"
      }
    });

    await this.audit.record({
      actorId: userId,
      action: "providers.me.create",
      entity: "ProviderProfile",
      entityId: profile.id,
      newValue: { publicName: profile.publicName }
    });

    return this.overview(profile.id);
  }

  async updateProfile(
    providerId: string,
    actorId: string,
    dto: {
      publicName?: string;
      bio?: string;
      experienceYears?: number;
      availabilityStatus?: string;
      avatarFileId?: string;
    }
  ) {
    const existing = await this.prisma.providerProfile.findUniqueOrThrow({ where: { id: providerId } });

    // Un dossier en cours d'instruction n'est plus modifiable sur le FOND :
    // changer le nom public sous les yeux de l'agent qui l'examine ferait
    // porter sa décision sur autre chose que ce qu'il a lu.
    //
    // La disponibilité, elle, reste modifiable en permanence : c'est un
    // interrupteur d'exploitation (« je ne prends plus de mission »), sans
    // rapport avec la décision de validation.
    const changesIdentity =
      dto.publicName !== undefined ||
      dto.bio !== undefined ||
      dto.experienceYears !== undefined ||
      dto.avatarFileId !== undefined;

    if (changesIdentity && existing.validationStatus === "pending_review") {
      throw new BadRequestException("Votre dossier est en cours de vérification : il n'est plus modifiable");
    }

    // L'avatar devient public : c'est la photo affichée dans les résultats de
    // recherche. Comme pour le portfolio, le fichier doit appartenir au
    // prestataire — sinon on publierait l'image de quelqu'un d'autre.
    if (dto.avatarFileId) {
      const file = await this.prisma.file.findFirst({
        where: { id: dto.avatarFileId, ownerId: actorId, disabledAt: null },
        select: { id: true, mimeType: true }
      });
      if (!file) {
        throw new NotFoundException("Fichier introuvable ou ne vous appartenant pas");
      }
      if (!file.mimeType.startsWith("image/")) {
        throw new BadRequestException("La photo de profil doit être une image");
      }
      await this.prisma.file.update({ where: { id: file.id }, data: { visibility: "public" } });
    }

    await this.prisma.providerProfile.update({
      where: { id: providerId },
      data: {
        publicName: dto.publicName?.trim() ?? existing.publicName,
        bio: dto.bio?.trim() ?? existing.bio,
        experienceYears: dto.experienceYears ?? existing.experienceYears,
        availabilityStatus: dto.availabilityStatus ?? existing.availabilityStatus,
        avatarFileId: dto.avatarFileId ?? existing.avatarFileId
      }
    });

    await this.audit.record({
      actorId,
      action: "providers.me.update",
      entity: "ProviderProfile",
      entityId: providerId,
      oldValue: { publicName: existing.publicName, bio: existing.bio, experienceYears: existing.experienceYears },
      newValue: dto
    });

    return this.overview(providerId);
  }

  /**
   * Vue « mon dossier » : profil, statut, checklist, motif de refus.
   *
   * Le motif de la dernière décision est renvoyé au prestataire lui-même —
   * c'est ce qui lui permet de corriger. Les notes internes des agents, elles,
   * ne sortent jamais d'ici.
   */
  async overview(providerId: string) {
    const provider = await this.prisma.providerProfile.findUnique({
      where: { id: providerId },
      select: {
        id: true,
        publicName: true,
        bio: true,
        experienceYears: true,
        validationStatus: true,
        availabilityStatus: true,
        score: true,
        reviewsCount: true,
        rejectionReason: true,
        resubmissionBlocked: true,
        submittedAt: true,
        createdAt: true,
        _count: { select: { zones: true } }
      }
    });
    if (!provider) {
      throw new NotFoundException("Profil prestataire introuvable");
    }

    const [bookableServices, availabilities, documents, requiredDocumentTypes] = await Promise.all([
      this.prisma.providerService.count({
        where: { providerId, active: true, packs: { some: { active: true } } }
      }),
      this.prisma.providerAvailability.count({ where: { providerId, active: true } }),
      this.prisma.providerDocument.findMany({
        where: { providerId },
        select: { type: true, status: true, fileId: true },
        orderBy: { createdAt: "desc" }
      }),
      this.settings.getStringList(
        SETTING.providerRequiredDocumentTypes,
        [...SETTING_DEFAULT.providerRequiredDocumentTypes]
      )
    ]);

    // Un document REJETÉ ne compte pas comme fourni : sinon la checklist
    // resterait verte alors que l'agent attend un nouveau justificatif.
    const providedDocumentTypes = [
      ...new Set(documents.filter((doc) => doc.fileId && doc.status !== "rejected").map((doc) => doc.type))
    ];

    const checklist = buildChecklist({
      publicName: provider.publicName,
      bio: provider.bio,
      bookableServices,
      zones: provider._count.zones,
      availabilities,
      requiredDocumentTypes,
      providedDocumentTypes
    });

    const complete = isChecklistComplete(checklist);
    const submittable = provider.validationStatus === "profile_incomplete" || provider.validationStatus === "changes_requested";

    return {
      id: provider.id,
      publicName: provider.publicName,
      bio: provider.bio,
      experienceYears: provider.experienceYears,
      validationStatus: provider.validationStatus,
      availabilityStatus: provider.availabilityStatus,
      score: Math.round(provider.score * 10) / 10,
      reviewsCount: provider.reviewsCount,
      checklist,
      requiredDocumentTypes,
      rejectionReason: provider.rejectionReason,
      resubmissionBlocked: provider.resubmissionBlocked,
      submittedAt: provider.submittedAt,
      canSubmit: complete && submittable && !provider.resubmissionBlocked,
      createdAt: provider.createdAt
    };
  }

  /**
   * Soumet le dossier à la vérification (§5).
   *
   * Trois refus possibles, tous explicites :
   *   - checklist incomplète (le détail part dans `errors`) ;
   *   - statut incompatible (un dossier déjà approuvé n'a rien à re-soumettre) ;
   *   - re-soumission bloquée par un agent.
   */
  async submit(providerId: string, actorId: string) {
    const overview = await this.overview(providerId);

    if (overview.resubmissionBlocked) {
      throw new ForbiddenException("La re-soumission de votre dossier a été bloquée. Contactez le support.");
    }

    if (overview.validationStatus !== "profile_incomplete" && overview.validationStatus !== "changes_requested") {
      throw new BadRequestException(
        `Votre dossier est au statut « ${overview.validationStatus} » : il n'y a rien à soumettre.`
      );
    }

    if (!isChecklistComplete(overview.checklist)) {
      throw new BadRequestException({
        message: "Votre dossier n'est pas complet",
        errors: checklistErrors(overview.checklist)
      });
    }

    await this.prisma.providerProfile.update({
      where: { id: providerId },
      data: {
        validationStatus: "pending_review",
        submittedAt: new Date(),
        // Le motif précédent n'a plus lieu d'être : il portait sur une version
        // du dossier qui vient d'être corrigée.
        rejectionReason: null
      }
    });

    await this.audit.record({
      actorId,
      action: "providers.me.submit",
      entity: "ProviderProfile",
      entityId: providerId,
      oldValue: { validationStatus: overview.validationStatus },
      newValue: { validationStatus: "pending_review" }
    });

    return this.overview(providerId);
  }

  // === Services déclarés par le prestataire (§5) ===

  async listServices(providerId: string) {
    return this.prisma.providerService.findMany({
      where: { providerId },
      orderBy: { createdAt: "desc" },
      select: {
        id: true,
        title: true,
        description: true,
        active: true,
        createdAt: true,
        serviceType: { select: { id: true, name: true, category: { select: { id: true, name: true } } } },
        packs: {
          select: { id: true, title: true, price: true, durationMinutes: true, active: true },
          orderBy: { price: "asc" }
        }
      }
    });
  }

  async createService(
    providerId: string,
    actorId: string,
    dto: { serviceTypeId: string; title: string; description?: string }
  ) {
    // Le type de service doit exister ET être actif : rattacher une offre à une
    // catégorie retirée du catalogue la rendrait invisible côté client.
    const serviceType = await this.prisma.serviceType.findFirst({
      where: { id: dto.serviceTypeId, active: true, category: { active: true } },
      select: { id: true }
    });
    if (!serviceType) {
      throw new NotFoundException("Type de service introuvable ou inactif");
    }

    const duplicate = await this.prisma.providerService.findFirst({
      where: { providerId, serviceTypeId: dto.serviceTypeId, active: true },
      select: { id: true }
    });
    if (duplicate) {
      throw new ConflictException("Vous proposez déjà un service actif de ce type");
    }

    const service = await this.prisma.providerService.create({
      data: {
        providerId,
        serviceTypeId: dto.serviceTypeId,
        title: dto.title.trim(),
        description: dto.description?.trim()
      }
    });

    await this.audit.record({
      actorId,
      action: "providers.me.services.create",
      entity: "ProviderService",
      entityId: service.id,
      newValue: { providerId, title: service.title }
    });

    return service;
  }

  async updateService(
    providerId: string,
    actorId: string,
    serviceId: string,
    dto: { title?: string; description?: string; active?: boolean }
  ) {
    // Recherche par le COUPLE (id, prestataire) : c'est ce qui empêche de
    // modifier le service d'un confrère en changeant l'identifiant de l'URL.
    const existing = await this.prisma.providerService.findFirst({ where: { id: serviceId, providerId } });
    if (!existing) {
      throw new NotFoundException("Service introuvable");
    }

    const service = await this.prisma.providerService.update({
      where: { id: serviceId },
      data: {
        title: dto.title?.trim() ?? existing.title,
        description: dto.description?.trim() ?? existing.description,
        active: dto.active ?? existing.active
      }
    });

    await this.audit.record({
      actorId,
      action: "providers.me.services.update",
      entity: "ProviderService",
      entityId: serviceId,
      oldValue: { title: existing.title, active: existing.active },
      newValue: { title: service.title, active: service.active }
    });

    return service;
  }

  // === Zones d'intervention (§6) ===

  async listZones(providerId: string) {
    const rows = await this.prisma.providerZone.findMany({
      where: { providerId },
      select: {
        zone: {
          select: {
            id: true,
            name: true,
            latitude: true,
            longitude: true,
            radiusKm: true,
            active: true,
            city: { select: { id: true, name: true } }
          }
        }
      }
    });
    return rows.map((row) => row.zone);
  }

  /**
   * Remplace la liste des zones (`PUT`, tout ou rien).
   *
   * Un `PUT` et non une suite d'ajouts : l'interface est une liste de cases à
   * cocher, l'appelant envoie donc l'état voulu. Cela évite aussi les états
   * intermédiaires incohérents si un ajout échoue au milieu d'une série.
   */
  async replaceZones(providerId: string, actorId: string, zoneIds: string[]) {
    const unique = [...new Set(zoneIds)];

    if (unique.length > MAX_PROVIDER_ZONES) {
      throw new BadRequestException(`Vous ne pouvez pas couvrir plus de ${MAX_PROVIDER_ZONES} zones`);
    }

    // Tout est validé AVANT d'écrire : sinon une zone inactive en fin de liste
    // laisserait le prestataire avec un périmètre à moitié effacé.
    if (unique.length > 0) {
      const valid = await this.prisma.zone.findMany({
        where: { id: { in: unique }, active: true },
        select: { id: true }
      });
      if (valid.length !== unique.length) {
        const found = new Set(valid.map((zone) => zone.id));
        const missing = unique.filter((id) => !found.has(id));
        throw new BadRequestException(`Zone inconnue ou inactive : ${missing.join(", ")}`);
      }
    }

    await this.prisma.$transaction([
      this.prisma.providerZone.deleteMany({ where: { providerId } }),
      this.prisma.providerZone.createMany({
        data: unique.map((zoneId) => ({ providerId, zoneId }))
      })
    ]);

    await this.audit.record({
      actorId,
      action: "providers.me.zones.replace",
      entity: "ProviderProfile",
      entityId: providerId,
      newValue: { zones: unique.length }
    });

    return this.listZones(providerId);
  }

  // === Portfolio (§6) ===

  async listPortfolio(providerId: string) {
    return this.prisma.providerPortfolioItem.findMany({
      where: { providerId },
      orderBy: [{ displayOrder: "asc" }, { createdAt: "desc" }],
      select: {
        id: true,
        title: true,
        description: true,
        displayOrder: true,
        createdAt: true,
        file: { select: { id: true, originalName: true, mimeType: true, visibility: true } }
      }
    });
  }

  /**
   * Ajoute une réalisation.
   *
   * Le fichier doit APPARTENIR au prestataire : sans ce contrôle, on pourrait
   * exposer publiquement le justificatif d'identité de quelqu'un d'autre en
   * indiquant simplement son identifiant de fichier.
   */
  async addPortfolioItem(
    providerId: string,
    actorId: string,
    dto: { fileId: string; title?: string; description?: string; displayOrder?: number }
  ) {
    const count = await this.prisma.providerPortfolioItem.count({ where: { providerId } });
    if (count >= MAX_PORTFOLIO_ITEMS) {
      throw new BadRequestException(`Votre portfolio est limité à ${MAX_PORTFOLIO_ITEMS} réalisations`);
    }

    const file = await this.prisma.file.findFirst({
      where: { id: dto.fileId, ownerId: actorId, disabledAt: null },
      select: { id: true, mimeType: true }
    });
    if (!file) {
      throw new NotFoundException("Fichier introuvable ou ne vous appartenant pas");
    }
    if (!file.mimeType.startsWith("image/")) {
      throw new BadRequestException("Une réalisation doit être une image");
    }

    // Le portfolio est la vitrine : la visibilité passe à « public », ce qui
    // est une décision volontaire du prestataire, pas un effet de bord du dépôt.
    await this.prisma.file.update({ where: { id: file.id }, data: { visibility: "public" } });

    const item = await this.prisma.providerPortfolioItem.create({
      data: {
        providerId,
        fileId: file.id,
        title: dto.title?.trim(),
        description: dto.description?.trim(),
        displayOrder: dto.displayOrder ?? count
      }
    });

    await this.audit.record({
      actorId,
      action: "providers.me.portfolio.add",
      entity: "ProviderPortfolioItem",
      entityId: item.id,
      newValue: { providerId, fileId: file.id }
    });

    return item;
  }

  async updatePortfolioItem(
    providerId: string,
    actorId: string,
    itemId: string,
    dto: { title?: string; description?: string; displayOrder?: number }
  ) {
    const existing = await this.prisma.providerPortfolioItem.findFirst({ where: { id: itemId, providerId } });
    if (!existing) {
      throw new NotFoundException("Réalisation introuvable");
    }

    const item = await this.prisma.providerPortfolioItem.update({
      where: { id: itemId },
      data: {
        title: dto.title?.trim() ?? existing.title,
        description: dto.description?.trim() ?? existing.description,
        displayOrder: dto.displayOrder ?? existing.displayOrder
      }
    });

    await this.audit.record({
      actorId,
      action: "providers.me.portfolio.update",
      entity: "ProviderPortfolioItem",
      entityId: itemId,
      newValue: dto
    });

    return item;
  }

  async removePortfolioItem(providerId: string, actorId: string, itemId: string) {
    const existing = await this.prisma.providerPortfolioItem.findFirst({
      where: { id: itemId, providerId },
      select: { id: true, fileId: true }
    });
    if (!existing) {
      throw new NotFoundException("Réalisation introuvable");
    }

    await this.prisma.$transaction([
      this.prisma.providerPortfolioItem.delete({ where: { id: itemId } }),
      // L'image redevient restreinte : retirée de la vitrine, elle n'a plus de
      // raison d'être lisible par tout le monde.
      this.prisma.file.update({ where: { id: existing.fileId }, data: { visibility: "restricted" } })
    ]);

    await this.audit.record({
      actorId,
      action: "providers.me.portfolio.remove",
      entity: "ProviderPortfolioItem",
      entityId: itemId
    });

    return { removed: true };
  }
}
