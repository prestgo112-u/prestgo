import { useCallback, useEffect, useState, type ReactElement } from "react";
import { apiClient } from "../../lib/api-client";

interface AuditLog {
  action: string;
  entity: string;
  entityId?: string;
  actorId?: string;
  createdAt: string;
}

export function AuditLogPage(): ReactElement {
  const [logs, setLogs] = useState<AuditLog[]>([]);
  const [entity, setEntity] = useState("");
  const [page, setPage] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const limit = 20;

  const load = useCallback(() => {
    const params = new URLSearchParams({ page: String(page), limit: String(limit) });
    if (entity) params.set("entity", entity);
    apiClient
      .get<AuditLog[]>(`/admin/audit-logs?${params.toString()}`)
      .then(setLogs)
      .catch(() => setError("Impossible de charger le journal d'audit."));
  }, [page, entity]);

  useEffect(() => load(), [load]);

  if (error) return <p style={{ color: "crimson" }}>{error}</p>;

  return (
    <div>
      <h1>Journal d'audit</h1>

      <label style={{ display: "block", marginBottom: 16 }}>
        Filtrer par entité :{" "}
        <input
          value={entity}
          onChange={(e) => {
            setPage(1);
            setEntity(e.target.value);
          }}
          placeholder="ex. Mission, ProviderProfile…"
          style={{ padding: 6 }}
        />
      </label>

      {logs.length === 0 ? (
        <p style={{ color: "#666" }}>Aucune entrée.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Action</th>
              <th style={{ padding: 8 }}>Entité</th>
              <th style={{ padding: 8 }}>Acteur</th>
              <th style={{ padding: 8 }}>Date</th>
            </tr>
          </thead>
          <tbody>
            {logs.map((log, index) => (
              <tr key={index} style={{ borderBottom: "1px solid #eee" }}>
                <td style={{ padding: 8 }}>{log.action}</td>
                <td style={{ padding: 8 }}>{log.entity}</td>
                <td style={{ padding: 8, fontSize: 12 }}>{log.actorId ?? "—"}</td>
                <td style={{ padding: 8 }}>{new Date(log.createdAt).toLocaleString("fr-FR")}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <div style={{ display: "flex", gap: 8, marginTop: 16, alignItems: "center" }}>
        <button disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
          Précédent
        </button>
        <span>Page {page}</span>
        <button disabled={logs.length < limit} onClick={() => setPage((p) => p + 1)}>
          Suivant
        </button>
      </div>
    </div>
  );
}
