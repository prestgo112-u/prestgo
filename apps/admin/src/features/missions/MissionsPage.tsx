import { useCallback, useEffect, useState, type ReactElement } from "react";
import { Link } from "react-router-dom";
import { apiClient } from "../../lib/api-client";

interface Mission {
  id: string;
  status: string;
  clientName: string;
  providerName: string;
  packTitle: string;
  city: string;
  scheduledAt?: string;
  createdAt: string;
}

const STATUS_OPTIONS = [
  "",
  "draft",
  "pending_provider",
  "confirmed",
  "in_progress",
  "completed",
  "closed",
  "cancelled",
  "disputed"
];

export function MissionsPage(): ReactElement {
  const [missions, setMissions] = useState<Mission[]>([]);
  const [status, setStatus] = useState("");
  const [search, setSearch] = useState("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [page, setPage] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const limit = 20;

  const load = useCallback(() => {
    const params = new URLSearchParams({ page: String(page), limit: String(limit) });
    if (status) params.set("status", status);
    if (search.trim()) params.set("search", search.trim());
    if (from) params.set("from", from);
    if (to) params.set("to", to);

    apiClient
      .get<Mission[]>(`/admin/missions?${params.toString()}`)
      .then((rows) => {
        setMissions(rows);
        setError(null);
      })
      .catch((loadError) => setError(loadError instanceof Error ? loadError.message : "Chargement impossible."));
  }, [page, status, search, from, to]);

  useEffect(() => load(), [load]);

  // Tout changement de filtre ramène à la première page : sinon on pourrait
  // se retrouver sur une page vide.
  function updateFilter(setter: (value: string) => void, value: string): void {
    setter(value);
    setPage(1);
  }

  function resetFilters(): void {
    setStatus("");
    setSearch("");
    setFrom("");
    setTo("");
    setPage(1);
  }

  return (
    <div>
      <h1>Missions</h1>

      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap", alignItems: "center" }}>
        <select value={status} onChange={(event) => updateFilter(setStatus, event.target.value)} style={{ padding: 6 }}>
          {STATUS_OPTIONS.map((value) => (
            <option key={value} value={value}>
              {value === "" ? "Tous les statuts" : value}
            </option>
          ))}
        </select>
        <input
          value={search}
          onChange={(event) => updateFilter(setSearch, event.target.value)}
          placeholder="Client, prestataire ou ville…"
          style={{ padding: 6, minWidth: 220 }}
        />
        <label style={{ fontSize: 13, color: "#666" }}>
          Du{" "}
          <input type="date" value={from} onChange={(event) => updateFilter(setFrom, event.target.value)} style={{ padding: 4 }} />
        </label>
        <label style={{ fontSize: 13, color: "#666" }}>
          au{" "}
          <input type="date" value={to} onChange={(event) => updateFilter(setTo, event.target.value)} style={{ padding: 4 }} />
        </label>
        <button onClick={resetFilters}>Réinitialiser</button>
      </div>

      {error && <p style={{ color: "crimson" }}>{error}</p>}

      {missions.length === 0 ? (
        <p style={{ color: "#666" }}>Aucune mission.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Client</th>
              <th style={{ padding: 8 }}>Prestataire</th>
              <th style={{ padding: 8 }}>Prestation</th>
              <th style={{ padding: 8 }}>Ville</th>
              <th style={{ padding: 8 }}>Planifiée</th>
              <th style={{ padding: 8 }}>Statut</th>
              <th style={{ padding: 8 }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {missions.map((mission) => (
              <tr key={mission.id} style={{ borderBottom: "1px solid #eee" }}>
                <td style={{ padding: 8 }}>{mission.clientName}</td>
                <td style={{ padding: 8 }}>{mission.providerName}</td>
                <td style={{ padding: 8 }}>{mission.packTitle}</td>
                <td style={{ padding: 8 }}>{mission.city}</td>
                <td style={{ padding: 8 }}>
                  {mission.scheduledAt ? new Date(mission.scheduledAt).toLocaleString("fr-FR") : "—"}
                </td>
                <td style={{ padding: 8 }}>{mission.status}</td>
                <td style={{ padding: 8 }}>
                  <Link to={`/missions/${mission.id}`}>Superviser</Link>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <div style={{ display: "flex", gap: 8, marginTop: 16, alignItems: "center" }}>
        <button disabled={page <= 1} onClick={() => setPage((current) => current - 1)}>
          Précédent
        </button>
        <span>Page {page}</span>
        <button disabled={missions.length < limit} onClick={() => setPage((current) => current + 1)}>
          Suivant
        </button>
      </div>
    </div>
  );
}
