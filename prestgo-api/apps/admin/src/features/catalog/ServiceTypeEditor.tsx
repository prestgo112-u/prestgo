import { useState, type ReactElement } from "react";
import { apiClient } from "../../lib/api-client";

// Petit formulaire pour ajouter un type de service à une catégorie donnée.
// "onCreated" est appelé après création pour rafraîchir la liste du parent.
export function ServiceTypeEditor({ categoryId, onCreated }: { categoryId: string; onCreated: () => void }): ReactElement {
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);

  // Transforme un nom en "slug" (identifiant en minuscules sans espaces).
  function toSlug(value: string): string {
    return value
      .toLowerCase()
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "") // enlève les accents
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/(^-|-$)/g, "");
  }

  async function add(): Promise<void> {
    if (!name.trim()) return;
    try {
      await apiClient.post("/admin/service-types", { categoryId, name, slug: toSlug(name) });
      setName("");
      onCreated();
    } catch {
      setError("Ajout impossible (slug déjà utilisé ?).");
    }
  }

  return (
    <div style={{ display: "flex", gap: 6, marginTop: 6 }}>
      <input
        value={name}
        onChange={(e) => setName(e.target.value)}
        placeholder="Nouveau type de service…"
        style={{ padding: 4 }}
      />
      <button onClick={add}>Ajouter</button>
      {error && <span style={{ color: "crimson" }}>{error}</span>}
    </div>
  );
}
