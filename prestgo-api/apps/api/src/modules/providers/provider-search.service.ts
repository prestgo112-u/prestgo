import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import type { Prisma } from "@prisma/client";
import { PrismaService } from "../../common/prisma/prisma.service.js";

/** Rayon de recherche par défaut et plafond (§7). */
export const DEFAULT_SEARCH_RADIUS_KM = 10;
export const MAX_SEARCH_RADIUS_KM = 50;

/**
 * Nombre maximum de candidats rapportés en mémoire pour un tri par distance.
 *
 * La distance ne se calcule pas en SQL sans PostGIS (§15.6) : trier dessus
 * impose de ramener les candidats. Le plafond borne ce coût. Il est très
 * au-dessus du nombre de prestataires couvrant un même point à Abidjan au
 * lancement ; le jour où il serait atteint, c'est le signal qu'il faut activer
 * PostGIS.
 */
const DISTANCE_SORT_CAP = 500;

export interface ProviderSearchQuery {
  categoryId?: string;
  serviceTypeId?: string;
  latitude?: number;
  longitude?: number;
  radiusKm?: number;
  zoneId?: string;
  date?: string;
  startTime?: string;
  minRating?: number;
  q?: string;
  sort?: string;
  page?: number;
  limit?: number;
}

/**
 * Recherche de prestataires (§7) — le moteur de l'écran d'accueil client.
 *
 * Deux principes gouvernent tout ce fichier :
 *
 * 1. **Les filtres d'office ne sont pas contournables.** Statut de validation,
 *    compte actif, disponibilité déclarée : ils sont posés dans le `where` de
 *    base, avant tout paramètre d'appel. Aucun paramètre ne peut les desserrer.
 *
 * 2. **Aucune donnée interne ne sort.** Ni email, ni téléphone, ni note
 *    d'agent, ni document. Ce que renvoie la recherche est exactement ce qu'un
 *    visiteur non connecté a le droit de voir.
 */
@Injectable()
export class ProviderSearchService {
  constructor(private readonly prisma: PrismaService) {}

  async search(query: ProviderSearchQuery) {
    const page = Math.max(1, Number(query.page ?? 1));
    const limit = Math.min(50, Math.max(1, Number(query.limit ?? 20)));

    const geo = this.resolveGeo(query);
    const where = await this.buildWhere(query, geo);

    // Le tri par distance impose un calcul hors SQL : on le traite à part.
    const sort = this.resolveSort(query.sort, geo !== null);

    if (sort === "distance" && geo) {
      return this.searchByDistance(where, geo, page, limit);
    }

    const orderBy: Prisma.ProviderProfileOrderByWithRelationInput =
      sort === "rating" ? { score: "desc" } : { createdAt: "desc" };

    const [rows, total] = await Promise.all([
      this.prisma.providerProfile.findMany({
        where,
        select: this.listSelect(),
        orderBy,
        skip: (page - 1) * limit,
        take: limit
      }),
      this.prisma.providerProfile.count({ where })
    ]);

    return {
      data: rows.map((row) => this.toListItem(row, geo)),
      total,
      page,
      limit
    };
  }

  /**
   * Fiche publique complète, en UN appel (§7).
   *
   * L'application mobile affiche tout l'écran prestataire d'un coup :
   * multiplier les allers-retours sur une connexion mobile ferait apparaître
   * l'écran par morceaux. D'où cette agrégation.
   */
  async publicProfile(providerId: string) {
    const provider = await this.prisma.providerProfile.findFirst({
      where: {
        id: providerId,
        // Un dossier non approuvé n'a pas de fiche publique : le rendre
        // consultable par identifiant contournerait la validation.
        validationStatus: "approved",
        user: { status: "active" }
      },
      select: {
        id: true,
        publicName: true,
        bio: true,
        experienceYears: true,
        availabilityStatus: true,
        score: true,
        reviewsCount: true,
        avatarFileId: true,
        createdAt: true,
        services: {
          where: { active: true },
          select: {
            id: true,
            title: true,
            description: true,
            serviceType: {
              select: { id: true, name: true, category: { select: { id: true, name: true, slug: true } } }
            },
            packs: {
              where: { active: true },
              orderBy: { price: "asc" },
              select: {
                id: true,
                title: true,
                description: true,
                price: true,
                durationMinutes: true,
                options: {
                  where: { active: true },
                  select: { id: true, title: true, price: true, durationMinutes: true }
                }
              }
            }
          }
        },
        portfolio: {
          orderBy: [{ displayOrder: "asc" }, { createdAt: "desc" }],
          select: { id: true, title: true, description: true, fileId: true }
        },
        availability: {
          where: { active: true },
          orderBy: [{ weekday: "asc" }, { startTime: "asc" }],
          select: { weekday: true, startTime: true, endTime: true }
        },
        unavailabilities: {
          // Seules les absences À VENIR intéressent un client qui réserve.
          where: { endAt: { gte: new Date() } },
          orderBy: { startAt: "asc" },
          select: { startAt: true, endAt: true }
        },
        zones: {
          where: { zone: { active: true } },
          select: { zone: { select: { id: true, name: true, city: { select: { name: true } } } } }
        }
      }
    });

    if (!provider) {
      throw new NotFoundException("Prestataire introuvable");
    }

    const [distribution, latestReviews] = await Promise.all([
      this.prisma.review.groupBy({
        by: ["rating"],
        where: { status: "published", mission: { providerId } },
        _count: { rating: true }
      }),
      this.prisma.review.findMany({
        where: { status: "published", mission: { providerId } },
        orderBy: { createdAt: "desc" },
        take: 5,
        select: {
          id: true,
          rating: true,
          comment: true,
          createdAt: true,
          // Prénom seul : identifier complètement l'auteur d'un avis serait une
          // fuite de donnée personnelle sur une page publique.
          author: { select: { firstName: true } }
        }
      })
    ]);

    const ratingDistribution: Record<string, number> = { "1": 0, "2": 0, "3": 0, "4": 0, "5": 0 };
    for (const bucket of distribution) {
      ratingDistribution[String(bucket.rating)] = bucket._count.rating;
    }

    const packs = provider.services.flatMap((service) => service.packs);

    return {
      id: provider.id,
      publicName: provider.publicName,
      bio: provider.bio,
      experienceYears: provider.experienceYears,
      avatarFileId: provider.avatarFileId,
      availableNow: provider.availabilityStatus === "available",
      score: Math.round(provider.score * 10) / 10,
      reviewsCount: provider.reviewsCount,
      startingPrice: packs.length ? Math.min(...packs.map((pack) => pack.price)) : null,
      categories: [
        ...new Map(
          provider.services.map((service) => [service.serviceType.category.id, service.serviceType.category])
        ).values()
      ],
      services: provider.services,
      portfolio: provider.portfolio,
      availability: provider.availability,
      upcomingUnavailabilities: provider.unavailabilities,
      zones: provider.zones.map((entry) => entry.zone),
      ratingDistribution,
      latestReviews: latestReviews.map((review) => ({
        id: review.id,
        rating: review.rating,
        comment: review.comment,
        authorFirstName: review.author?.firstName ?? null,
        createdAt: review.createdAt
      })),
      memberSince: provider.createdAt
    };
  }

  // === Construction de la requête ===

  private resolveGeo(query: ProviderSearchQuery): { latitude: number; longitude: number; radiusKm: number } | null {
    if (query.latitude == null || query.longitude == null) {
      return null;
    }
    const radiusKm = Math.min(MAX_SEARCH_RADIUS_KM, Math.max(1, query.radiusKm ?? DEFAULT_SEARCH_RADIUS_KM));
    return { latitude: query.latitude, longitude: query.longitude, radiusKm };
  }

  private resolveSort(sort: string | undefined, hasGeo: boolean): "distance" | "rating" | "recent" {
    const requested = sort?.trim().toLowerCase();
    if (requested === "distance") {
      if (!hasGeo) {
        throw new BadRequestException("Le tri par distance exige latitude et longitude");
      }
      return "distance";
    }
    if (requested === "rating") return "rating";
    if (requested === "recent") return "recent";
    if (requested) {
      throw new BadRequestException(`Tri inconnu : « ${requested} ». Valeurs acceptées : distance, rating, recent.`);
    }
    // Défaut : la distance si l'on sait où est le client, la note sinon.
    return hasGeo ? "distance" : "rating";
  }

  private async buildWhere(
    query: ProviderSearchQuery,
    geo: { latitude: number; longitude: number; radiusKm: number } | null
  ): Promise<Prisma.ProviderProfileWhereInput> {
    // --- Filtres appliqués d'office (§7), non contournables ---
    const where: Prisma.ProviderProfileWhereInput = {
      validationStatus: "approved",
      user: { status: "active" },
      availabilityStatus: { not: "unavailable" }
    };

    // --- Offre ---
    if (query.serviceTypeId) {
      where.services = { some: { active: true, serviceTypeId: query.serviceTypeId, packs: { some: { active: true } } } };
    } else if (query.categoryId) {
      where.services = {
        some: { active: true, serviceType: { categoryId: query.categoryId }, packs: { some: { active: true } } }
      };
    } else {
      // Même sans filtre d'offre, un prestataire sans formule active n'est pas
      // réservable : l'afficher mènerait à une fiche sans bouton.
      where.services = { some: { active: true, packs: { some: { active: true } } } };
    }

    // --- Géographie ---
    if (geo) {
      const zoneIds = await this.candidateZoneIds(geo);
      // Aucune zone ne couvre ce point : la recherche ne doit rien renvoyer,
      // et surtout pas « tous les prestataires » faute de filtre.
      where.zones = { some: { zoneId: { in: zoneIds } } };
    } else if (query.zoneId) {
      where.zones = { some: { zoneId: query.zoneId, zone: { active: true } } };
    }

    // --- Créneau demandé ---
    if (query.date && query.startTime) {
      const { weekday, startAt, endAt } = this.resolveSlot(query.date, query.startTime);
      where.availability = {
        some: {
          active: true,
          weekday,
          // Les heures sont au format « HH:MM » sur deux chiffres : la
          // comparaison de chaînes équivaut à une comparaison horaire.
          startTime: { lte: query.startTime },
          endTime: { gt: query.startTime }
        }
      };
      // Et aucune absence exceptionnelle ne recouvre l'horaire.
      where.unavailabilities = { none: { startAt: { lt: endAt }, endAt: { gt: startAt } } };
    } else if (query.date || query.startTime) {
      throw new BadRequestException("Indiquez à la fois « date » et « startTime » pour filtrer sur un créneau");
    }

    // --- Note minimale ---
    if (query.minRating != null) {
      where.score = { gte: query.minRating };
    }

    // --- Recherche texte ---
    if (query.q?.trim()) {
      const term = query.q.trim();
      where.OR = [
        { publicName: { contains: term, mode: "insensitive" } },
        { services: { some: { active: true, title: { contains: term, mode: "insensitive" } } } }
      ];
    }

    return where;
  }

  /**
   * Zones retenues pour un point donné.
   *
   * Réutilise la technique de `zones/nearby` (§7 « Technique ») : un pré-filtre
   * par RECTANGLE, que PostgreSQL résout avec l'index `(latitude, longitude)`,
   * puis un calcul de distance exact sur le petit reste.
   *
   * Une zone est retenue si elle COUVRE le point (le prestataire se déplace
   * jusque-là) ou si son centre tombe dans le rayon demandé (le client accepte
   * de s'en approcher). L'union des deux évite d'écarter un prestataire dont la
   * zone est large mais centrée un peu plus loin.
   */
  private async candidateZoneIds(geo: { latitude: number; longitude: number; radiusKm: number }): Promise<string[]> {
    // On élargit le rectangle au plus grand rayon de zone existant, sinon une
    // zone très large centrée hors du rectangle serait écartée avant même le
    // calcul de distance.
    const largestZoneRadius = await this.prisma.zone.aggregate({
      where: { active: true },
      _max: { radiusKm: true }
    });
    const searchBox = geo.radiusKm + (largestZoneRadius._max.radiusKm ?? 0);

    const latDelta = searchBox / 111;
    const cosLat = Math.cos((geo.latitude * Math.PI) / 180);
    const lngDelta = searchBox / (111 * Math.max(0.01, Math.abs(cosLat)));

    const candidates = await this.prisma.zone.findMany({
      where: {
        active: true,
        latitude: { gte: geo.latitude - latDelta, lte: geo.latitude + latDelta },
        longitude: { gte: geo.longitude - lngDelta, lte: geo.longitude + lngDelta }
      },
      select: { id: true, latitude: true, longitude: true, radiusKm: true }
    });

    return candidates
      .filter((zone) => {
        if (zone.latitude == null || zone.longitude == null) return false;
        const distance = haversineKm(geo.latitude, geo.longitude, zone.latitude, zone.longitude);
        return distance <= Math.max(zone.radiusKm ?? 0, geo.radiusKm);
      })
      .map((zone) => zone.id);
  }

  /** Décompose « date + heure » en jour de la semaine et bornes horaires. */
  private resolveSlot(date: string, startTime: string) {
    if (!/^\d{2}:\d{2}$/.test(startTime)) {
      throw new BadRequestException("« startTime » doit être au format HH:MM");
    }
    const startAt = new Date(`${date}T${startTime}:00.000Z`);
    if (Number.isNaN(startAt.getTime())) {
      throw new BadRequestException("« date » doit être au format AAAA-MM-JJ");
    }
    return {
      weekday: startAt.getUTCDay(),
      startAt,
      // Une heure d'amplitude par défaut : c'est la granularité des créneaux
      // proposés côté application, et la durée réelle dépend de la formule
      // choisie, qui n'est pas encore connue au moment de la recherche.
      endAt: new Date(startAt.getTime() + 60 * 60_000)
    };
  }

  // === Tri par distance ===

  private async searchByDistance(
    where: Prisma.ProviderProfileWhereInput,
    geo: { latitude: number; longitude: number; radiusKm: number },
    page: number,
    limit: number
  ) {
    const [rows, total] = await Promise.all([
      this.prisma.providerProfile.findMany({ where, select: this.listSelect(), take: DISTANCE_SORT_CAP }),
      this.prisma.providerProfile.count({ where })
    ]);

    const sorted = rows
      .map((row) => this.toListItem(row, geo))
      .sort((a, b) => (a.distanceKm ?? Number.POSITIVE_INFINITY) - (b.distanceKm ?? Number.POSITIVE_INFINITY));

    return {
      data: sorted.slice((page - 1) * limit, page * limit),
      total,
      page,
      limit
    };
  }

  private listSelect() {
    return {
      id: true,
      publicName: true,
      score: true,
      reviewsCount: true,
      avatarFileId: true,
      availabilityStatus: true,
      createdAt: true,
      services: {
        where: { active: true },
        select: {
          serviceType: { select: { category: { select: { id: true, name: true } } } },
          packs: { where: { active: true }, select: { price: true } }
        }
      },
      zones: {
        where: { zone: { active: true } },
        select: { zone: { select: { id: true, latitude: true, longitude: true } } }
      }
    } satisfies Prisma.ProviderProfileSelect;
  }

  private toListItem(
    row: Prisma.ProviderProfileGetPayload<{ select: ReturnType<ProviderSearchService["listSelect"]> }>,
    geo: { latitude: number; longitude: number } | null
  ) {
    const prices = row.services.flatMap((service) => service.packs.map((pack) => pack.price));

    // Distance : celle de la zone la plus proche du client. C'est la valeur
    // qui a un sens pour lui — « à quelle distance ce prestataire intervient ».
    let distanceKm: number | null = null;
    if (geo) {
      const distances = row.zones
        .map((entry) => entry.zone)
        .filter((zone) => zone.latitude != null && zone.longitude != null)
        .map((zone) => haversineKm(geo.latitude, geo.longitude, zone.latitude!, zone.longitude!));
      if (distances.length) {
        distanceKm = Math.round(Math.min(...distances) * 100) / 100;
      }
    }

    return {
      id: row.id,
      publicName: row.publicName,
      score: Math.round(row.score * 10) / 10,
      reviewsCount: row.reviewsCount,
      distanceKm,
      categories: [
        ...new Set(row.services.map((service) => service.serviceType.category.name))
      ],
      startingPrice: prices.length ? Math.min(...prices) : null,
      avatarFileId: row.avatarFileId,
      availableNow: row.availabilityStatus === "available"
    };
  }
}

/**
 * Distance en kilomètres entre deux points, formule de haversine.
 *
 * Distance « à vol d'oiseau ». Suffisant pour dire si un prestataire couvre une
 * adresse et pour trier des résultats ; ce n'est pas une distance routière.
 */
function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const EARTH_RADIUS_KM = 6371;
  const toRad = (deg: number): number => (deg * Math.PI) / 180;

  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;

  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
}
