import { BadRequestException, Injectable } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";

interface AvailabilityInput {
  weekday: number; // 0 = dimanche ... 6 = samedi
  startTime: string; // "HH:MM"
  endTime: string; // "HH:MM"
}

@Injectable()
export class AvailabilityService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  // Liste les créneaux de disponibilité d'un prestataire.
  async listForProvider(providerId: string) {
    return this.prisma.providerAvailability.findMany({
      where: { providerId },
      orderBy: [{ weekday: "asc" }, { startTime: "asc" }]
    });
  }

  // Ajoute un créneau après avoir vérifié qu'il est valide et ne chevauche rien.
  async add(providerId: string, dto: AvailabilityInput, actorId?: string) {
    if (dto.weekday < 0 || dto.weekday > 6) {
      throw new BadRequestException("Le jour doit être compris entre 0 (dimanche) et 6 (samedi)");
    }
    // Les heures étant au format "HH:MM" avec deux chiffres, la comparaison de chaînes
    // équivaut à une comparaison chronologique (ex. "09:00" < "14:30").
    if (dto.endTime <= dto.startTime) {
      throw new BadRequestException("L'heure de fin doit être après l'heure de début");
    }

    // On récupère les créneaux actifs du même jour pour détecter un chevauchement.
    const sameDay = await this.prisma.providerAvailability.findMany({
      where: { providerId, weekday: dto.weekday, active: true }
    });
    const overlaps = sameDay.some((slot) => dto.startTime < slot.endTime && slot.startTime < dto.endTime);
    if (overlaps) {
      throw new BadRequestException("Ce créneau chevauche une disponibilité existante");
    }

    const created = await this.prisma.providerAvailability.create({
      data: { providerId, weekday: dto.weekday, startTime: dto.startTime, endTime: dto.endTime }
    });
    await this.audit.record({ actorId, action: "admin.availability.add", entity: "ProviderAvailability", entityId: created.id, newValue: dto });
    return created;
  }

  /**
   * Remplace tout l'agenda hebdomadaire d'un prestataire.
   *
   * On valide TOUS les créneaux avant d'écrire quoi que ce soit : si le 5ᵉ est
   * invalide, le prestataire ne doit pas se retrouver avec un agenda à moitié
   * effacé. La suppression et la réinsertion sont ensuite faites dans une
   * transaction, pour la même raison.
   */
  async replaceAll(providerId: string, slots: AvailabilityInput[], actorId?: string) {
    for (const slot of slots) {
      if (slot.endTime <= slot.startTime) {
        throw new BadRequestException(
          `Créneau invalide (${slot.startTime}–${slot.endTime}) : l'heure de fin doit être après l'heure de début`
        );
      }
    }

    // Détection des chevauchements à l'intérieur même de l'agenda envoyé.
    for (let i = 0; i < slots.length; i += 1) {
      for (let j = i + 1; j < slots.length; j += 1) {
        const a = slots[i]!;
        const b = slots[j]!;
        if (a.weekday === b.weekday && a.startTime < b.endTime && b.startTime < a.endTime) {
          throw new BadRequestException(
            `Deux créneaux se chevauchent le jour ${a.weekday} (${a.startTime}–${a.endTime} et ${b.startTime}–${b.endTime})`
          );
        }
      }
    }

    await this.prisma.$transaction([
      this.prisma.providerAvailability.deleteMany({ where: { providerId } }),
      this.prisma.providerAvailability.createMany({
        data: slots.map((slot) => ({
          providerId,
          weekday: slot.weekday,
          startTime: slot.startTime,
          endTime: slot.endTime
        }))
      })
    ]);

    await this.audit.record({
      actorId,
      action: "providers.availability.replace",
      entity: "ProviderProfile",
      entityId: providerId,
      newValue: { slots: slots.length }
    });

    return this.listForProvider(providerId);
  }

  // === Indisponibilités exceptionnelles (congés, absence ponctuelle) ===
  // Elles complètent l'agenda hebdomadaire : celui-ci dit « je travaille le
  // lundi matin », celles-ci disent « sauf du 12 au 20 août ».

  async listUnavailabilities(providerId: string) {
    return this.prisma.providerUnavailability.findMany({
      where: { providerId },
      orderBy: { startAt: "asc" }
    });
  }

  async addUnavailability(
    providerId: string,
    dto: { startAt: string; endAt: string; reason?: string },
    actorId?: string
  ) {
    const startAt = new Date(dto.startAt);
    const endAt = new Date(dto.endAt);

    if (endAt <= startAt) {
      throw new BadRequestException("La date de fin doit être après la date de début");
    }

    // Un chevauchement n'aurait pas de sens : deux absences sur la même période
    // décrivent la même chose.
    const overlapping = await this.prisma.providerUnavailability.findFirst({
      where: { providerId, startAt: { lt: endAt }, endAt: { gt: startAt } }
    });
    if (overlapping) {
      throw new BadRequestException("Cette période chevauche une indisponibilité existante");
    }

    const created = await this.prisma.providerUnavailability.create({
      data: { providerId, startAt, endAt, reason: dto.reason }
    });

    await this.audit.record({
      actorId,
      action: "providers.unavailability.add",
      entity: "ProviderUnavailability",
      entityId: created.id,
      newValue: { providerId, startAt, endAt, reason: dto.reason }
    });
    return created;
  }

  async removeUnavailability(id: string, actorId?: string) {
    await this.prisma.providerUnavailability.delete({ where: { id } });
    await this.audit.record({
      actorId,
      action: "providers.unavailability.remove",
      entity: "ProviderUnavailability",
      entityId: id
    });
    return { removed: true };
  }

  // Supprime un créneau.
  async remove(id: string, actorId?: string) {
    await this.prisma.providerAvailability.delete({ where: { id } });
    await this.audit.record({ actorId, action: "admin.availability.remove", entity: "ProviderAvailability", entityId: id });
    return { removed: true };
  }
}
