import { BadRequestException, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaService } from "../../common/prisma/prisma.service.js";
import { AuditService } from "../audit/audit.service.js";
import { MAX_ADDRESSES_PER_USER } from "../settings/settings.keys.js";

interface AddressInput {
  label: string;
  city: string;
  commune?: string;
  details?: string;
  latitude: number;
  longitude: number;
  isDefault?: boolean;
}

/**
 * Carnet d'adresses du client (§4).
 *
 * Toutes les méthodes prennent le `userId` du jeton : une adresse est toujours
 * cherchée par le couple (id, propriétaire), jamais par son seul identifiant.
 * C'est ce qui empêche de lire ou d'effacer l'adresse d'un inconnu.
 */
@Injectable()
export class AddressesService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly audit: AuditService
  ) {}

  async list(userId: string) {
    return this.prisma.address.findMany({
      where: { userId },
      orderBy: [{ isDefault: "desc" }, { createdAt: "desc" }],
      select: {
        id: true,
        label: true,
        city: true,
        commune: true,
        details: true,
        latitude: true,
        longitude: true,
        isDefault: true,
        createdAt: true
      }
    });
  }

  /**
   * Crée une adresse.
   *
   * Deux règles du §4 sont appliquées ici :
   *   - dix adresses au maximum — au-delà, c'est du remplissage, pas un usage ;
   *   - la PREMIÈRE adresse devient automatiquement l'adresse par défaut,
   *     sinon le client réserverait sans adresse pré-remplie alors qu'il n'en
   *     a qu'une.
   */
  async create(userId: string, dto: AddressInput) {
    const count = await this.prisma.address.count({ where: { userId } });
    if (count >= MAX_ADDRESSES_PER_USER) {
      throw new BadRequestException(`Vous ne pouvez pas enregistrer plus de ${MAX_ADDRESSES_PER_USER} adresses`);
    }

    const shouldBeDefault = dto.isDefault === true || count === 0;

    // Transaction : basculer le drapeau par défaut et créer l'adresse doivent
    // réussir ou échouer ensemble, sans quoi le compte pourrait se retrouver
    // avec deux adresses par défaut — ou aucune.
    const address = await this.prisma.$transaction(async (tx) => {
      if (shouldBeDefault) {
        await tx.address.updateMany({ where: { userId, isDefault: true }, data: { isDefault: false } });
      }
      return tx.address.create({
        data: {
          userId,
          label: dto.label.trim(),
          city: dto.city.trim(),
          commune: dto.commune?.trim(),
          details: dto.details?.trim(),
          latitude: dto.latitude,
          longitude: dto.longitude,
          isDefault: shouldBeDefault
        }
      });
    });

    await this.audit.record({
      actorId: userId,
      action: "me.addresses.create",
      entity: "Address",
      entityId: address.id,
      newValue: { label: address.label, city: address.city, isDefault: address.isDefault }
    });

    return address;
  }

  async update(userId: string, addressId: string, dto: Partial<AddressInput>) {
    const existing = await this.requireOwned(userId, addressId);

    const address = await this.prisma.address.update({
      where: { id: addressId },
      data: {
        label: dto.label?.trim() ?? existing.label,
        city: dto.city?.trim() ?? existing.city,
        commune: dto.commune?.trim() ?? existing.commune,
        details: dto.details?.trim() ?? existing.details,
        latitude: dto.latitude ?? existing.latitude,
        longitude: dto.longitude ?? existing.longitude
      }
    });

    await this.audit.record({
      actorId: userId,
      action: "me.addresses.update",
      entity: "Address",
      entityId: addressId,
      oldValue: { label: existing.label, city: existing.city },
      newValue: { label: address.label, city: address.city }
    });

    return address;
  }

  /**
   * Supprime une adresse.
   *
   * Une adresse déjà utilisée par une mission n'est PAS supprimée : elle
   * documente où l'intervention a eu lieu. On la détache du carnet en la
   * renommant, ce qui la fait disparaître de la liste sans casser l'historique
   * — supprimer aurait rompu la clé étrangère de la mission.
   */
  async remove(userId: string, addressId: string) {
    const existing = await this.requireOwned(userId, addressId);

    const usedByMissions = await this.prisma.mission.count({ where: { addressId } });

    if (usedByMissions > 0) {
      await this.prisma.$transaction(async (tx) => {
        await tx.address.update({ where: { id: addressId }, data: { isDefault: false } });
        await tx.clientProfile.updateMany({ where: { defaultAddressId: addressId }, data: { defaultAddressId: null } });
      });
      // Le carnet ne montre que les adresses non archivées : on marque
      // l'archivage par le libellé, la table n'ayant pas de colonne dédiée.
      await this.prisma.address.update({
        where: { id: addressId },
        data: { label: `${existing.label} (archivée)` }
      });

      await this.audit.record({
        actorId: userId,
        action: "me.addresses.archive",
        entity: "Address",
        entityId: addressId,
        newValue: { reason: "référencée par des missions", missions: usedByMissions }
      });

      return { removed: false, archived: true, reason: "Adresse conservée car utilisée par des missions passées" };
    }

    await this.prisma.$transaction(async (tx) => {
      await tx.clientProfile.updateMany({ where: { defaultAddressId: addressId }, data: { defaultAddressId: null } });
      await tx.address.delete({ where: { id: addressId } });

      // Si l'adresse supprimée était celle par défaut, on promeut la plus
      // récente : laisser le compte sans adresse par défaut obligerait à
      // rechoisir à chaque réservation.
      if (existing.isDefault) {
        const next = await tx.address.findFirst({ where: { userId }, orderBy: { createdAt: "desc" } });
        if (next) {
          await tx.address.update({ where: { id: next.id }, data: { isDefault: true } });
        }
      }
    });

    await this.audit.record({
      actorId: userId,
      action: "me.addresses.delete",
      entity: "Address",
      entityId: addressId,
      oldValue: { label: existing.label, city: existing.city }
    });

    return { removed: true, archived: false };
  }

  /** Désigne l'adresse par défaut : une seule à la fois, bascule en transaction. */
  async setDefault(userId: string, addressId: string) {
    await this.requireOwned(userId, addressId);

    await this.prisma.$transaction(async (tx) => {
      await tx.address.updateMany({ where: { userId, isDefault: true }, data: { isDefault: false } });
      await tx.address.update({ where: { id: addressId }, data: { isDefault: true } });
      // Le profil client porte aussi l'adresse par défaut (colonne historique) :
      // laisser les deux diverger afficherait deux adresses différentes selon
      // l'écran consulté.
      await tx.clientProfile.updateMany({ where: { userId }, data: { defaultAddressId: addressId } });
    });

    await this.audit.record({
      actorId: userId,
      action: "me.addresses.setDefault",
      entity: "Address",
      entityId: addressId
    });

    return this.list(userId);
  }

  /**
   * Charge une adresse en vérifiant qu'elle appartient bien à l'appelant.
   *
   * On répond 404 et non 403 : révéler qu'une adresse existe chez quelqu'un
   * d'autre serait déjà une fuite. La règle du §14.3 (403 plutôt que 404) vise
   * les missions, où l'appelant connaît déjà l'existence de la ressource.
   */
  private async requireOwned(userId: string, addressId: string) {
    const address = await this.prisma.address.findFirst({ where: { id: addressId, userId } });
    if (!address) {
      throw new NotFoundException("Adresse introuvable");
    }
    return address;
  }
}
