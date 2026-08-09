import { useCallback, useEffect, useState, type ReactElement } from "react";
import { apiClient } from "../../lib/api-client";

interface ExportJob {
  id: string;
  type: string;
  status: string;
  fileId?: string;
  createdAt: string;
  completedAt?: string;
}

const EXPORT_TYPES = ["users", "providers", "missions", "disputes", "reviews"];

export function ExportsPage(): ReactElement {
  const [jobs, setJobs] = useState<ExportJob[]>([]);
  const [type, setType] = useState("users");
  const [message, setMessage] = useState<string | null>(null);

  const load = useCallback(() => {
    apiClient
      .get<ExportJob[]>("/admin/exports")
      .then(setJobs)
      .catch(() => setMessage("Impossible de charger les exports."));
  }, []);

  useEffect(() => load(), [load]);

  // Demande un nouvel export (le fichier généré est à accès restreint).
  async function requestExport(): Promise<void> {
    try {
      await apiClient.post("/admin/exports", { type });
      setMessage("Export généré.");
      load();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Demande d'export impossible.");
    }
  }

  /**
   * Télécharge le CSV produit.
   *
   * Le fichier est protégé : on ne peut pas l'atteindre par un simple lien, il
   * faut envoyer le token. On récupère donc son contenu, puis on simule un clic
   * sur un lien de téléchargement.
   */
  async function downloadExport(job: ExportJob): Promise<void> {
    if (!job.fileId) return;
    try {
      const url = await apiClient.fetchBlobUrl(`/files/${job.fileId}/content`);
      const link = document.createElement("a");
      link.href = url;
      link.download = `${job.type}-${job.id}.csv`;
      link.click();
      // On libère la mémoire une fois le téléchargement lancé.
      URL.revokeObjectURL(url);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Téléchargement impossible.");
    }
  }

  return (
    <div>
      <h1>Exports</h1>
      {message && <p style={{ color: "#0a0" }}>{message}</p>}

      <div style={{ display: "flex", gap: 8, marginBottom: 24, alignItems: "center" }}>
        <select value={type} onChange={(e) => setType(e.target.value)} style={{ padding: 6 }}>
          {EXPORT_TYPES.map((t) => (
            <option key={t} value={t}>
              {t}
            </option>
          ))}
        </select>
        <button onClick={requestExport}>Demander un export</button>
      </div>

      {jobs.length === 0 ? (
        <p style={{ color: "#666" }}>Aucun export.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Type</th>
              <th style={{ padding: 8 }}>Statut</th>
              <th style={{ padding: 8 }}>Fichier</th>
              <th style={{ padding: 8 }}>Date</th>
            </tr>
          </thead>
          <tbody>
            {jobs.map((j) => (
              <tr key={j.id} style={{ borderBottom: "1px solid #eee" }}>
                <td style={{ padding: 8 }}>{j.type}</td>
                <td style={{ padding: 8 }}>{j.status}</td>
                <td style={{ padding: 8 }}>
                  {j.fileId ? <button onClick={() => downloadExport(j)}>Télécharger le CSV</button> : "—"}
                </td>
                <td style={{ padding: 8 }}>{new Date(j.createdAt).toLocaleString("fr-FR")}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
