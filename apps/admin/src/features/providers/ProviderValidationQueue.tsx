import { useCallback, useEffect, useState, type ReactElement } from "react";
import { Link } from "react-router-dom";
import { apiClient } from "../../lib/api-client";

// Un prestataire dans la file de validation.
interface Provider {
  id: string;
  publicName: string;
  email?: string;
  validationStatus: string;
  availabilityStatus: string;
  score: number;
  createdAt: string;
}

// Les statuts qu'on peut filtrer, avec un libellé lisible en français.
const STATUS_FILTERS: { value: string; label: string }[] = [
  { value: "pending_review", label: "En attente de revue" },
  { value: "changes_requested", label: "Corrections demandées" },
  { value: "approved", label: "Approuvés" },
  { value: "rejected", label: "Rejetés" },
  { value: "suspended", label: "Suspendus" },
  { value: "", label: "Tous" }
];

export function ProviderValidationQueue(): ReactElement {
  const [providers, setProviders] = useState<Provider[]>([]);
  const [status, setStatus] = useState("pending_review");
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const limit = 20;

  const load = useCallback(() => {
    const params = new URLSearchParams({ page: String(page), limit: String(limit) });
    if (status) params.set("validationStatus", status);
    // Le backend cherche dans le nom public, l'email ET le téléphone.
    if (search.trim()) params.set("search", search.trim());

    apiClient
      .get<Provider[]>(`/admin/providers?${params.toString()}`)
      .then((rows) => {
        setProviders(rows);
        setError(null);
      })
      .catch((loadError) => setError(loadError instanceof Error ? loadError.message : "Chargement impossible."));
  }, [page, status, search]);

  useEffect(() => load(), [load]);

  return (
    <div>
      <h1>Prestataires</h1>

      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
        <select
          value={status}
          onChange={(event) => {
            setStatus(event.target.value);
            setPage(1);
          }}
          style={{ padding: 6 }}
        >
          {STATUS_FILTERS.map((filter) => (
            <option key={filter.value} value={filter.value}>
              {filter.label}
            </option>
          ))}
        </select>
        <input
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setPage(1);
          }}
          placeholder="Nom, email ou téléphone…"
          style={{ padding: 6, minWidth: 240 }}
        />
      </div>

      {error && <p style={{ color: "crimson" }}>{error}</p>}

      {providers.length === 0 ? (
        <p style={{ color: "#666" }}>Aucun prestataire pour ce filtre.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Nom public</th>
              <th style={{ padding: 8 }}>Email</th>
              <th style={{ padding: 8 }}>Statut</th>
              <th style={{ padding: 8 }}>Disponibilité</th>
              <th style={{ padding: 8 }}>Score</th>
              <th style={{ padding: 8 }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {providers.map((provider) => (
              <tr key={provider.id} style={{ borderBottom: "1px solid #eee" }}>
                <td style={{ padding: 8 }}>{provider.publicName}</td>
                <td style={{ padding: 8 }}>{provider.email ?? "—"}</td>
                <td style={{ padding: 8 }}>{provider.validationStatus}</td>
                <td style={{ padding: 8 }}>{provider.availabilityStatus}</td>
                <td style={{ padding: 8 }}>{provider.score}</td>
                <td style={{ padding: 8 }}>
                  <Link to={`/providers/${provider.id}`}>Examiner</Link>
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
        <button disabled={providers.length < limit} onClick={() => setPage((current) => current + 1)}>
          Suivant
        </button>
      </div>
    </div>
  );
}
