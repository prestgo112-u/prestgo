import { useCallback, useEffect, useState, type ReactElement } from "react";
import { Link } from "react-router-dom";
import { apiClient } from "../../lib/api-client";
import { useReasonPrompt } from "../../components/prompt";
import { FilePreview } from "../../components/FilePreview";

interface QueueItem {
  id: string;
  type: string;
  status: string;
  createdAt: string;
  fileId: string | null;
  fileName: string | null;
  providerId: string;
  providerName: string;
  providerEmail?: string;
  providerStatus: string;
}

const STATUSES = ["pending", "approved", "rejected"];

/**
 * File d'attente de vérification, tous prestataires confondus.
 *
 * Avant, il fallait ouvrir chaque prestataire un par un pour découvrir s'il
 * avait des documents à examiner. Cet écran centralise le travail des agents.
 */
export function VerificationsPage(): ReactElement {
  const ask = useReasonPrompt();
  const [items, setItems] = useState<QueueItem[]>([]);
  const [status, setStatus] = useState("pending");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const [previewFileId, setPreviewFileId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const limit = 20;

  const load = useCallback(() => {
    const params = new URLSearchParams({ page: String(page), limit: String(limit), status });
    if (search.trim()) params.set("search", search.trim());

    apiClient
      .get<QueueItem[]>(`/admin/verifications/providers?${params.toString()}`)
      .then((rows) => {
        setItems(rows);
        setError(null);
      })
      .catch((loadError) => setError(loadError instanceof Error ? loadError.message : "Chargement impossible."));
  }, [page, status, search]);

  useEffect(() => load(), [load]);

  async function approve(documentId: string): Promise<void> {
    try {
      await apiClient.post(`/admin/verifications/documents/${documentId}/approve`, {});
      load();
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : "Approbation impossible.");
    }
  }

  async function reject(documentId: string): Promise<void> {
    const reason = (await ask("Motif du rejet du document ?")) ?? "";
    if (!reason.trim()) return;
    try {
      await apiClient.post(`/admin/verifications/documents/${documentId}/reject`, { reason });
      load();
    } catch (actionError) {
      setError(actionError instanceof Error ? actionError.message : "Rejet impossible.");
    }
  }

  return (
    <div>
      <h1>Vérifications</h1>
      <p style={{ color: "#666" }}>Documents à examiner, du plus ancien au plus récent.</p>

      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
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
              {value === "pending" ? "En attente" : value === "approved" ? "Approuvés" : "Rejetés"}
            </option>
          ))}
        </select>
        <input
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setPage(1);
          }}
          placeholder="Nom du prestataire…"
          style={{ padding: 6, minWidth: 220 }}
        />
      </div>

      {error && <p style={{ color: "crimson" }}>{error}</p>}

      {items.length === 0 ? (
        <p style={{ color: "#666" }}>Aucun document dans cette file.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Prestataire</th>
              <th style={{ padding: 8 }}>Type</th>
              <th style={{ padding: 8 }}>Justificatif</th>
              <th style={{ padding: 8 }}>Déposé le</th>
              <th style={{ padding: 8 }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {items.map((item) => (
              <tr key={item.id} style={{ borderBottom: "1px solid #eee" }}>
                <td style={{ padding: 8 }}>
                  <Link to={`/providers/${item.providerId}`}>{item.providerName}</Link>
                  <div style={{ color: "#888", fontSize: 12 }}>{item.providerStatus}</div>
                </td>
                <td style={{ padding: 8 }}>{item.type}</td>
                <td style={{ padding: 8 }}>
                  {item.fileId ? (
                    <button onClick={() => setPreviewFileId(item.fileId)}>Consulter</button>
                  ) : (
                    <span style={{ color: "#a00" }}>aucun fichier</span>
                  )}
                </td>
                <td style={{ padding: 8 }}>{new Date(item.createdAt).toLocaleDateString("fr-FR")}</td>
                <td style={{ padding: 8, display: "flex", gap: 8 }}>
                  {/* On ne décide jamais sans avoir pu ouvrir la pièce. */}
                  <button onClick={() => approve(item.id)} disabled={!item.fileId || item.status !== "pending"}>
                    Approuver
                  </button>
                  <button onClick={() => reject(item.id)} disabled={!item.fileId || item.status !== "pending"}>
                    Rejeter
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {previewFileId && <FilePreview fileId={previewFileId} onClose={() => setPreviewFileId(null)} />}

      <div style={{ display: "flex", gap: 8, marginTop: 16, alignItems: "center" }}>
        <button disabled={page <= 1} onClick={() => setPage((current) => current - 1)}>
          Précédent
        </button>
        <span>Page {page}</span>
        <button disabled={items.length < limit} onClick={() => setPage((current) => current + 1)}>
          Suivant
        </button>
      </div>
    </div>
  );
}
