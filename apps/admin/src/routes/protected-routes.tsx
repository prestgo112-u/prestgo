export interface AdminRoute {
  path: string;
  label: string;
  permission: string;
}

// Ordre des entrées du menu, aligné sur le cahier des charges §4.1.
export const adminRoutes: AdminRoute[] = [
  { path: "/dashboard", label: "Tableau de bord", permission: "admin.dashboard.read" },
  { path: "/users", label: "Utilisateurs", permission: "admin.users.read" },
  { path: "/clients", label: "Clients", permission: "admin.clients.read" },
  { path: "/providers", label: "Prestataires", permission: "admin.providers.read" },
  { path: "/verifications", label: "Vérifications", permission: "admin.verifications.documents.review" },
  { path: "/catalog", label: "Catalogue", permission: "admin.catalog.read" },
  { path: "/zones", label: "Zones", permission: "admin.zones.read" },
  { path: "/missions", label: "Missions", permission: "admin.missions.read" },
  { path: "/messages", label: "Messages", permission: "admin.messages.read" },
  { path: "/reviews", label: "Avis", permission: "admin.reviews.read" },
  { path: "/disputes", label: "Litiges", permission: "admin.disputes.read" },
  { path: "/notifications", label: "Notifications", permission: "admin.notifications.read" },
  { path: "/roles", label: "Rôles & permissions", permission: "admin.roles.manage" },
  { path: "/settings", label: "Réglages", permission: "admin.settings.read" },
  { path: "/audit", label: "Audit", permission: "audit.read" },
  { path: "/exports", label: "Exports", permission: "admin.exports.manage" }
];

export function canAccessRoute(route: AdminRoute, permissions: string[]): boolean {
  return permissions.includes(route.permission);
}

/**
 * Permission exigée pour afficher une URL donnée.
 *
 * Avant le Lot 2, le menu masquait bien les entrées interdites, mais taper
 * l'URL à la main donnait quand même accès à l'écran (seule l'API refusait
 * ensuite les appels). On associe donc explicitement chaque URL, y compris les
 * pages de détail, à la permission qui la protège.
 */
const ROUTE_PERMISSIONS: { prefix: string; permission: string }[] = [
  { prefix: "/dashboard", permission: "admin.dashboard.read" },
  { prefix: "/users", permission: "admin.users.read" },
  { prefix: "/clients", permission: "admin.clients.read" },
  { prefix: "/providers", permission: "admin.providers.read" },
  { prefix: "/verifications", permission: "admin.verifications.documents.review" },
  { prefix: "/catalog", permission: "admin.catalog.read" },
  { prefix: "/zones", permission: "admin.zones.read" },
  { prefix: "/missions", permission: "admin.missions.read" },
  { prefix: "/messages", permission: "admin.messages.read" },
  { prefix: "/reviews", permission: "admin.reviews.read" },
  { prefix: "/disputes", permission: "admin.disputes.read" },
  { prefix: "/notifications", permission: "admin.notifications.read" },
  { prefix: "/roles", permission: "admin.roles.manage" },
  { prefix: "/settings", permission: "admin.settings.read" },
  { prefix: "/audit", permission: "audit.read" },
  { prefix: "/exports", permission: "admin.exports.manage" }
];

export function permissionForPath(pathname: string): string | null {
  const match = ROUTE_PERMISSIONS.find(
    (route) => pathname === route.prefix || pathname.startsWith(`${route.prefix}/`)
  );
  return match?.permission ?? null;
}

// Première page accessible à l'utilisateur : utile pour la redirection après
// connexion, car tout le monde n'a pas forcément accès au tableau de bord.
export function firstAllowedPath(permissions: string[]): string {
  const route = adminRoutes.find((item) => canAccessRoute(item, permissions));
  return route?.path ?? "/login";
}
