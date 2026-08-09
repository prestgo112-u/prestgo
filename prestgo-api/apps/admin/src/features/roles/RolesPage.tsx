import { useCallback, useEffect, useMemo, useState, type ReactElement } from "react";
import { apiClient } from "../../lib/api-client";

interface Permission {
  id: string;
  code: string;
  module: string;
  action: string;
}

interface Role {
  id: string;
  code: string;
  name: string;
  description?: string;
  isSystem: boolean;
  permissions: Permission[];
}

/**
 * Écran Rôles & permissions.
 *
 * Le backend savait déjà tout faire (créer un rôle, lister les permissions,
 * les affecter) mais aucune interface n'appelait ces routes : le critère du
 * CDC « un super admin peut créer des rôles et affecter des permissions »
 * n'était donc pas satisfait.
 */
export function RolesPage(): ReactElement {
  const [roles, setRoles] = useState<Role[]>([]);
  const [permissions, setPermissions] = useState<Permission[]>([]);
  const [selectedRoleId, setSelectedRoleId] = useState<string | null>(null);
  // Permissions cochées dans le panneau de droite, avant enregistrement.
  const [checked, setChecked] = useState<Set<string>>(new Set());
  const [newRole, setNewRole] = useState({ code: "", name: "", description: "" });
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(() => {
    apiClient
      .get<Role[]>("/admin/roles")
      .then(setRoles)
      .catch((loadError) => setError(loadError instanceof Error ? loadError.message : "Chargement impossible."));
    apiClient
      .get<Permission[]>("/admin/permissions")
      .then(setPermissions)
      .catch(() => setPermissions([]));
  }, []);

  useEffect(() => load(), [load]);

  const selectedRole = roles.find((role) => role.id === selectedRoleId) ?? null;

  // Les permissions regroupées par module, pour un affichage lisible.
  const byModule = useMemo(() => {
    const groups = new Map<string, Permission[]>();
    for (const permission of permissions) {
      const list = groups.get(permission.module) ?? [];
      list.push(permission);
      groups.set(permission.module, list);
    }
    return [...groups].sort((a, b) => a[0].localeCompare(b[0]));
  }, [permissions]);

  // Quand on sélectionne un rôle, on pré-coche ses permissions actuelles.
  function selectRole(role: Role): void {
    setSelectedRoleId(role.id);
    setChecked(new Set(role.permissions.map((permission) => permission.id)));
    setMessage(null);
  }

  function toggle(permissionId: string): void {
    setChecked((current) => {
      const next = new Set(current);
      if (next.has(permissionId)) {
        next.delete(permissionId);
      } else {
        next.add(permissionId);
      }
      return next;
    });
  }

  async function createRole(): Promise<void> {
    try {
      await apiClient.post("/admin/roles", {
        code: newRole.code.trim(),
        name: newRole.name.trim(),
        description: newRole.description.trim() || undefined
      });
      setNewRole({ code: "", name: "", description: "" });
      setMessage("Rôle créé.");
      load();
    } catch (createError) {
      setError(createError instanceof Error ? createError.message : "Création impossible.");
    }
  }

  async function savePermissions(): Promise<void> {
    if (!selectedRole) return;
    try {
      await apiClient.patch(`/admin/roles/${selectedRole.id}/permissions`, { permissionIds: [...checked] });
      setMessage(`Permissions du rôle « ${selectedRole.name} » enregistrées.`);
      load();
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : "Enregistrement impossible.");
    }
  }

  return (
    <div>
      <h1>Rôles &amp; permissions</h1>

      {error && <p style={{ color: "crimson" }}>{error}</p>}
      {message && <p style={{ color: "#0a0" }}>{message}</p>}

      <div style={{ display: "flex", gap: 24, alignItems: "flex-start", flexWrap: "wrap" }}>
        {/* Colonne de gauche : la liste des rôles */}
        <div style={{ minWidth: 280 }}>
          <h2>Rôles</h2>
          <ul style={{ listStyle: "none", padding: 0 }}>
            {roles.map((role) => (
              <li key={role.id} style={{ marginBottom: 4 }}>
                <button
                  onClick={() => selectRole(role)}
                  style={{
                    width: "100%",
                    textAlign: "left",
                    padding: 8,
                    fontWeight: role.id === selectedRoleId ? "bold" : "normal"
                  }}
                >
                  {role.name}
                  <div style={{ color: "#888", fontSize: 12 }}>
                    {role.code} · {role.permissions.length} permission(s)
                    {role.isSystem && " · système"}
                  </div>
                </button>
              </li>
            ))}
          </ul>

          <h3>Créer un rôle</h3>
          <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
            <input
              value={newRole.code}
              onChange={(event) => setNewRole({ ...newRole, code: event.target.value })}
              placeholder="code (ex : agent_support)"
              style={{ padding: 6 }}
            />
            <input
              value={newRole.name}
              onChange={(event) => setNewRole({ ...newRole, name: event.target.value })}
              placeholder="Nom affiché"
              style={{ padding: 6 }}
            />
            <input
              value={newRole.description}
              onChange={(event) => setNewRole({ ...newRole, description: event.target.value })}
              placeholder="Description (facultatif)"
              style={{ padding: 6 }}
            />
            <button onClick={createRole} disabled={!newRole.code.trim() || !newRole.name.trim()}>
              Créer le rôle
            </button>
          </div>
        </div>

        {/* Colonne de droite : les permissions du rôle sélectionné */}
        <div style={{ flex: 1, minWidth: 320 }}>
          <h2>Permissions</h2>
          {!selectedRole ? (
            <p style={{ color: "#666" }}>Sélectionne un rôle à gauche pour modifier ses permissions.</p>
          ) : (
            <>
              <p style={{ color: "#666" }}>
                Rôle <strong>{selectedRole.name}</strong> — {checked.size} permission(s) cochée(s).
              </p>
              {byModule.map(([moduleName, modulePermissions]) => (
                <fieldset key={moduleName} style={{ marginBottom: 12, border: "1px solid #ddd", padding: 8 }}>
                  <legend style={{ fontWeight: "bold" }}>{moduleName}</legend>
                  {modulePermissions.map((permission) => (
                    <label key={permission.id} style={{ display: "block", padding: 2 }}>
                      <input
                        type="checkbox"
                        checked={checked.has(permission.id)}
                        onChange={() => toggle(permission.id)}
                      />{" "}
                      {permission.action} <span style={{ color: "#888", fontSize: 12 }}>({permission.code})</span>
                    </label>
                  ))}
                </fieldset>
              ))}
              <button onClick={savePermissions} style={{ padding: 8 }}>
                Enregistrer les permissions
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
