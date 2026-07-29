import { useCallback, useEffect, useState, type ReactElement } from "react";
import { Link } from "react-router-dom";
import { apiClient } from "../../lib/api-client";

interface Client {
  id: string;
  email?: string;
  phone?: string;
  firstName?: string;
  lastName?: string;
  status: string;
  missionCount: number;
  hasNotes: boolean;
  createdAt: string;
}

const STATUSES = ["", "draft", "pending", "active", "rejected", "suspended", "deleted"];

export function ClientsPage(): ReactElement {
  const [clients, setClients] = useState<Client[]>([]);
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("");
  const [page, setPage] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const limit = 20;

  const load = useCallback(() => {
    const params = new URLSearchParams({ page: String(page), limit: String(limit) });
    if (search.trim()) params.set("search", search.trim());
    if (status) params.set("status", status);

    apiClient
      .get<Client[]>(`/admin/clients?${params.toString()}`)
      .then((rows) => {
        setClients(rows);
        setError(null);
      })
      .catch((loadError) => setError(loadError instanceof Error ? loadError.message : "Chargement impossible."));
  }, [page, search, status]);

  useEffect(() => load(), [load]);

  return (
    <div>
      <h1>Clients</h1>
      <p style={{ color: "#666" }}>
        Comptes qui commandent des prestations (ni prestataires, ni membres des équipes internes).
      </p>

      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
        <input
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setPage(1); // toute nouvelle recherche repart de la première page
          }}
          placeholder="Nom, email ou téléphone…"
          style={{ padding: 6, minWidth: 240 }}
        />
        <select
          value={status}
          onChange={(event) => {
            setStatus(event.target.value);
            setPage(1);
          }}
          style={{ padding: 6 }}
        >
          {STATUSES.map((value) => (
            <option key={value} value={value}>
              {value === "" ? "Tous les statuts" : value}
            </option>
          ))}
        </select>
      </div>

      {error && <p style={{ color: "crimson" }}>{error}</p>}

      {clients.length === 0 ? (
        <p style={{ color: "#666" }}>Aucun client à afficher.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Email</th>
              <th style={{ padding: 8 }}>Nom</th>
              <th style={{ padding: 8 }}>Téléphone</th>
              <th style={{ padding: 8 }}>Statut</th>
              <th style={{ padding: 8 }}>Missions</th>
              <th style={{ padding: 8 }}>Note interne</th>
              <th style={{ padding: 8 }}>Inscrit le</th>
            </tr>
          </thead>
          <tbody>
            {clients.map((client) => (
              <tr key={client.id} style={{ borderBottom: "1px solid #eee" }}>
                <td style={{ padding: 8 }}>
                  <Link to={`/clients/${client.id}`}>{client.email ?? "—"}</Link>
                </td>
                <td style={{ padding: 8 }}>{[client.firstName, client.lastName].filter(Boolean).join(" ") || "—"}</td>
                <td style={{ padding: 8 }}>{client.phone ?? "—"}</td>
                <td style={{ padding: 8 }}>{client.status}</td>
                <td style={{ padding: 8 }}>{client.missionCount}</td>
                <td style={{ padding: 8 }}>{client.hasNotes ? "oui" : "—"}</td>
                <td style={{ padding: 8 }}>{new Date(client.createdAt).toLocaleDateString("fr-FR")}</td>
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
        <button disabled={clients.length < limit} onClick={() => setPage((current) => current + 1)}>
          Suivant
        </button>
      </div>
    </div>
  );
}
