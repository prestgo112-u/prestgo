import { useCallback, useEffect, useState, type ReactElement } from "react";
import { Link, useParams } from "react-router-dom";
import { apiClient } from "../../lib/api-client";
import { useReasonPrompt } from "../../components/prompt";

interface InternalUser {
  id: string;
  email?: string;
  firstName?: string;
  lastName?: string;
  roles: string[];
}

interface DisputeDetail {
  id: string;
  reason: string;
  description?: string;
  status: string;
  decision?: string;
  assignedTo?: string;
  messages: { id: string; message: string; createdAt: string }[];
}

// Transitions proposées selon le statut (reflète la machine à états backend).
const STATUS_ACTIONS: Record<string, { status: string; label: string; decision: boolean }[]> = {
  open: [{ status: "in_review", label: "Passer en revue", decision: false }],
  in_review: [
    { status: "waiting_client", label: "Attente client", decision: false },
    { status: "waiting_provider", label: "Attente prestataire", decision: false },
    { status: "resolved", label: "Résoudre", decision: true },
    { status: "rejected", label: "Rejeter", decision: true }
  ],
  waiting_client: [
    { status: "in_review", label: "Reprendre la revue", decision: false },
    { status: "resolved", label: "Résoudre", decision: true }
  ],
  waiting_provider: [
    { status: "in_review", label: "Reprendre la revue", decision: false },
    { status: "resolved", label: "Résoudre", decision: true }
  ],
  resolved: [{ status: "closed", label: "Clôturer", decision: true }],
  rejected: [{ status: "closed", label: "Clôturer", decision: true }],
  closed: []
};

export function DisputeDetailPage(): ReactElement {
  const { id } = useParams<{ id: string }>();
  const ask = useReasonPrompt();
  const [dispute, setDispute] = useState<DisputeDetail | null>(null);
  const [message, setMessage] = useState("");
  const [error, setError] = useState<string | null>(null);
  // Agents internes auxquels le litige peut être confié.
  const [agents, setAgents] = useState<InternalUser[]>([]);
  const [assignee, setAssignee] = useState("");

  const load = useCallback(() => {
    if (!id) return;
    apiClient
      .get<DisputeDetail>(`/admin/disputes/${id}`)
      .then((data) => {
        setDispute(data);
        setAssignee(data.assignedTo ?? "");
      })
      .catch(() => setError("Litige introuvable."));
  }, [id]);

  useEffect(() => load(), [load]);

  // On récupère les comptes internes pour alimenter la liste d'affectation.
  // Un compte est « interne » dès qu'il porte au moins un rôle.
  useEffect(() => {
    apiClient
      .get<InternalUser[]>("/admin/users?limit=100")
      .then((users) => setAgents(users.filter((user) => user.roles.length > 0)))
      .catch(() => setAgents([]));
  }, []);

  // Confie le litige à un agent (CDC §4.5 : « affecter un agent support »).
  async function assign(): Promise<void> {
    if (!assignee) return;
    try {
      await apiClient.patch(`/admin/disputes/${id}/assign`, { assignedTo: assignee });
      load();
    } catch (assignError) {
      setError(assignError instanceof Error ? assignError.message : "Affectation impossible.");
    }
  }

  // Change le statut ; demande une décision motivée si nécessaire.
  async function changeStatus(status: string, needsDecision: boolean): Promise<void> {
    let decision: string | undefined;
    if (needsDecision) {
      decision = (await ask("Décision / motif ?")) ?? "";
      if (!decision.trim()) return;
    }
    try {
      await apiClient.request(`/admin/disputes/${id}/status`, {
        method: "PATCH",
        body: JSON.stringify({ status, decision })
      });
      load();
    } catch {
      setError("Transition non autorisée.");
    }
  }

  // Ajoute un message au fil du litige.
  async function sendMessage(): Promise<void> {
    if (!message.trim()) return;
    await apiClient.post(`/admin/disputes/${id}/messages`, { message });
    setMessage("");
    load();
  }

  if (error) return <p style={{ color: "crimson" }}>{error}</p>;
  if (!dispute) return <p>Chargement…</p>;

  const actions = STATUS_ACTIONS[dispute.status] ?? [];

  return (
    <div>
      <p>
        <Link to="/disputes">← Retour aux litiges</Link>
      </p>
      <h1>Litige — {dispute.status}</h1>
      <p>Motif : {dispute.reason}</p>
      {dispute.description && <p>{dispute.description}</p>}
      {dispute.decision && <p>Décision : {dispute.decision}</p>}

      <h2>Agent en charge</h2>
      <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
        <select value={assignee} onChange={(event) => setAssignee(event.target.value)} style={{ padding: 6 }}>
          <option value="">— Aucun agent —</option>
          {agents.map((agent) => (
            <option key={agent.id} value={agent.id}>
              {[agent.firstName, agent.lastName].filter(Boolean).join(" ") || agent.email} ({agent.roles.join(", ")})
            </option>
          ))}
        </select>
        <button onClick={assign} disabled={!assignee || assignee === dispute.assignedTo}>
          Affecter
        </button>
        {dispute.assignedTo && <span style={{ color: "#666", fontSize: 13 }}>Actuellement affecté.</span>}
      </div>

      <h2>Actions</h2>
      {actions.length === 0 ? (
        <p style={{ color: "#666" }}>Aucune action (litige clôturé).</p>
      ) : (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {actions.map((a) => (
            <button key={a.status} onClick={() => changeStatus(a.status, a.decision)} style={{ padding: 8 }}>
              {a.label}
            </button>
          ))}
        </div>
      )}

      <h2 style={{ marginTop: 24 }}>Messages</h2>
      <ul>
        {dispute.messages.map((m) => (
          <li key={m.id}>
            {m.message} — <em>{new Date(m.createdAt).toLocaleString("fr-FR")}</em>
          </li>
        ))}
      </ul>
      <div style={{ display: "flex", gap: 8 }}>
        <input
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          placeholder="Écrire un message…"
          style={{ flex: 1, padding: 8 }}
        />
        <button onClick={sendMessage}>Envoyer</button>
      </div>
    </div>
  );
}
