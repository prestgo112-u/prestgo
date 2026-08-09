import { useCallback, useEffect, useState, type ReactElement } from "react";
import { Link, useParams } from "react-router-dom";
import { apiClient } from "../../lib/api-client";
import { useAuth } from "../auth/auth.store";

interface ClientDetail {
  id: string;
  email?: string;
  phone?: string;
  firstName?: string;
  lastName?: string;
  status: string;
  createdAt: string;
  missionCount: number;
  notes: string | null;
  addresses: { id: string; label?: string; city?: string; commune?: string; details?: string; isDefault: boolean }[];
}

interface ClientMission {
  id: string;
  status: string;
  scheduledAt?: string;
  providerName: string;
  packTitle: string;
  price: number | null;
  createdAt: string;
}

export function ClientDetailPage(): ReactElement {
  const { id } = useParams<{ id: string }>();
  const { permissions } = useAuth();
  const [client, setClient] = useState<ClientDetail | null>(null);
  const [missions, setMissions] = useState<ClientMission[]>([]);
  const [note, setNote] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const canAddNote = permissions.includes("admin.clients.notes");

  const load = useCallback(() => {
    if (!id) return;
    apiClient
      .get<ClientDetail>(`/admin/clients/${id}`)
      .then(setClient)
      .catch(() => setError("Client introuvable."));
    apiClient
      .get<ClientMission[]>(`/admin/clients/${id}/missions?limit=50`)
      .then(setMissions)
      .catch(() => setMissions([]));
  }, [id]);

  useEffect(() => load(), [load]);

  // Ajoute une note interne : elle s'ajoute aux précédentes, elle ne les écrase pas.
  async function submitNote(): Promise<void> {
    if (!note.trim()) return;
    try {
      await apiClient.post(`/admin/clients/${id}/notes`, { note });
      setNote("");
      setMessage("Note enregistrée.");
      load();
    } catch (noteError) {
      setError(noteError instanceof Error ? noteError.message : "Enregistrement impossible.");
    }
  }

  if (error) return <p style={{ color: "crimson" }}>{error}</p>;
  if (!client) return <p>Chargement…</p>;

  const fullName = [client.firstName, client.lastName].filter(Boolean).join(" ") || client.email || "Client";

  return (
    <div>
      <p>
        <Link to="/clients">← Retour aux clients</Link>
      </p>
      <h1>{fullName}</h1>
      <p style={{ color: "#666" }}>
        {client.email ?? "—"} · {client.phone ?? "pas de téléphone"} · statut : <strong>{client.status}</strong> ·
        inscrit le {new Date(client.createdAt).toLocaleDateString("fr-FR")} · {client.missionCount} mission(s)
      </p>

      <h2>Adresses</h2>
      {client.addresses.length === 0 ? (
        <p style={{ color: "#666" }}>Aucune adresse enregistrée.</p>
      ) : (
        <ul>
          {client.addresses.map((address) => (
            <li key={address.id}>
              {[address.label, address.details, address.commune, address.city].filter(Boolean).join(", ")}
              {address.isDefault && <strong> (par défaut)</strong>}
            </li>
          ))}
        </ul>
      )}

      <h2>Historique des missions</h2>
      {missions.length === 0 ? (
        <p style={{ color: "#666" }}>Aucune mission.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse", marginBottom: 24 }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Prestation</th>
              <th style={{ padding: 8 }}>Prestataire</th>
              <th style={{ padding: 8 }}>Statut</th>
              <th style={{ padding: 8 }}>Prix</th>
              <th style={{ padding: 8 }}>Planifiée</th>
            </tr>
          </thead>
          <tbody>
            {missions.map((mission) => (
              <tr key={mission.id} style={{ borderBottom: "1px solid #eee" }}>
                <td style={{ padding: 8 }}>
                  <Link to={`/missions/${mission.id}`}>{mission.packTitle}</Link>
                </td>
                <td style={{ padding: 8 }}>{mission.providerName}</td>
                <td style={{ padding: 8 }}>{mission.status}</td>
                <td style={{ padding: 8 }}>{mission.price != null ? `${mission.price} F CFA` : "—"}</td>
                <td style={{ padding: 8 }}>
                  {mission.scheduledAt ? new Date(mission.scheduledAt).toLocaleString("fr-FR") : "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <h2>Notes internes</h2>
      <p style={{ color: "#666" }}>Visibles uniquement du back-office, jamais du client.</p>
      {client.notes ? (
        <pre style={{ background: "#f6f6f6", padding: 12, whiteSpace: "pre-wrap" }}>{client.notes}</pre>
      ) : (
        <p style={{ color: "#666" }}>Aucune note.</p>
      )}

      {canAddNote && (
        <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
          <input
            value={note}
            onChange={(event) => setNote(event.target.value)}
            placeholder="Ajouter une note…"
            style={{ padding: 6, flex: 1 }}
          />
          <button onClick={submitNote}>Enregistrer</button>
        </div>
      )}
      {message && <p style={{ color: "#0a0" }}>{message}</p>}
    </div>
  );
}
