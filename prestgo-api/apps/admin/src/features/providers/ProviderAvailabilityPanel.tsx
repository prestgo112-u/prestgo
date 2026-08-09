import { useCallback, useEffect, useState, type ReactElement } from "react";
import { apiClient } from "../../lib/api-client";

interface Slot {
  id: string;
  weekday: number;
  startTime: string;
  endTime: string;
}

const WEEKDAYS = ["Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"];

// Panneau de gestion des disponibilités hebdomadaires d'un prestataire.
export function ProviderAvailabilityPanel({ providerId }: { providerId: string }): ReactElement {
  const [slots, setSlots] = useState<Slot[]>([]);
  const [weekday, setWeekday] = useState(1);
  const [startTime, setStartTime] = useState("09:00");
  const [endTime, setEndTime] = useState("12:00");
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    apiClient
      .get<Slot[]>(`/admin/providers/${providerId}/availability`)
      .then(setSlots)
      .catch(() => setError("Impossible de charger les disponibilités."));
  }, [providerId]);

  useEffect(() => load(), [load]);

  // Ajoute un créneau (le backend refuse les chevauchements et fin ≤ début).
  async function add(): Promise<void> {
    try {
      await apiClient.post(`/admin/providers/${providerId}/availability`, { weekday, startTime, endTime });
      setError(null);
      load();
    } catch {
      setError("Créneau refusé (chevauchement, ou heure de fin avant le début).");
    }
  }

  async function remove(id: string): Promise<void> {
    await apiClient.delete(`/admin/providers/${providerId}/availability/${id}`);
    load();
  }

  return (
    <div style={{ marginTop: 24 }}>
      <h2>Disponibilités</h2>
      {error && <p style={{ color: "crimson" }}>{error}</p>}

      {slots.length === 0 ? (
        <p style={{ color: "#666" }}>Aucun créneau.</p>
      ) : (
        <ul>
          {slots.map((s) => (
            <li key={s.id}>
              {WEEKDAYS[s.weekday]} {s.startTime}–{s.endTime}{" "}
              <button onClick={() => remove(s.id)}>Supprimer</button>
            </li>
          ))}
        </ul>
      )}

      {/* Ajout d'un créneau */}
      <div style={{ display: "flex", gap: 8, alignItems: "center", marginTop: 8 }}>
        <select value={weekday} onChange={(e) => setWeekday(Number(e.target.value))} style={{ padding: 4 }}>
          {WEEKDAYS.map((label, index) => (
            <option key={index} value={index}>
              {label}
            </option>
          ))}
        </select>
        <input type="time" value={startTime} onChange={(e) => setStartTime(e.target.value)} />
        <input type="time" value={endTime} onChange={(e) => setEndTime(e.target.value)} />
        <button onClick={add}>Ajouter le créneau</button>
      </div>
    </div>
  );
}
