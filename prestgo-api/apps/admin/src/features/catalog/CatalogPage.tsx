import { useCallback, useEffect, useState, type ReactElement } from "react";
import { apiClient } from "../../lib/api-client";
import { ServiceTypeEditor } from "./ServiceTypeEditor";

interface ServiceType {
  id: string;
  name: string;
  active: boolean;
}

interface Category {
  id: string;
  name: string;
  slug: string;
  active: boolean;
  serviceTypes: ServiceType[];
}

function toSlug(value: string): string {
  return value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");
}

export function CatalogPage(): ReactElement {
  const [categories, setCategories] = useState<Category[]>([]);
  const [newCategory, setNewCategory] = useState("");
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    apiClient
      .get<Category[]>("/admin/categories")
      .then(setCategories)
      .catch(() => setError("Impossible de charger le catalogue."));
  }, []);

  useEffect(() => load(), [load]);

  // Crée une catégorie.
  async function addCategory(): Promise<void> {
    if (!newCategory.trim()) return;
    try {
      await apiClient.post("/admin/categories", { name: newCategory, slug: toSlug(newCategory) });
      setNewCategory("");
      load();
    } catch {
      setError("Création impossible (slug déjà utilisé ?).");
    }
  }

  // Active ou désactive une catégorie (elle reste dans l'historique).
  async function toggleCategory(cat: Category): Promise<void> {
    await apiClient.request(`/admin/categories/${cat.id}`, {
      method: "PATCH",
      body: JSON.stringify({ active: !cat.active })
    });
    load();
  }

  // Active/désactive un type de service.
  async function toggleType(type: ServiceType): Promise<void> {
    await apiClient.request(`/admin/service-types/${type.id}`, {
      method: "PATCH",
      body: JSON.stringify({ active: !type.active })
    });
    load();
  }

  return (
    <div>
      <h1>Catalogue</h1>
      {error && <p style={{ color: "crimson" }}>{error}</p>}

      {/* Ajouter une catégorie */}
      <div style={{ display: "flex", gap: 8, marginBottom: 24 }}>
        <input
          value={newCategory}
          onChange={(e) => setNewCategory(e.target.value)}
          placeholder="Nouvelle catégorie…"
          style={{ padding: 6 }}
        />
        <button onClick={addCategory}>Ajouter une catégorie</button>
      </div>

      {categories.length === 0 ? (
        <p style={{ color: "#666" }}>Aucune catégorie.</p>
      ) : (
        categories.map((cat) => (
          <div key={cat.id} style={{ border: "1px solid #e0e0e0", borderRadius: 8, padding: 16, marginBottom: 16 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <h2 style={{ margin: 0, opacity: cat.active ? 1 : 0.5 }}>{cat.name}</h2>
              <span style={{ color: cat.active ? "green" : "#999" }}>{cat.active ? "actif" : "inactif"}</span>
              <button onClick={() => toggleCategory(cat)}>{cat.active ? "Désactiver" : "Réactiver"}</button>
            </div>

            <ul>
              {cat.serviceTypes.map((type) => (
                <li key={type.id} style={{ opacity: type.active ? 1 : 0.5 }}>
                  {type.name} — {type.active ? "actif" : "inactif"}{" "}
                  <button onClick={() => toggleType(type)}>{type.active ? "Désactiver" : "Réactiver"}</button>
                </li>
              ))}
            </ul>

            {/* Formulaire d'ajout de type de service pour cette catégorie */}
            <ServiceTypeEditor categoryId={cat.id} onCreated={load} />
          </div>
        ))
      )}
    </div>
  );
}
