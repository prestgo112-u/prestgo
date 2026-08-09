import { useCallback, useEffect, useState, type ReactElement } from "react";
import { apiClient } from "../../lib/api-client";
import { ZoneEditor } from "./ZoneEditor";

interface Zone {
  id: string;
  name: string;
  latitude?: number;
  longitude?: number;
  radiusKm?: number;
  active: boolean;
}

export function ZonesPage(): ReactElement {
  const [zones, setZones] = useState<Zone[]>([]);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    apiClient
      .get<Zone[]>("/admin/zones")
      .then(setZones)
      .catch(() => setError("Impossible de charger les zones."));
  }, []);

  useEffect(() => load(), [load]);

  // Active/désactive une zone.
  async function toggle(zone: Zone): Promise<void> {
    try {
      await apiClient.request(`/admin/zones/${zone.id}`, {
        method: "PATCH",
        body: JSON.stringify({ active: !zone.active })
      });
      load();
    } catch {
      setError("Modification refusée (coordonnées manquantes pour activer ?).");
    }
  }

  return (
    <div>
      <h1>Zones</h1>
      {error && <p style={{ color: "crimson" }}>{error}</p>}

      <ZoneEditor onCreated={load} />

      {zones.length === 0 ? (
        <p style={{ color: "#666" }}>Aucune zone.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Nom</th>
              <th style={{ padding: 8 }}>Coordonnées</th>
              <th style={{ padding: 8 }}>Rayon</th>
              <th style={{ padding: 8 }}>Statut</th>
              <th style={{ padding: 8 }}>Action</th>
            </tr>
          </thead>
          <tbody>
            {zones.map((z) => (
              <tr key={z.id} style={{ borderBottom: "1px solid #eee", opacity: z.active ? 1 : 0.5 }}>
                <td style={{ padding: 8 }}>{z.name}</td>
                <td style={{ padding: 8 }}>{z.latitude != null ? `${z.latitude}, ${z.longitude}` : "—"}</td>
                <td style={{ padding: 8 }}>{z.radiusKm != null ? `${z.radiusKm} km` : "—"}</td>
                <td style={{ padding: 8 }}>{z.active ? "actif" : "inactif"}</td>
                <td style={{ padding: 8 }}>
                  <button onClick={() => toggle(z)}>{z.active ? "Désactiver" : "Réactiver"}</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
