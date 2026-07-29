import { BadRequestException } from "@nestjs/common";
import type { ReviewStatus } from "@prisma/client";

// La modération d'un avis est plus souple qu'une machine à états stricte :
// depuis n'importe quel état, un modérateur peut publier, masquer ou rejeter.
const ALLOWED_TARGETS: ReviewStatus[] = ["published", "reported", "hidden", "rejected"];

// Masquer ou rejeter un avis exige un motif (décision motivée).
const REASON_REQUIRED: ReviewStatus[] = ["hidden", "rejected"];

export function assertModeration(target: ReviewStatus, reason?: string): void {
  if (!ALLOWED_TARGETS.includes(target)) {
    throw new BadRequestException(`Statut de modération invalide : ${target}`);
  }
  if (REASON_REQUIRED.includes(target) && (!reason || reason.trim() === "")) {
    throw new BadRequestException(`Un motif est obligatoire pour "${target}"`);
  }
}
