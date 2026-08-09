import { useCallback, useEffect, useState, type ReactElement } from "react";
import { Link, useParams } from "react-router-dom";
import { apiClient } from "../../lib/api-client";
import { useReasonPrompt } from "../../components/prompt";

interface MissionDetail {
  id: string;
  status: string;
  instructions?: string;
  scheduledAt?: string;
  client: { firstName?: string; lastName?: string; email?: string };
  provider?: { publicName: string };
  // Lot 1 : la prestation vendue et le lieu d'intervention.
  pack?: {
    title: string;
    price: number;
    durationMinutes: number;
    providerService?: { title: string; serviceType?: { name: string } };
  };
  address?: { label?: string; city?: string; commune?: string; details?: string };
  history: { id: string; oldStatus?: string; newStatus: string; reason?: string; createdAt: string }[];
  reschedules?: { id: string; newScheduledAt: string; reason?: string; createdAt: string }[];
  cancellation?: { reason: string; createdAt: string };
}

// Transitions proposées selon le statut (reflète la machine à états backend).
const STATUS_ACTIONS: Record<string, { status: string; label: string; reason: boolean }[]> = {
  draft: [{ status: "pending_provider", label: "Envoyer au prestataire", reason: false }],
  pending_provider: [
    { status: "confirmed", label: "Confirmer", reason: false },
    { status: "cancelled", label: "Annuler", reason: true }
  ],
  confirmed: [
    { status: "in_progress", label: "Démarrer", reason: false },
    { status: "cancelled", label: "Annuler", reason: true }
  ],
  in_progress: [
    { status: "completed", label: "Terminer", reason: false },
    { status: "disputed", label: "Marquer en litige", reason: false }
  ],
  completed: [
    { status: "closed", label: "Clôturer", reason: false },
    { status: "disputed", label: "Marquer en litige", reason: false }
  ],
  disputed: [
    { status: "completed", label: "Terminer", reason: false },
    { status: "closed", label: "Clôturer", reason: false },
    { status: "cancelled", label: "Annuler", reason: true }
  ],
  cancelled: [],
  closed: []
};

export function MissionDetailPage(): ReactElement {
  const { id } = useParams<{ id: string }>();
  const ask = useReasonPrompt();
  const [mission, setMission] = useState<MissionDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  // Nouvelle date saisie dans le formulaire de reprogrammation.
  const [newDate, setNewDate] = useState("");

  const load = useCallback(() => {
    if (!id) return;
    apiClient
      .get<MissionDetail>(`/admin/missions/${id}`)
      .then(setMission)
      .catch(() => setError("Mission introuvable."));
  }, [id]);

  useEffect(() => load(), [load]);

  // Change le statut (via /status), ou annule (via /cancel) qui demande un motif.
  async function act(status: string, needsReason: boolean): Promise<void> {
    let reason: string | undefined;
    if (needsReason) {
      reason = (await ask("Motif ?")) ?? "";
      if (!reason.trim()) return;
    }
    try {
      if (status === "cancelled") {
        await apiClient.post(`/admin/missions/${id}/cancel`, { reason });
      } else {
        await apiClient.request(`/admin/missions/${id}/status`, {
          method: "PATCH",
          body: JSON.stringify({ status, reason })
        });
      }
      load();
    } catch {
      setError("Action refusée (transition non autorisée ?).");
    }
  }

  /**
   * Reporte la mission à une nouvelle date.
   *
   * L'API attend une date complète au format ISO. Le champ HTML
   * `datetime-local` renvoie « 2026-08-03T14:00 » (sans fuseau) : on le
   * convertit donc en date réelle avant l'envoi.
   */
  async function reschedule(): Promise<void> {
    if (!newDate) return;
    const reason = (await ask("Motif du report ?")) ?? "";
    try {
      await apiClient.post(`/admin/missions/${id}/reschedule`, {
        scheduledAt: new Date(newDate).toISOString(),
        reason: reason.trim() || undefined
      });
      setNewDate("");
      load();
    } catch (rescheduleError) {
      setError(rescheduleError instanceof Error ? rescheduleError.message : "Reprogrammation refusée.");
    }
  }

  if (error) return <p style={{ color: "crimson" }}>{error}</p>;
  if (!mission) return <p>Chargement…</p>;

  const actions = STATUS_ACTIONS[mission.status] ?? [];

  return (
    <div>
      <p>
        <Link to="/missions">← Retour aux missions</Link>
      </p>
      <h1>Mission — {mission.status}</h1>
      <p>
        Client : {[mission.client.firstName, mission.client.lastName].filter(Boolean).join(" ") || mission.client.email} —
        Prestataire : {mission.provider?.publicName ?? "—"}
      </p>
      {/* Prestation vendue : sans elle, la mission n'a ni tarif ni durée. */}
      <p>
        Prestation :{" "}
        {mission.pack ? (
          <>
            <strong>{mission.pack.title}</strong> — {mission.pack.price} F CFA · {mission.pack.durationMinutes} min
            {mission.pack.providerService?.serviceType?.name && ` · ${mission.pack.providerService.serviceType.name}`}
          </>
        ) : (
          <span style={{ color: "#a00" }}>aucune prestation rattachée</span>
        )}
      </p>

      {/* Lieu d'intervention. */}
      <p>
        Lieu :{" "}
        {mission.address ? (
          [mission.address.label, mission.address.commune, mission.address.city, mission.address.details]
            .filter(Boolean)
            .join(", ")
        ) : (
          <span style={{ color: "#a00" }}>aucune adresse rattachée</span>
        )}
      </p>

      {mission.scheduledAt && <p>Planifiée le : {new Date(mission.scheduledAt).toLocaleString("fr-FR")}</p>}
      {mission.instructions && <p>Instructions : {mission.instructions}</p>}
      {mission.cancellation && <p style={{ color: "crimson" }}>Annulée : {mission.cancellation.reason}</p>}

      <h2>Actions</h2>
      {actions.length === 0 ? (
        <p style={{ color: "#666" }}>Aucune action possible (statut final).</p>
      ) : (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {actions.map((a) => (
            <button key={a.status} onClick={() => act(a.status, a.reason)} style={{ padding: 8 }}>
              {a.label}
            </button>
          ))}
        </div>
      )}

      <h2 style={{ marginTop: 24 }}>Reprogrammer</h2>
      <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
        <input
          type="datetime-local"
          value={newDate}
          onChange={(event) => setNewDate(event.target.value)}
          style={{ padding: 6 }}
        />
        <button onClick={reschedule} disabled={!newDate}>
          Reporter la mission
        </button>
      </div>
      {mission.reschedules && mission.reschedules.length > 0 && (
        <ul style={{ color: "#666", fontSize: 13 }}>
          {mission.reschedules.map((item) => (
            <li key={item.id}>
              Reportée au {new Date(item.newScheduledAt).toLocaleString("fr-FR")}
              {item.reason ? ` — ${item.reason}` : ""}
            </li>
          ))}
        </ul>
      )}

      <h2 style={{ marginTop: 24 }}>Historique des statuts</h2>
      <ul>
        {mission.history.map((h) => (
          <li key={h.id}>
            {h.oldStatus ? `${h.oldStatus} → ` : ""}
            <strong>{h.newStatus}</strong>
            {h.reason ? ` (${h.reason})` : ""} — {new Date(h.createdAt).toLocaleString("fr-FR")}
          </li>
        ))}
      </ul>
    </div>
  );
}
