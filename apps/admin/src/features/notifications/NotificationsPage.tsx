import { useCallback, useEffect, useState, type ReactElement } from "react";
import { apiClient } from "../../lib/api-client";

interface Notification {
  id: string;
  title: string;
  body: string;
  channel: string;
  status: string;
  createdAt: string;
}

export function NotificationsPage(): ReactElement {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [message, setMessage] = useState<string | null>(null);

  const load = useCallback(() => {
    apiClient
      .get<Notification[]>("/admin/notifications")
      .then(setNotifications)
      .catch(() => setMessage("Impossible de charger les notifications."));
  }, []);

  useEffect(() => load(), [load]);

  // Envoie (met en file) une notification.
  async function send(): Promise<void> {
    if (!title.trim() || !body.trim()) {
      setMessage("Titre et message obligatoires.");
      return;
    }
    try {
      await apiClient.post("/admin/notifications/send", { type: "custom", title, body, channel: "in_app" });
      setTitle("");
      setBody("");
      setMessage("Notification mise en file d'attente.");
      load();
    } catch {
      setMessage("Envoi impossible.");
    }
  }

  return (
    <div>
      <h1>Notifications</h1>
      {message && <p style={{ color: "#0a0" }}>{message}</p>}

      {/* Formulaire d'envoi */}
      <div style={{ display: "grid", gap: 8, maxWidth: 500, marginBottom: 24 }}>
        <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Titre" style={{ padding: 8 }} />
        <textarea value={body} onChange={(e) => setBody(e.target.value)} placeholder="Message" rows={3} style={{ padding: 8 }} />
        <button onClick={send} style={{ padding: 8 }}>
          Envoyer la notification
        </button>
      </div>

      <h2>Historique</h2>
      {notifications.length === 0 ? (
        <p style={{ color: "#666" }}>Aucune notification.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Titre</th>
              <th style={{ padding: 8 }}>Canal</th>
              <th style={{ padding: 8 }}>Statut</th>
              <th style={{ padding: 8 }}>Date</th>
            </tr>
          </thead>
          <tbody>
            {notifications.map((n) => (
              <tr key={n.id} style={{ borderBottom: "1px solid #eee" }}>
                <td style={{ padding: 8 }}>{n.title}</td>
                <td style={{ padding: 8 }}>{n.channel}</td>
                <td style={{ padding: 8 }}>{n.status}</td>
                <td style={{ padding: 8 }}>{new Date(n.createdAt).toLocaleString("fr-FR")}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
