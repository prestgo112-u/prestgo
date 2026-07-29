import { useCallback, useEffect, useState, type ReactElement } from "react";
import { Link, useParams } from "react-router-dom";
import { apiClient } from "../../lib/api-client";
import { useAuth } from "../auth/auth.store";

interface AdminUserDetail {
  id: string;
  email?: string;
  firstName?: string;
  lastName?: string;
  phone?: string;
  status: string;
  roles: string[];
  permissions: string[];
  createdAt: string;
}

interface Role {
  id: string;
  code: string;
  name: string;
}

export function UserDetailPage(): ReactElement {
  // useParams lit l'identifiant présent dans l'URL (/users/:id).
  const { id } = useParams<{ id: string }>();
  const { permissions: myPermissions } = useAuth();
  const [user, setUser] = useState<AdminUserDetail | null>(null);
  const [roles, setRoles] = useState<Role[]>([]);
  // Rôles cochés dans le formulaire, avant enregistrement.
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const canManageRoles = myPermissions.includes("admin.roles.manage");

  const load = useCallback(() => {
    if (!id) return;
    apiClient
      .get<AdminUserDetail>(`/admin/users/${id}`)
      .then(setUser)
      .catch(() => setError("Utilisateur introuvable."));
  }, [id]);

  useEffect(() => load(), [load]);

  // On charge la liste des rôles pour proposer les cases à cocher.
  useEffect(() => {
    if (!canManageRoles) return;
    apiClient
      .get<Role[]>("/admin/roles")
      .then(setRoles)
      .catch(() => setRoles([]));
  }, [canManageRoles]);

  // Quand utilisateur et rôles sont chargés, on coche les rôles qu'il possède.
  // Le lien se fait par le CODE du rôle, car c'est ce que renvoie la fiche.
  useEffect(() => {
    if (!user || roles.length === 0) return;
    const owned = roles.filter((role) => user.roles.includes(role.code)).map((role) => role.id);
    setSelected(new Set(owned));
  }, [user, roles]);

  function toggle(roleId: string): void {
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(roleId)) {
        next.delete(roleId);
      } else {
        next.add(roleId);
      }
      return next;
    });
  }

  async function saveRoles(): Promise<void> {
    try {
      await apiClient.patch(`/admin/users/${id}/roles`, { roleIds: [...selected] });
      setMessage("Rôles mis à jour.");
      load();
    } catch (saveError) {
      setError(saveError instanceof Error ? saveError.message : "Mise à jour impossible.");
    }
  }

  if (error) return <p style={{ color: "crimson" }}>{error}</p>;
  if (!user) return <p>Chargement…</p>;

  return (
    <div>
      <p>
        <Link to="/users">← Retour à la liste</Link>
      </p>
      <h1>{[user.firstName, user.lastName].filter(Boolean).join(" ") || user.email || "Utilisateur"}</h1>

      <dl style={{ display: "grid", gridTemplateColumns: "160px 1fr", gap: 8, maxWidth: 500 }}>
        <dt>Email</dt>
        <dd>{user.email ?? "—"}</dd>
        <dt>Téléphone</dt>
        <dd>{user.phone ?? "—"}</dd>
        <dt>Statut</dt>
        <dd>{user.status}</dd>
        <dt>Rôles</dt>
        <dd>{user.roles.join(", ") || "—"}</dd>
        <dt>Permissions</dt>
        <dd>{user.permissions.join(", ") || "—"}</dd>
        <dt>Créé le</dt>
        <dd>{new Date(user.createdAt).toLocaleString("fr-FR")}</dd>
      </dl>

      {canManageRoles && (
        <>
          <h2>Affecter des rôles</h2>
          <p style={{ color: "#666" }}>
            Un compte sans aucun rôle est un compte utilisateur ordinaire (client).
          </p>
          {roles.length === 0 ? (
            <p style={{ color: "#666" }}>Aucun rôle disponible.</p>
          ) : (
            <div style={{ marginBottom: 12 }}>
              {roles.map((role) => (
                <label key={role.id} style={{ display: "block", padding: 2 }}>
                  <input type="checkbox" checked={selected.has(role.id)} onChange={() => toggle(role.id)} />{" "}
                  {role.name} <span style={{ color: "#888", fontSize: 12 }}>({role.code})</span>
                </label>
              ))}
            </div>
          )}
          <button onClick={saveRoles}>Enregistrer les rôles</button>
          {message && <p style={{ color: "#0a0" }}>{message}</p>}
        </>
      )}
    </div>
  );
}
