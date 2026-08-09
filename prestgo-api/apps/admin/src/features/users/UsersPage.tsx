import { useCallback, useEffect, useState, type ReactElement } from "react";
import { Link } from "react-router-dom";
import { apiClient } from "../../lib/api-client";
import { useAuth } from "../auth/auth.store";
import { useReasonPrompt } from "../../components/prompt";

// Forme d'un utilisateur renvoyé par l'API.
interface AdminUser {
  id: string;
  email?: string;
  firstName?: string;
  lastName?: string;
  status: string;
  roles: string[];
}

const STATUSES = ["", "draft", "pending", "active", "rejected", "suspended", "deleted"];

export function UsersPage(): ReactElement {
  const { permissions } = useAuth();
  const ask = useReasonPrompt();
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [search, setSearch] = useState("");
  const [status, setStatus] = useState("");
  const [page, setPage] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const limit = 20;

  // Peut-on changer le statut ? Seulement si on a la permission.
  const canChangeStatus = permissions.includes("admin.users.status.update");

  const loadUsers = useCallback(() => {
    const params = new URLSearchParams({ page: String(page), limit: String(limit) });
    if (search.trim()) params.set("search", search.trim());
    if (status) params.set("status", status);

    apiClient
      .get<AdminUser[]>(`/admin/users?${params.toString()}`)
      .then((rows) => {
        setUsers(rows);
        setError(null);
      })
      .catch((loadError) => setError(loadError instanceof Error ? loadError.message : "Chargement impossible."));
  }, [page, search, status]);

  useEffect(() => loadUsers(), [loadUsers]);

  // Change le statut d'un utilisateur puis recharge la liste.
  async function changeStatus(userId: string, nextStatus: string): Promise<void> {
    const reason = (await ask("Motif du changement de statut ?")) ?? "";
    if (!reason.trim()) return; // le motif est obligatoire
    try {
      await apiClient.patch(`/admin/users/${userId}/status`, { status: nextStatus, reason });
      loadUsers();
    } catch (statusError) {
      setError(statusError instanceof Error ? statusError.message : "Le changement de statut a échoué.");
    }
  }

  return (
    <div>
      <h1>Utilisateurs</h1>

      <div style={{ display: "flex", gap: 8, marginBottom: 16, flexWrap: "wrap" }}>
        <input
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setPage(1);
          }}
          placeholder="Nom, email ou téléphone…"
          style={{ padding: 6, minWidth: 240 }}
        />
        <select
          value={status}
          onChange={(event) => {
            setStatus(event.target.value);
            setPage(1);
          }}
          style={{ padding: 6 }}
        >
          {STATUSES.map((value) => (
            <option key={value} value={value}>
              {value === "" ? "Tous les statuts" : value}
            </option>
          ))}
        </select>
      </div>

      {error && <p style={{ color: "crimson" }}>{error}</p>}

      {users.length === 0 ? (
        <p style={{ color: "#666" }}>Aucun utilisateur à afficher.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid #ddd" }}>
              <th style={{ padding: 8 }}>Email</th>
              <th style={{ padding: 8 }}>Nom</th>
              <th style={{ padding: 8 }}>Rôles</th>
              <th style={{ padding: 8 }}>Statut</th>
              <th style={{ padding: 8 }}>Actions</th>
            </tr>
          </thead>
          <tbody>
            {users.map((user) => (
              <tr key={user.id} style={{ borderBottom: "1px solid #eee" }}>
                <td style={{ padding: 8 }}>
                  <Link to={`/users/${user.id}`}>{user.email ?? "—"}</Link>
                </td>
                <td style={{ padding: 8 }}>
                  {[user.firstName, user.lastName].filter(Boolean).join(" ") || "—"}
                </td>
                <td style={{ padding: 8 }}>{user.roles.join(", ") || "—"}</td>
                <td style={{ padding: 8 }}>{user.status}</td>
                <td style={{ padding: 8 }}>
                  {/* Le bouton n'apparaît que si l'admin a la permission */}
                  {canChangeStatus && user.status !== "suspended" && (
                    <button onClick={() => changeStatus(user.id, "suspended")}>Suspendre</button>
                  )}
                  {canChangeStatus && user.status === "suspended" && (
                    <button onClick={() => changeStatus(user.id, "active")}>Réactiver</button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {/* Pagination simple */}
      <div style={{ display: "flex", gap: 8, marginTop: 16, alignItems: "center" }}>
        <button disabled={page <= 1} onClick={() => setPage((current) => current - 1)}>
          Précédent
        </button>
        <span>Page {page}</span>
        <button disabled={users.length < limit} onClick={() => setPage((current) => current + 1)}>
          Suivant
        </button>
      </div>
    </div>
  );
}
