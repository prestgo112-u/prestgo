import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";

interface ZoneInput {
  name: string;
  cityId?: string;
  latitude?: number;
  longitude?: number;
  radiusKm?: number;
  active?: boolean;
}

@Injectable()
export class ZonesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  // Liste toutes les zones (vue admin : actives et inactives).
  async list() {
    return this.prisma.zone.findMany({ orderBy: { name: "asc" } });
  }

  // Vue publique : seules les zones actives, sans les champs internes.
  async listActive() {
    return this.prisma.zone.findMany({
      where: { active: true },
      select: {
        id: true,
        name: true,
        latitude: true,
        longitude: true,
        radiusKm: true,
        city: { select: { id: true, name: true, slug: true } }
      },
      orderBy: { name: "asc" }
    });
  }

  /**
   * Trouve les zones actives dont le centre est à moins de `radiusKm` d'un point.
   *
   * Pourquoi pas PostGIS : l'extension n'est pas installée sur l'instance
   * PostgreSQL utilisée. On procède donc en deux temps :
   *
   *   1. un PRÉ-FILTRE par rectangle, que PostgreSQL résout avec l'index
   *      `(latitude, longitude)` — c'est lui qui évite de parcourir la table ;
   *   2. un calcul de distance exact (formule de haversine) sur les quelques
   *      lignes restantes, pour couper les coins du rectangle.
   *
   * Le résultat est identique à celui de PostGIS ; seule la montée en charge
   * diffère. Le jour où l'extension sera disponible, seule cette méthode change.
   */
  async searchNearby(latitude: number, longitude: number, radiusKm: number) {
    // 1° de latitude ≈ 111 km partout. Pour la longitude, la distance se
    // resserre vers les pôles, d'où le cosinus de la latitude.
    const latDelta = radiusKm / 111;
    const cosLat = Math.cos((latitude * Math.PI) / 180);
    // Garde-fou : près des pôles le cosinus tend vers 0, la division exploserait.
    const lngDelta = radiusKm / (111 * Math.max(0.01, Math.abs(cosLat)));

    const candidates = await this.prisma.zone.findMany({
      where: {
        active: true,
        latitude: { gte: latitude - latDelta, lte: latitude + latDelta },
        longitude: { gte: longitude - lngDelta, lte: longitude + lngDelta }
      },
      select: {
        id: true,
        name: true,
        latitude: true,
        longitude: true,
        radiusKm: true,
        city: { select: { id: true, name: true, slug: true } }
      }
    });

    return candidates
      .map((zone) => ({
        ...zone,
        distanceKm: haversineKm(latitude, longitude, zone.latitude!, zone.longitude!)
      }))
      .filter((zone) => zone.distanceKm <= radiusKm)
      .sort((a, b) => a.distanceKm - b.distanceKm)
      .map((zone) => ({ ...zone, distanceKm: Math.round(zone.distanceKm * 100) / 100 }));
  }

  // Vérifie qu'une zone active a des coordonnées valides et un rayon positif.
  private validate(active: boolean, latitude?: number, longitude?: number, radiusKm?: number): void {
    if (!active) return; // une zone inactive n'a pas besoin de coordonnées
    if (latitude == null || longitude == null || radiusKm == null || radiusKm <= 0) {
      throw new BadRequestException("Une zone active exige latitude, longitude et un rayon positif");
    }
  }

  // Crée une zone.
  async create(dto: ZoneInput, actorId?: string) {
    const active = dto.active ?? true;
    this.validate(active, dto.latitude, dto.longitude, dto.radiusKm);
    const zone = await this.prisma.zone.create({
      data: { name: dto.name, cityId: dto.cityId, latitude: dto.latitude, longitude: dto.longitude, radiusKm: dto.radiusKm, active }
    });
    await this.audit.record({ actorId, action: "admin.zones.create", entity: "Zone", entityId: zone.id, newValue: dto });
    return zone;
  }

  // Met à jour une zone (activer/désactiver, changer les coordonnées).
  async update(id: string, dto: Partial<ZoneInput>, actorId?: string) {
    const existing = await this.prisma.zone.findUnique({ where: { id } });
    if (!existing) {
      throw new NotFoundException("Zone introuvable");
    }
    const merged = {
      name: dto.name ?? existing.name,
      cityId: dto.cityId ?? existing.cityId,
      latitude: dto.latitude ?? existing.latitude,
      longitude: dto.longitude ?? existing.longitude,
      radiusKm: dto.radiusKm ?? existing.radiusKm,
      active: dto.active ?? existing.active
    };
    this.validate(merged.active, merged.latitude ?? undefined, merged.longitude ?? undefined, merged.radiusKm ?? undefined);
    const zone = await this.prisma.zone.update({ where: { id }, data: merged });
    await this.audit.record({ actorId, action: "admin.zones.update", entity: "Zone", entityId: id, newValue: dto });
    return zone;
  }

  // Rattache une zone à un prestataire.
  async attachProvider(zoneId: string, providerId: string, actorId?: string) {
    await this.prisma.providerZone.upsert({
      where: { providerId_zoneId: { providerId, zoneId } },
      update: {},
      create: { providerId, zoneId }
    });
    await this.audit.record({ actorId, action: "admin.zones.attachProvider", entity: "Zone", entityId: zoneId, newValue: { providerId } });
    return { attached: true };
  }
}

/**
 * Distance en kilomètres entre deux points, formule de haversine.
 *
 * C'est la distance « à vol d'oiseau » sur la sphère terrestre. Suffisant pour
 * dire si un prestataire couvre une adresse ; ce n'est pas une distance
 * routière.
 */
function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const EARTH_RADIUS_KM = 6371;
  const toRad = (deg: number): number => (deg * Math.PI) / 180;

  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;

  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
}
