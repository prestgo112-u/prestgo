import { useCallback, useEffect, useState, type ReactElement } from "react";
import { apiClient } from "../../lib/api-client";

interface Setting {
  key: string;
  value: string;
  type: string;
  description?: string;
}

export function SettingsPage(): ReactElement {
  const [settings, setSettings] = useState<Setting[]>([]);
  // On garde la valeur en cours d'édition pour chaque clé.
  const [edits, setEdits] = useState<Record<string, string>>({});
  const [message, setMessage] = useState<string | null>(null);

  const load = useCallback(() => {
    apiClient
      .get<Setting[]>("/admin/settings")
      .then((data) => {
        setSettings(data);
        setEdits(Object.fromEntries(data.map((s) => [s.key, s.value])));
      })
      .catch(() => setMessage("Impossible de charger les réglages."));
  }, []);

  useEffect(() => load(), [load]);

  // Enregistre la nouvelle valeur d'un réglage (le backend vérifie le type).
  async function save(key: string): Promise<void> {
    try {
      await apiClient.request(`/admin/settings/${key}`, {
        method: "PATCH",
        body: JSON.stringify({ value: edits[key] })
      });
      setMessage(`Réglage "${key}" enregistré.`);
      load();
    } catch {
      setMessage(`Valeur invalide pour "${key}" (mauvais type ?).`);
    }
  }

  return (
    <div>
      <h1>Réglages système</h1>
      {message && <p style={{ color: "#0a0" }}>{message}</p>}

      <table style={{ width: "100%", borderCollapse: "collapse" }}>
        <thead>
          <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
            <th style={{ padding: 8 }}>Clé</th>
            <th style={{ padding: 8 }}>Type</th>
            <th style={{ padding: 8 }}>Valeur</th>
            <th style={{ padding: 8 }}></th>
          </tr>
        </thead>
        <tbody>
          {settings.map((s) => (
            <tr key={s.key} style={{ borderBottom: "1px solid #eee" }}>
              <td style={{ padding: 8 }}>
                {s.key}
                {s.description && <div style={{ color: "#888", fontSize: 12 }}>{s.description}</div>}
              </td>
              <td style={{ padding: 8 }}>{s.type}</td>
              <td style={{ padding: 8 }}>
                <input
                  value={edits[s.key] ?? ""}
                  onChange={(e) => setEdits({ ...edits, [s.key]: e.target.value })}
                  style={{ padding: 6, width: 200 }}
                />
              </td>
              <td style={{ padding: 8 }}>
                <button onClick={() => save(s.key)}>Enregistrer</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
