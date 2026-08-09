import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import { SettingsService } from "../settings/settings.service.js";
import { SETTING, SETTING_DEFAULT } from "../settings/settings.keys.js";

/**
 * Dépôt de justificatifs PAR LE PRESTATAIRE (§6).
 *
 * C'est la correction de l'inversion du §6.1 : jusqu'ici, seul un agent
 * pouvait joindre un fichier — autrement dit, le prestataire devait envoyer sa
 * pièce d'identité par un canal hors application, et un humain la déposait à sa
 * place. La route admin est CONSERVÉE comme outil de support (dépannage
 * téléphonique), elle n'est simplement plus le seul chemin.
 */
@Injectable()
export class ProviderDocumentsSelfService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly settings: SettingsService
  ) {}

  /**
   * Mes documents, toutes versions confondues.
   *
   * Le motif de rejet est renvoyé : c'est l'information dont le prestataire a
   * besoin pour fournir le bon document au deuxième essai. En revanche, ni
   * l'identité du relecteur ni les notes internes ne sortent d'ici.
   */
  async list(providerId: string) {
    const [documents, requiredTypes] = await Promise.all([
      this.prisma.providerDocument.findMany({
        where: { providerId },
        orderBy: [{ type: "asc" }, { version: "desc" }],
        select: {
          id: true,
          type: true,
          status: true,
          version: true,
          rejectionReason: true,
          reviewedAt: true,
          createdAt: true,
          file: { select: { id: true, originalName: true, mimeType: true, size: true } }
        }
      }),
      this.settings.getStringList(
        SETTING.providerRequiredDocumentTypes,
        [...SETTING_DEFAULT.providerRequiredDocumentTypes]
      )
    ]);

    // La version courante d'un type est la plus élevée. Les précédentes restent
    // consultables : elles expliquent l'historique des décisions.
    const currentByType = new Map<string, (typeof documents)[number]>();
    for (const document of documents) {
      if (!currentByType.has(document.type)) {
        currentByType.set(document.type, document);
      }
    }

    return {
      requiredTypes,
      missingTypes: requiredTypes.filter((type) => {
        const current = currentByType.get(type);
        return !current || !current.file || current.status === "rejected";
      }),
      documents,
      current: [...currentByType.values()]
    };
  }

  /**
   * Soumet un justificatif.
   *
   * Le fichier a déjà été envoyé via `POST /files/upload` ; on ne fait ici que
   * le rattacher. Deux contrôles portent tout le poids :
   *   - le fichier doit APPARTENIR au compte connecté, sinon on pourrait
   *     rattacher à son dossier la pièce d'identité d'un inconnu ;
   *   - sa visibilité passe à `sensitive`, quelle qu'ait été celle du dépôt :
   *     une pièce d'identité ne doit jamais rester lisible largement.
   *
   * Re-soumettre ne remplace pas la ligne précédente : on crée une NOUVELLE
   * version. L'agent voit ainsi ce qui avait été rejeté à côté du nouveau
   * document.
   */
  async submit(providerId: string, actorId: string, dto: { type: string; fileId: string }) {
    const type = dto.type.trim();
    if (!type) {
      throw new BadRequestException("Le type de document est obligatoire");
    }

    const file = await this.prisma.file.findFirst({
      where: { id: dto.fileId, ownerId: actorId, disabledAt: null },
      select: { id: true, originalName: true, mimeType: true }
    });
    if (!file) {
      throw new NotFoundException("Fichier introuvable ou ne vous appartenant pas");
    }

    const last = await this.prisma.providerDocument.findFirst({
      where: { providerId, type },
      orderBy: { version: "desc" },
      select: { id: true, version: true, status: true }
    });

    // Un document déjà approuvé n'a pas à être remplacé : le re-soumettre
    // remettrait tout le dossier en file d'attente sans raison.
    if (last?.status === "approved") {
      throw new BadRequestException(`Votre justificatif « ${type} » est déjà validé`);
    }

    const document = await this.prisma.$transaction(async (tx) => {
      await tx.file.update({ where: { id: file.id }, data: { visibility: "sensitive" } });
      return tx.providerDocument.create({
        data: {
          providerId,
          type,
          fileId: file.id,
          status: "pending",
          version: (last?.version ?? 0) + 1
        },
        select: {
          id: true,
          type: true,
          status: true,
          version: true,
          createdAt: true,
          file: { select: { id: true, originalName: true, mimeType: true } }
        }
      });
    });

    // Un dossier déjà soumis retourne en file d'attente : la décision de
    // l'agent portait sur l'ancien justificatif, elle n'est plus à jour.
    const provider = await this.prisma.providerProfile.findUniqueOrThrow({
      where: { id: providerId },
      select: { validationStatus: true }
    });
    if (provider.validationStatus === "changes_requested") {
      await this.prisma.providerProfile.update({
        where: { id: providerId },
        data: { validationStatus: "pending_review", submittedAt: new Date(), rejectionReason: null }
      });
    }

    await this.audit.record({
      actorId,
      action: "providers.me.documents.submit",
      entity: "ProviderDocument",
      entityId: document.id,
      newValue: { providerId, type, version: document.version, fileId: file.id }
    });

    return document;
  }
}
