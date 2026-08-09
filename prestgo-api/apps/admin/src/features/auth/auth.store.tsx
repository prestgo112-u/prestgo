import { createContext, useContext, useMemo, useState, type ReactElement, type ReactNode } from "react";
import { apiClient } from "../../lib/api-client";

// Ce qu'on stocke sur l'utilisateur connecté côté navigateur.
interface AuthState {
  accessToken: string | null;
  permissions: string[];
  roles: string[];
  userId: string | null;
}

// Ce que le contexte met à disposition de toute l'application.
interface AuthContextValue extends AuthState {
  isAuthenticated: boolean;
  login: (email: string, password: string) => Promise<void>;
  logout: () => void;
}

// Réponse renvoyée par POST /auth/login.
interface LoginResult {
  accessToken: string;
  refreshToken: string;
}

const STORAGE_KEY = "prestgo.accessToken";

// Un contexte React = une valeur partagée que n'importe quel composant enfant
// peut lire sans qu'on ait à la passer manuellement de parent en enfant.
const AuthContext = createContext<AuthContextValue | null>(null);

// Décode la partie "payload" d'un JWT (le token est : entete.payload.signature).
// On y trouve les rôles et permissions, sans appel serveur supplémentaire.
function decodeToken(token: string): { sub?: string; roles?: string[]; permissions?: string[] } {
  try {
    const payload = token.split(".")[1];
    if (!payload) return {};
    // atob décode le base64. On remet les caractères spéciaux du base64url.
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return JSON.parse(json);
  } catch {
    return {};
  }
}

// Construit l'état d'auth à partir d'un token (ou état vide si pas de token).
function stateFromToken(token: string | null): AuthState {
  if (!token) {
    return { accessToken: null, permissions: [], roles: [], userId: null };
  }
  const decoded = decodeToken(token);
  return {
    accessToken: token,
    permissions: decoded.permissions ?? [],
    roles: decoded.roles ?? [],
    userId: decoded.sub ?? null
  };
}

// Le "Provider" enveloppe l'application et fournit l'état d'auth à ses enfants.
export function AuthProvider({ children }: { children: ReactNode }): ReactElement {
  // On lit le token déjà sauvegardé (pour rester connecté après un rafraîchissement).
  const [state, setState] = useState<AuthState>(() => {
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved) {
      apiClient.setAccessToken(saved);
    }
    return stateFromToken(saved);
  });

  const value = useMemo<AuthContextValue>(() => ({
    ...state,
    isAuthenticated: Boolean(state.accessToken),
    // Appelle l'API de connexion, stocke le token, met à jour l'état.
    login: async (email: string, password: string) => {
      const result = await apiClient.post<LoginResult>("/auth/login", { email, password });
      apiClient.setAccessToken(result.accessToken);
      localStorage.setItem(STORAGE_KEY, result.accessToken);
      setState(stateFromToken(result.accessToken));
    },
    // Efface le token partout et repasse à l'état déconnecté.
    logout: () => {
      apiClient.clearAccessToken();
      localStorage.removeItem(STORAGE_KEY);
      setState(stateFromToken(null));
    }
  }), [state]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

// Petit raccourci pour lire le contexte d'auth depuis n'importe quel composant.
export function useAuth(): AuthContextValue {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth doit être utilisé à l'intérieur de <AuthProvider>");
  }
  return context;
}
