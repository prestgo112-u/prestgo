import { BadRequestException } from "@nestjs/common";
import type { MissionStatus } from "@prisma/client";

// Transitions autorisées pour une mission (voir data-model.md).
const TRANSITIONS: Record<MissionStatus, MissionStatus[]> = {
  draft: ["pending_provider"],
  pending_provider: ["confirmed", "cancelled"],
  confirmed: ["in_progress", "cancelled"],
  in_progress: ["completed", "disputed"],
  completed: ["closed", "disputed"],
  disputed: ["completed", "closed", "cancelled"],
  cancelled: [], // état final
  closed: [] // état final
};

// L'annulation exige toujours un motif.
const REASON_REQUIRED: MissionStatus[] = ["cancelled"];

export function canTransition(from: MissionStatus, to: MissionStatus): boolean {
  return TRANSITIONS[from]?.includes(to) ?? false;
}

export function assertTransition(from: MissionStatus, to: MissionStatus, reason?: string): void {
  if (!canTransition(from, to)) {
    throw new BadRequestException(`Transition de mission invalide : ${from} → ${to}`);
  }
  if (REASON_REQUIRED.includes(to) && (!reason || reason.trim() === "")) {
    throw new BadRequestException(`Un motif est obligatoire pour passer au statut "${to}"`);
  }
}
