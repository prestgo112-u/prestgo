import { useState, type ReactElement } from "react";
import { apiClient } from "../../lib/api-client";

// Formulaire d'ajout d'une zone. Une zone active exige des coordonnées et un rayon > 0.
export function ZoneEditor({ onCreated }: { onCreated: () => void }): ReactElement {
  const [name, setName] = useState("");
  const [latitude, setLatitude] = useState("");
  const [longitude, setLongitude] = useState("");
  const [radiusKm, setRadiusKm] = useState("");
  const [error, setError] = useState<string | null>(null);

  async function add(): Promise<void> {
    if (!name.trim()) return;
    try {
      await apiClient.post("/admin/zones", {
        name,
        // Number("") vaut 0, donc on met undefined si le champ est vide.
        latitude: latitude ? Number(latitude) : undefined,
        longitude: longitude ? Number(longitude) : undefined,
        radiusKm: radiusKm ? Number(radiusKm) : undefined,
        active: true
      });
      setName("");
      setLatitude("");
      setLongitude("");
      setRadiusKm("");
      setError(null);
      onCreated();
    } catch {
      setError("Création refusée : une zone active exige latitude, longitude et un rayon positif.");
    }
  }

  return (
    <div style={{ marginBottom: 24 }}>
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "center" }}>
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Nom de la zone" style={{ padding: 6 }} />
        <input value={latitude} onChange={(e) => setLatitude(e.target.value)} placeholder="Latitude" style={{ padding: 6, width: 100 }} />
        <input value={longitude} onChange={(e) => setLongitude(e.target.value)} placeholder="Longitude" style={{ padding: 6, width: 100 }} />
        <input value={radiusKm} onChange={(e) => setRadiusKm(e.target.value)} placeholder="Rayon (km)" style={{ padding: 6, width: 90 }} />
        <button onClick={add}>Ajouter la zone</button>
      </div>
      {error && <p style={{ color: "crimson", margin: "6px 0 0" }}>{error}</p>}
    </div>
  );
}
