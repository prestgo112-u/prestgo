import { useCallback, useEffect, useState, type ReactElement } from "react";
import { apiClient } from "../../lib/api-client";
import { useReasonPrompt } from "../../components/prompt";

interface Review {
  id: string;
  rating: number;
  comment?: string;
  status: string;
  reportCount: number;
  createdAt: string;
}

const STATUS_OPTIONS = ["", "published", "reported", "hidden", "rejected"];

export function ReviewsPage(): ReactElement {
  const ask = useReasonPrompt();
  const [reviews, setReviews] = useState<Review[]>([]);
  const [status, setStatus] = useState("reported");
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    const query = status ? `?status=${status}` : "";
    apiClient
      .get<Review[]>(`/admin/reviews${query}`)
      .then(setReviews)
      .catch(() => setError("Impossible de charger les avis."));
  }, [status]);

  useEffect(() => load(), [load]);

  // Modère un avis. Masquer/rejeter demande un motif obligatoire.
  async function moderate(id: string, newStatus: string): Promise<void> {
    let reason: string | undefined;
    if (newStatus === "hidden" || newStatus === "rejected") {
      reason = (await ask("Motif de la modération ?")) ?? "";
      if (!reason.trim()) return;
    }
    try {
      await apiClient.request(`/admin/reviews/${id}/status`, {
        method: "PATCH",
        body: JSON.stringify({ status: newStatus, reason })
      });
      load();
    } catch {
      setError("La modération a échoué.");
    }
  }

  if (error) return <p style={{ color: "crimson" }}>{error}</p>;

  return (
    <div>
      <h1>Modération des avis</h1>
      <label style={{ display: "block", marginBottom: 16 }}>
        Statut :{" "}
        <select value={status} onChange={(e) => setStatus(e.target.value)} style={{ padding: 6 }}>
          {STATUS_OPTIONS.map((s) => (
            <option key={s} value={s}>
              {s === "" ? "Tous" : s}
            </option>
          ))}
        </select>
      </label>

      {reviews.length === 0 ? (
        <p style={{ color: "#666" }}>Aucun avis.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Note</th>
              <th style={{ padding: 8 }}>Commentaire</th>
              <th style={{ padding: 8 }}>Statut</th>
              <th style={{ padding: 8 }}>Signalements</th>
              <th style={{ padding: 8 }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {reviews.map((r) => (
              <tr key={r.id} style={{ borderBottom: "1px solid #eee" }}>
                <td style={{ padding: 8 }}>{r.rating}/5</td>
                <td style={{ padding: 8 }}>{r.comment ?? "—"}</td>
                <td style={{ padding: 8 }}>{r.status}</td>
                <td style={{ padding: 8 }}>{r.reportCount}</td>
                <td style={{ padding: 8, display: "flex", gap: 6 }}>
                  <button onClick={() => moderate(r.id, "published")}>Publier</button>
                  <button onClick={() => moderate(r.id, "hidden")}>Masquer</button>
                  <button onClick={() => moderate(r.id, "rejected")}>Rejeter</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
