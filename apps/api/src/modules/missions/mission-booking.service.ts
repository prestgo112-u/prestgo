import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import type { MissionStatus, Prisma } from "@prisma/client";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { buildOrderBy, type SortAllowList } from "../../common/dto/sorting.js";
import { AuditService } from "../audit/audit.service.js";
import { NOTIFICATION, NotificationEventsService } from "../notifications/notification-events.service.js";
import { SETTING, SETTING_DEFAULT } from "../settings/settings.keys.js";
import { SettingsService } from "../settings/settings.service.js";

export interface CreateMissionInput {
  providerId: string;
  packId: string;
  optionIds?: string[];
  scheduledAt: string;
  addressId: string;
  instructions?: string;
}

/**
 * Création d'une réservation (§8) — le cœur de la boucle de valeur.
 *
 * Toutes les validations sont faites AVANT d'écrire, et l'écriture se fait dans
 * une seule transaction. C'est important : une mission créée à moitié — sans
 * fil de discussion, sans historique, sans notification au prestataire — serait
 * invisible des deux côtés tout en occupant un créneau.
 */
@Injectable()
export class MissionBookingService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService,
    private readonly settings: SettingsService,
    private readonly events: NotificationEventsService
  ) {}

  async create(clientId: string, dto: CreateMissionInput) {
    const scheduledAt = new Date(dto.scheduledAt);
    if (Number.isNaN(scheduledAt.getTime())) {
      throw new BadRequestException("Date d'intervention invalide");
    }

    const minLeadMinutes = await this.settings.getNumber(
      SETTING.missionMinLeadTimeMinutes,
      SETTING_DEFAULT.missionMinLeadTimeMinutes
    );
    const earliest = new Date(Date.now() + minLeadMinutes * 60_000);
    if (scheduledAt < earliest) {
      throw new BadRequestException(
        `Une réservation doit être posée au moins ${minLeadMinutes} minutes à l'avance`
      );
    }

    // --- Prestataire : validé, actif, disponible ---
    const provider = await this.prisma.providerProfile.findFirst({
      where: { id: dto.providerId, validationStatus: "approved", user: { status: "active" } },
      select: {
        id: true,
        userId: true,
        publicName: true,
        availabilityStatus: true,
        zones: { select: { zoneId: true } }
      }
    });
    if (!provider) {
      throw new NotFoundException("Prestataire introuvable ou non disponible à la réservation");
    }
    if (provider.availabilityStatus === "unavailable") {
      throw new BadRequestException("Ce prestataire ne prend pas de réservation actuellement");
    }
    if (provider.userId === clientId) {
      throw new BadRequestException("Vous ne pouvez pas réserver votre propre prestation");
    }

    // --- Formule : active ET appartenant à CE prestataire ---
    // Le second point est essentiel : sans lui, on pourrait réserver chez un
    // prestataire au tarif d'un autre.
    const pack = await this.prisma.servicePack.findFirst({
      where: {
        id: dto.packId,
        active: true,
        providerService: { providerId: provider.id, active: true }
      },
      select: {
        id: true,
        title: true,
        price: true,
        durationMinutes: true,
        options: { where: { active: true }, select: { id: true, title: true, price: true, durationMinutes: true } }
      }
    });
    if (!pack) {
      throw new NotFoundException("Formule introuvable, inactive, ou ne correspondant pas à ce prestataire");
    }

    // --- Options : toutes doivent appartenir à la formule choisie ---
    const requestedOptionIds = [...new Set(dto.optionIds ?? [])];
    const options = pack.options.filter((option) => requestedOptionIds.includes(option.id));
    if (options.length !== requestedOptionIds.length) {
      const known = new Set(pack.options.map((option) => option.id));
      const unknown = requestedOptionIds.filter((id) => !known.has(id));
      throw new BadRequestException(`Option inconnue pour cette formule : ${unknown.join(", ")}`);
    }

    // --- Adresse : elle doit appartenir au client ---
    const address = await this.prisma.address.findFirst({
      where: { id: dto.addressId, userId: clientId },
      select: { id: true, latitude: true, longitude: true, city: true }
    });
    if (!address) {
      throw new NotFoundException("Adresse introuvable dans votre carnet");
    }
    if (address.latitude == null || address.longitude == null) {
      throw new BadRequestException("Cette adresse n'est pas géolocalisée : elle ne peut pas servir de lieu d'intervention");
    }

    // --- L'adresse tombe-t-elle dans une zone du prestataire ? ---
    await this.assertAddressCovered(provider.zones.map((zone) => zone.zoneId), address.latitude, address.longitude);

    // --- Le créneau est-il couvert par l'agenda ? ---
    const durationMinutes =
      pack.durationMinutes + options.reduce((total, option) => total + option.durationMinutes, 0);
    await this.assertSlotAvailable(provider.id, scheduledAt, durationMinutes);

    // --- Anti-doublon : même client, même prestataire, même créneau ---
    const duplicate = await this.prisma.mission.findFirst({
      where: {
        clientId,
        providerId: provider.id,
        scheduledAt,
        status: { in: ["pending_provider", "confirmed", "in_progress"] }
      },
      select: { id: true }
    });
    if (duplicate) {
      throw new BadRequestException("Vous avez déjà une réservation en cours avec ce prestataire sur ce créneau");
    }

    // Montant indicatif FIGÉ (§8) : le prix affiché à la réservation reste
    // celui de la mission, même si le prestataire révise ses tarifs demain.
    const quotedAmount = pack.price + options.reduce((total, option) => total + option.price, 0);

    const mission = await this.prisma.$transaction(async (tx) => {
      const created = await tx.mission.create({
        data: {
          clientId,
          providerId: provider.id,
          packId: pack.id,
          addressId: address.id,
          scheduledAt,
          instructions: dto.instructions?.trim(),
          quotedAmount,
          status: "pending_provider",
          options: {
            create: options.map((option) => ({
              optionId: option.id,
              title: option.title,
              price: option.price
            }))
          },
          // Historique dès la création : une mission sans première entrée
          // apparaîtrait « sortie de nulle part » dans le suivi.
          history: {
            create: { newStatus: "pending_provider", changedBy: clientId, reason: "Réservation créée par le client" }
          },
          // Le fil de discussion existe dès la demande : le prestataire doit
          // pouvoir poser une question AVANT d'accepter.
          thread: { create: {} }
        },
        select: { id: true }
      });
      return created;
    });

    await this.audit.record({
      actorId: clientId,
      action: "missions.create",
      entity: "Mission",
      entityId: mission.id,
      newValue: {
        providerId: provider.id,
        packId: pack.id,
        scheduledAt,
        quotedAmount,
        options: options.map((option) => option.id)
      }
    });

    const client = await this.prisma.user.findUnique({
      where: { id: clientId },
      select: { firstName: true, lastName: true }
    });

    await this.events.notify({
      userId: provider.userId,
      code: NOTIFICATION.missionCreated,
      variables: {
        clientName: [client?.firstName, client?.lastName].filter(Boolean).join(" ") || "Un client",
        scheduledAt: formatDateTime(scheduledAt)
      },
      data: { missionId: mission.id, type: "mission" }
    });

    return this.detail(mission.id);
  }

  /**
   * Détail d'une mission tel que le voient le client et le prestataire.
   *
   * Volontairement distinct de la vue admin : ni notes internes, ni
   * commentaires réservés au back-office, ni coordonnées personnelles de
   * l'autre partie au-delà de ce qui est nécessaire à l'intervention.
   */
  async detail(missionId: string) {
    const mission = await this.prisma.mission.findUnique({
      where: { id: missionId },
      select: {
        id: true,
        status: true,
        scheduledAt: true,
        instructions: true,
        quotedAmount: true,
        createdAt: true,
        client: { select: { id: true, firstName: true, lastName: true } },
        provider: { select: { id: true, publicName: true, score: true, reviewsCount: true, avatarFileId: true } },
        pack: {
          select: {
            id: true,
            title: true,
            price: true,
            durationMinutes: true,
            providerService: { select: { title: true, serviceType: { select: { name: true } } } }
          }
        },
        options: { select: { optionId: true, title: true, price: true } },
        address: { select: { id: true, label: true, city: true, commune: true, details: true, latitude: true, longitude: true } },
        thread: { select: { id: true, status: true } },
        cancellation: { select: { reason: true, details: true, late: true, createdAt: true } },
        reschedules: {
          where: { status: "requested" },
          select: { id: true, newScheduledAt: true, reason: true, createdBy: true, createdAt: true }
        },
        reviews: { select: { id: true, authorId: true, rating: true } }
      }
    });

    if (!mission) {
      throw new NotFoundException("Mission introuvable");
    }

    return mission;
  }

  /**
   * Fil de discussion d'une mission (§12).
   *
   * Le contrôle d'appartenance est fait par l'appelant : ce service ne sait pas
   * qui demande, il ne fait que lire.
   */
  async thread(missionId: string) {
    const thread = await this.prisma.chatThread.findUnique({
      where: { missionId },
      select: {
        id: true,
        status: true,
        createdAt: true,
        _count: { select: { messages: true } }
      }
    });
    if (!thread) {
      throw new NotFoundException("Cette mission n'a pas de conversation");
    }
    return {
      id: thread.id,
      missionId,
      status: thread.status,
      messageCount: thread._count.messages,
      createdAt: thread.createdAt
    };
  }

  /**
   * Colonnes triables des listes de missions « me » (§15.4).
   *
   * En mode `lenient` (voir les appels ci-dessous) : un `sort` inconnu ou mal
   * formé ne bloque pas l'appelant, il retombe sur le tri par défaut de la
   * liste — contrairement aux listes du back-office, qui refusent
   * explicitement.
   */
  private static readonly MY_MISSIONS_SORTABLE: SortAllowList = {
    scheduledAt: { path: ["scheduledAt"] },
    createdAt: { path: ["createdAt"], defaultDirection: "desc" },
    status: ["status"]
  };

  /** Missions du client connecté (§8). */
  async listForClient(
    clientId: string,
    query: { status?: string | string[]; from?: string; to?: string; page?: number; limit?: number; sort?: string }
  ) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));
    const where = buildMissionListWhere({ clientId }, query);

    const [rows, total] = await Promise.all([
      this.prisma.mission.findMany({
        where,
        // Tri par défaut inchangé : `scheduledAt desc` — le client consulte
        // d'abord son historique récent.
        orderBy: buildOrderBy<Prisma.MissionOrderByWithRelationInput>(
          query.sort,
          MissionBookingService.MY_MISSIONS_SORTABLE,
          { scheduledAt: "desc" },
          { lenient: true }
        ),
        skip: (page - 1) * limit,
        take: limit,
        select: this.listSelect()
      }),
      this.prisma.mission.count({ where })
    ]);

    return { data: rows.map(toListItem), total, page, limit };
  }

  /**
   * Missions du prestataire connecté (§9).
   *
   * Triées par défaut par date d'intervention CROISSANTE : le prestataire veut
   * voir ce qui arrive, pas ce qui est passé. C'est l'inverse du besoin du
   * client — ce défaut n'est pas modifié par cette tâche.
   */
  async listForProvider(
    providerId: string,
    query: { status?: string | string[]; from?: string; to?: string; page?: number; limit?: number; sort?: string }
  ) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(100, Math.max(1, Number(query.limit ?? 20)));
    const where = buildMissionListWhere({ providerId }, query);

    const [rows, total] = await Promise.all([
      this.prisma.mission.findMany({
        where,
        orderBy: buildOrderBy<Prisma.MissionOrderByWithRelationInput>(
          query.sort,
          MissionBookingService.MY_MISSIONS_SORTABLE,
          { scheduledAt: "asc" },
          { lenient: true }
        ),
        skip: (page - 1) * limit,
        take: limit,
        select: this.listSelect()
      }),
      this.prisma.mission.count({ where })
    ]);

    return { data: rows.map(toListItem), total, page, limit };
  }

  private listSelect() {
    return {
      id: true,
      status: true,
      scheduledAt: true,
      quotedAmount: true,
      createdAt: true,
      client: { select: { id: true, firstName: true, lastName: true } },
      provider: { select: { id: true, publicName: true, avatarFileId: true } },
      pack: { select: { id: true, title: true, durationMinutes: true } },
      address: { select: { city: true, commune: true } }
    } satisfies Prisma.MissionSelect;
  }

  /**
   * Vérifie que l'adresse tombe dans une zone couverte par le prestataire.
   *
   * Sans ce contrôle, un client d'une autre ville pourrait réserver un
   * artisan qui ne s'y déplace pas — la mission ne serait découverte comme
   * impossible qu'au moment du refus, après avoir bloqué un créneau.
   */
  private async assertAddressCovered(zoneIds: string[], latitude: number, longitude: number): Promise<void> {
    if (zoneIds.length === 0) {
      throw new BadRequestException("Ce prestataire n'a déclaré aucune zone d'intervention");
    }

    const zones = await this.prisma.zone.findMany({
      where: { id: { in: zoneIds }, active: true },
      select: { name: true, latitude: true, longitude: true, radiusKm: true }
    });

    const covered = zones.some((zone) => {
      if (zone.latitude == null || zone.longitude == null || zone.radiusKm == null) {
        return false;
      }
      return haversineKm(latitude, longitude, zone.latitude, zone.longitude) <= zone.radiusKm;
    });

    if (!covered) {
      throw new BadRequestException("Cette adresse n'est pas dans la zone d'intervention du prestataire");
    }
  }

  /**
   * Vérifie que le créneau demandé est couvert par l'agenda et libre.
   *
   * Trois conditions : un créneau hebdomadaire englobe l'horaire, aucune
   * absence exceptionnelle ne le recouvre, et aucune autre mission ne
   * chevauche. La troisième est celle qui empêche le double booking — un
   * prestataire ne peut pas être à deux endroits en même temps.
   */
  private async assertSlotAvailable(providerId: string, scheduledAt: Date, durationMinutes: number): Promise<void> {
    const endAt = new Date(scheduledAt.getTime() + durationMinutes * 60_000);
    const weekday = scheduledAt.getUTCDay();
    const startTime = formatTime(scheduledAt);
    const endTime = formatTime(endAt);

    const slot = await this.prisma.providerAvailability.findFirst({
      where: {
        providerId,
        active: true,
        weekday,
        startTime: { lte: startTime },
        // La prestation doit tenir ENTIÈREMENT dans le créneau déclaré :
        // commencer à 11 h 30 une intervention d'une heure sur un créneau qui
        // ferme à 12 h reviendrait à faire déborder le prestataire.
        endTime: { gte: endTime }
      },
      select: { id: true }
    });
    if (!slot) {
      throw new BadRequestException("Le prestataire n'est pas disponible sur ce créneau");
    }

    const unavailable = await this.prisma.providerUnavailability.findFirst({
      where: { providerId, startAt: { lt: endAt }, endAt: { gt: scheduledAt } },
      select: { id: true }
    });
    if (unavailable) {
      throw new BadRequestException("Le prestataire est absent à cette date");
    }

    // Chevauchement avec une mission déjà engagée. On compare sur la durée
    // réelle de chaque formule, pas sur un créneau forfaitaire.
    const neighbours = await this.prisma.mission.findMany({
      where: {
        providerId,
        status: { in: ["pending_provider", "confirmed", "in_progress"] },
        scheduledAt: {
          gte: new Date(scheduledAt.getTime() - 24 * 60 * 60_000),
          lte: new Date(endAt.getTime() + 24 * 60 * 60_000)
        }
      },
      select: { scheduledAt: true, pack: { select: { durationMinutes: true } }, options: { select: { optionId: true } } }
    });

    const clash = neighbours.some((mission) => {
      if (!mission.scheduledAt) return false;
      const otherEnd = new Date(mission.scheduledAt.getTime() + (mission.pack?.durationMinutes ?? 60) * 60_000);
      return mission.scheduledAt < endAt && otherEnd > scheduledAt;
    });
    if (clash) {
      throw new BadRequestException("Ce créneau est déjà réservé chez ce prestataire");
    }
  }
}

// === Utilitaires partagés ===

function buildMissionListWhere(
  base: Prisma.MissionWhereInput,
  query: { status?: string | string[]; from?: string; to?: string }
): Prisma.MissionWhereInput {
  const where: Prisma.MissionWhereInput = { ...base };

  // `status` accepte une valeur ou une liste (`?status=completed,closed`) : un
  // onglet qui couvre deux statuts doit tenir en un seul appel, sinon sa
  // pagination est fausse.
  const statuses = (Array.isArray(query.status) ? query.status : query.status ? [query.status] : []).filter(Boolean);

  if (statuses.length === 1) {
    where.status = statuses[0] as MissionStatus;
  } else if (statuses.length > 1) {
    where.status = { in: statuses as MissionStatus[] };
  }

  if (query.from || query.to) {
    const scheduledAt: Prisma.DateTimeNullableFilter = {};
    if (query.from) {
      scheduledAt.gte = new Date(query.from);
    }
    if (query.to) {
      // Borne de fin inclusive : on prend tout le jour indiqué.
      const to = new Date(query.to);
      to.setDate(to.getDate() + 1);
      scheduledAt.lt = to;
    }
    where.scheduledAt = scheduledAt;
  }

  return where;
}

function toListItem(mission: {
  id: string;
  status: string;
  scheduledAt: Date | null;
  quotedAmount: number | null;
  createdAt: Date;
  client: { id: string; firstName: string | null; lastName: string | null };
  provider: { id: string; publicName: string; avatarFileId: string | null } | null;
  pack: { id: string; title: string; durationMinutes: number } | null;
  address: { city: string | null; commune: string | null } | null;
}) {
  return {
    id: mission.id,
    status: mission.status,
    scheduledAt: mission.scheduledAt,
    quotedAmount: mission.quotedAmount,
    durationMinutes: mission.pack?.durationMinutes ?? null,
    packTitle: mission.pack?.title ?? null,
    clientName: [mission.client.firstName, mission.client.lastName].filter(Boolean).join(" ") || null,
    providerId: mission.provider?.id ?? null,
    providerName: mission.provider?.publicName ?? null,
    providerAvatarFileId: mission.provider?.avatarFileId ?? null,
    city: mission.address?.city ?? null,
    commune: mission.address?.commune ?? null,
    createdAt: mission.createdAt
  };
}

/** « HH:MM » en UTC, format des créneaux `ProviderAvailability`. */
function formatTime(date: Date): string {
  return `${String(date.getUTCHours()).padStart(2, "0")}:${String(date.getUTCMinutes()).padStart(2, "0")}`;
}

/** Date lisible pour les notifications. */
export function formatDateTime(date: Date | null): string {
  if (!date) return "";
  return date.toISOString().replace("T", " ").slice(0, 16);
}

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const EARTH_RADIUS_KM = 6371;
  const toRad = (deg: number): number => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
}
