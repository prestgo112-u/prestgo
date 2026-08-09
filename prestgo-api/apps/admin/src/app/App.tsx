import type { ReactElement, ReactNode } from "react";
import { BrowserRouter, Navigate, Route, Routes, useLocation } from "react-router-dom";
import { AdminShell } from "./AdminShell";
import { firstAllowedPath, permissionForPath } from "../routes/protected-routes";
import { AuthProvider, useAuth } from "../features/auth/auth.store";
import { PromptProvider } from "../components/prompt";
import { LoginPage } from "../features/auth/LoginPage";
import { DashboardPage } from "../features/dashboard/DashboardPage";
import { UsersPage } from "../features/users/UsersPage";
import { UserDetailPage } from "../features/users/UserDetailPage";
import { ProviderValidationQueue } from "../features/providers/ProviderValidationQueue";
import { ProviderDetailPage } from "../features/providers/ProviderDetailPage";
import { MissionsPage } from "../features/missions/MissionsPage";
import { MissionDetailPage } from "../features/missions/MissionDetailPage";
import { DisputesPage } from "../features/disputes/DisputesPage";
import { DisputeDetailPage } from "../features/disputes/DisputeDetailPage";
import { ReviewsPage } from "../features/reviews/ReviewsPage";
import { MessagesPage } from "../features/messages/MessagesPage";
import { CatalogPage } from "../features/catalog/CatalogPage";
import { ZonesPage } from "../features/zones/ZonesPage";
import { SettingsPage } from "../features/settings/SettingsPage";
import { AuditLogPage } from "../features/audit/AuditLogPage";
import { NotificationsPage } from "../features/notifications/NotificationsPage";
import { ExportsPage } from "../features/exports/ExportsPage";
import { ClientsPage } from "../features/clients/ClientsPage";
import { ClientDetailPage } from "../features/clients/ClientDetailPage";
import { VerificationsPage } from "../features/verifications/VerificationsPage";
import { RolesPage } from "../features/roles/RolesPage";

// "Garde" côté navigateur : si l'utilisateur n'est pas connecté, on le renvoie
// vers la page de connexion. Sinon on vérifie qu'il a bien le droit de voir
// CETTE page, puis on l'affiche dans le cadre admin.
function Protected({ children }: { children: ReactNode }): ReactElement {
  const { isAuthenticated, permissions } = useAuth();
  const location = useLocation();

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  // Contrôle de permission par URL. Sans lui, masquer une entrée du menu ne
  // servait à rien : il suffisait de taper l'adresse pour ouvrir l'écran.
  const required = permissionForPath(location.pathname);
  if (required && !permissions.includes(required)) {
    return (
      <AdminShell userPermissions={permissions}>
        <div>
          <h1>Accès refusé</h1>
          <p style={{ color: "#666" }}>
            Vous n'avez pas la permission <code>{required}</code> nécessaire pour consulter cette page.
          </p>
        </div>
      </AdminShell>
    );
  }

  // AdminShell affiche le menu latéral (filtré selon les permissions) + le contenu.
  return <AdminShell userPermissions={permissions}>{children}</AdminShell>;
}

// Redirige vers la première page autorisée plutôt que systématiquement vers le
// tableau de bord, auquel tout le monde n'a pas forcément accès.
function DefaultRedirect(): ReactElement {
  const { isAuthenticated, permissions } = useAuth();
  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }
  return <Navigate to={firstAllowedPath(permissions)} replace />;
}

// Déclare toutes les routes (URL → composant à afficher).
function AppRoutes(): ReactElement {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route path="/dashboard" element={<Protected><DashboardPage /></Protected>} />
      <Route path="/users" element={<Protected><UsersPage /></Protected>} />
      <Route path="/users/:id" element={<Protected><UserDetailPage /></Protected>} />
      <Route path="/clients" element={<Protected><ClientsPage /></Protected>} />
      <Route path="/clients/:id" element={<Protected><ClientDetailPage /></Protected>} />
      <Route path="/verifications" element={<Protected><VerificationsPage /></Protected>} />
      <Route path="/roles" element={<Protected><RolesPage /></Protected>} />
      <Route path="/providers" element={<Protected><ProviderValidationQueue /></Protected>} />
      <Route path="/providers/:id" element={<Protected><ProviderDetailPage /></Protected>} />
      <Route path="/missions" element={<Protected><MissionsPage /></Protected>} />
      <Route path="/missions/:id" element={<Protected><MissionDetailPage /></Protected>} />
      <Route path="/disputes" element={<Protected><DisputesPage /></Protected>} />
      <Route path="/disputes/:id" element={<Protected><DisputeDetailPage /></Protected>} />
      <Route path="/reviews" element={<Protected><ReviewsPage /></Protected>} />
      <Route path="/messages" element={<Protected><MessagesPage /></Protected>} />
      <Route path="/catalog" element={<Protected><CatalogPage /></Protected>} />
      <Route path="/zones" element={<Protected><ZonesPage /></Protected>} />
      <Route path="/settings" element={<Protected><SettingsPage /></Protected>} />
      <Route path="/notifications" element={<Protected><NotificationsPage /></Protected>} />
      <Route path="/exports" element={<Protected><ExportsPage /></Protected>} />
      <Route path="/audit" element={<Protected><AuditLogPage /></Protected>} />
      {/* Par défaut, on redirige vers la première page autorisée. */}
      <Route path="*" element={<DefaultRedirect />} />
    </Routes>
  );
}

export function App(): ReactElement {
  return (
    // AuthProvider rend l'état de connexion disponible partout.
    // BrowserRouter active la navigation par URL sans recharger la page.
    <AuthProvider>
      <PromptProvider>
        <BrowserRouter>
          <AppRoutes />
        </BrowserRouter>
      </PromptProvider>
    </AuthProvider>
  );
}