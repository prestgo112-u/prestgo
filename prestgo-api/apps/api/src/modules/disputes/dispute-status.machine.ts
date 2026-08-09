import { BadRequestException } from "@nestjs/common";
import type { DisputeStatus } from "@prisma/client";

// Transitions autorisées pour un litige (voir data-model.md).
const TRANSITIONS: Record<DisputeStatus, DisputeStatus[]> = {
  open: ["in_review"],
  in_review: ["waiting_client", "waiting_provider", "resolved", "rejected"],
  waiting_client: ["in_review", "resolved"],
  waiting_provider: ["in_review", "resolved"],
  resolved: ["closed"],
  rejected: ["closed"],
  closed: [] // état final
};

// Résolution, rejet et clôture exigent une décision ou un motif.
const REASON_REQUIRED: DisputeStatus[] = ["resolved", "rejected", "closed"];

export function canTransition(from: DisputeStatus, to: DisputeStatus): boolean {
  return TRANSITIONS[from]?.includes(to) ?? false;
}

export function assertTransition(from: DisputeStatus, to: DisputeStatus, reasonOrDecision?: string): void {
  if (!canTransition(from, to)) {
    throw new BadRequestException(`Transition de litige invalide : ${from} → ${to}`);
  }
  if (REASON_REQUIRED.includes(to) && (!reasonOrDecision || reasonOrDecision.trim() === "")) {
    throw new BadRequestException(`Une décision/un motif est obligatoire pour passer au statut "${to}"`);
  }
}
