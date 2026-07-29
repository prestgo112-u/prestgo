import { useCallback, useEffect, useState, type ReactElement } from "react";
import { Link } from "react-router-dom";
import { apiClient } from "../../lib/api-client";

interface Dispute {
  id: string;
  missionId: string;
  reason: string;
  status: string;
  assignedTo: string | null;
  clientName: string;
  providerName: string;
  createdAt: string;
}

const STATUS_OPTIONS = ["", "open", "in_review", "waiting_client", "waiting_provider", "resolved", "rejected", "closed"];

export function DisputesPage(): ReactElement {
  const [disputes, setDisputes] = useState<Dispute[]>([]);
  const [status, setStatus] = useState("");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const limit = 20;

  const load = useCallback(() => {
    const params = new URLSearchParams({ page: String(page), limit: String(limit) });
    if (status) params.set("status", status);
    if (search.trim()) params.set("search", search.trim());

    apiClient
      .get<Dispute[]>(`/admin/disputes?${params.toString()}`)
      .then((rows) => {
        setDisputes(rows);
        setError(null);
      })
      .catch((loadError) => setError(loadError instanceof Error ? loadError.message : "Chargement impossible."));
  }, [page, status, search]);

  useEffect(() => load(), [load]);

  return (
    <div>
      <h1>Litiges</h1>

      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
        <select
          value={status}
          onChange={(event) => {
            setStatus(event.target.value);
            setPage(1);
          }}
          style={{ padding: 6 }}
        >
          {STATUS_OPTIONS.map((value) => (
            <option key={value} value={value}>
              {value === "" ? "Tous les statuts" : value}
            </option>
          ))}
        </select>
        <input
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setPage(1);
          }}
          placeholder="Motif ou description…"
          style={{ padding: 6, minWidth: 240 }}
        />
      </div>

      {error && <p style={{ color: "crimson" }}>{error}</p>}

      {disputes.length === 0 ? (
        <p style={{ color: "#666" }}>Aucun litige.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Motif</th>
              <th style={{ padding: 8 }}>Client</th>
              <th style={{ padding: 8 }}>Prestataire</th>
              <th style={{ padding: 8 }}>Statut</th>
              <th style={{ padding: 8 }}>Assigné</th>
              <th style={{ padding: 8 }}>Ouvert le</th>
              <th style={{ padding: 8 }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {disputes.map((dispute) => (
              <tr key={dispute.id} style={{ borderBottom: "1px solid #eee" }}>
                <td style={{ padding: 8 }}>{dispute.reason}</td>
                <td style={{ padding: 8 }}>{dispute.clientName}</td>
                <td style={{ padding: 8 }}>{dispute.providerName}</td>
                <td style={{ padding: 8 }}>{dispute.status}</td>
                <td style={{ padding: 8 }}>{dispute.assignedTo ? "oui" : "—"}</td>
                <td style={{ padding: 8 }}>{new Date(dispute.createdAt).toLocaleDateString("fr-FR")}</td>
                <td style={{ padding: 8 }}>
                  <Link to={`/disputes/${dispute.id}`}>Traiter</Link>
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
        <button disabled={disputes.length < limit} onClick={() => setPage((current) => current + 1)}>
          Suivant
        </button>
      </div>
    </div>
  );
}
