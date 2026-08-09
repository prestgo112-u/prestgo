import { BadRequestException } from "@nestjs/common";
import type { ProviderValidationStatus } from "@prisma/client";

// Une "machine à états" décrit quels changements de statut sont autorisés.
// Clé = statut actuel, valeur = liste des statuts vers lesquels on peut aller.
// (Voir data-model.md pour la logique métier.)
const TRANSITIONS: Record<ProviderValidationStatus, ProviderValidationStatus[]> = {
  profile_incomplete: ["pending_review"],
  pending_review: ["approved", "rejected", "changes_requested"],
  changes_requested: ["pending_review"],
  approved: ["suspended"],
  suspended: ["approved", "rejected"],
  rejected: [] // état final : plus aucune transition
};

// Statuts qui exigent OBLIGATOIREMENT un motif (rejet, demande de correction, suspension).
const REASON_REQUIRED: ProviderValidationStatus[] = ["rejected", "changes_requested", "suspended"];

// Indique si passer de "from" à "to" est autorisé.
export function canTransition(from: ProviderValidationStatus, to: ProviderValidationStatus): boolean {
  return TRANSITIONS[from]?.includes(to) ?? false;
}

// Vérifie la transition et l'obligation de motif ; lève une erreur 400 sinon.
export function assertTransition(
  from: ProviderValidationStatus,
  to: ProviderValidationStatus,
  reason?: string
): void {
  if (!canTransition(from, to)) {
    throw new BadRequestException(`Transition de statut invalide : ${from} → ${to}`);
  }
  if (REASON_REQUIRED.includes(to) && (!reason || reason.trim() === "")) {
    throw new BadRequestException(`Un motif est obligatoire pour passer au statut "${to}"`);
  }
}