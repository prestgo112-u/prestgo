import { useEffect, useState, type ReactElement } from "react";
import { apiClient } from "../../lib/api-client";

interface Thread {
  id: string;
  missionId: string;
  missionStatus: string;
  messageCount: number;
  createdAt: string;
}

interface ThreadDetail {
  id: string;
  messages: { id: string; senderId?: string; message: string; createdAt: string }[];
}

export function MessagesPage(): ReactElement {
  const [threads, setThreads] = useState<Thread[]>([]);
  const [selected, setSelected] = useState<ThreadDetail | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiClient
      .get<Thread[]>("/admin/messages/threads")
      .then(setThreads)
      .catch(() => setError("Impossible de charger les fils de discussion."));
  }, []);

  // Ouvre un fil pour lire ses messages (supervision, lecture seule).
  async function openThread(threadId: string): Promise<void> {
    const detail = await apiClient.get<ThreadDetail>(`/admin/messages/threads/${threadId}`);
    setSelected(detail);
  }

  if (error) return <p style={{ color: "crimson" }}>{error}</p>;

  return (
    <div>
      <h1>Supervision des messages</h1>
      <div style={{ display: "flex", gap: 24 }}>
        {/* Colonne gauche : liste des fils */}
        <div style={{ flex: "0 0 320px" }}>
          {threads.length === 0 ? (
            <p style={{ color: "#666" }}>Aucun fil de discussion.</p>
          ) : (
            <ul style={{ listStyle: "none", padding: 0 }}>
              {threads.map((t) => (
                <li key={t.id} style={{ marginBottom: 8 }}>
                  <button onClick={() => openThread(t.id)} style={{ width: "100%", textAlign: "left", padding: 8 }}>
                    Mission {t.missionStatus} — {t.messageCount} message(s)
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Colonne droite : messages du fil sélectionné */}
        <div style={{ flex: 1 }}>
          {!selected ? (
            <p style={{ color: "#666" }}>Sélectionnez un fil pour lire les messages.</p>
          ) : (
            <ul>
              {selected.messages.map((m) => (
                <li key={m.id} style={{ marginBottom: 8 }}>
                  {m.message} — <em>{new Date(m.createdAt).toLocaleString("fr-FR")}</em>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
}
