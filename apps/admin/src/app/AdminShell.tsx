import type { ReactElement, ReactNode } from "react";
import { Link } from "react-router-dom";
import { adminRoutes, canAccessRoute } from "../routes/protected-routes";
import { useAuth } from "../features/auth/auth.store";

interface AdminShellProps {
  children: ReactNode;
  userPermissions?: string[];
}

// AdminShell = le cadre commun à toutes les pages : menu à gauche, contenu à droite.
export function AdminShell({ children, userPermissions = [] }: AdminShellProps): ReactElement {
  const { logout } = useAuth();
  // On n'affiche dans le menu que les pages autorisées par les permissions.
  const accessibleRoutes = adminRoutes.filter((route) => canAccessRoute(route, userPermissions));

  return (
    <div className="admin-shell" style={{ display: "flex", minHeight: "100vh", fontFamily: "system-ui" }}>
      <aside
        aria-label="Admin navigation"
        className="admin-sidebar"
        style={{ width: 220, background: "#f5f5f5", padding: 16, display: "flex", flexDirection: "column" }}
      >
        <div className="admin-brand" style={{ marginBottom: 24 }}>
          <strong>PRESTGO</strong> <span className="admin-version">v1.0</span>
        </div>
        <nav className="admin-nav" style={{ display: "grid", gap: 8 }}>
          {accessibleRoutes.map((route) => (
            // Link = navigation sans recharger la page (contrairement à <a href>).
            <Link to={route.path} key={route.path} className="admin-nav-link">
              {route.label}
            </Link>
          ))}
        </nav>
        <button onClick={logout} style={{ marginTop: "auto", padding: 8, cursor: "pointer" }}>
          Se déconnecter
        </button>
      </aside>
      <main className="admin-content" style={{ flex: 1, padding: 24 }}>
        {children}
      </main>
    </div>
  );
}
