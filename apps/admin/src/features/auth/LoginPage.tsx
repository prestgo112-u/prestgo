import { useState, type FormEvent, type ReactElement } from "react";
import { useNavigate } from "react-router-dom";
import { useAuth } from "./auth.store";

// Page de connexion du back-office : un formulaire email + mot de passe.
export function LoginPage(): ReactElement {
  const { login } = useAuth();
  const navigate = useNavigate(); // permet de rediriger après connexion

  // useState garde en mémoire ce que l'utilisateur tape dans les champs.
  const [email, setEmail] = useState("admin@prestgo.test");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  // Fonction appelée quand on valide le formulaire.
  async function handleSubmit(event: FormEvent): Promise<void> {
    event.preventDefault(); // empêche le rechargement de la page par le navigateur
    setError(null);
    setLoading(true);
    try {
      await login(email, password);
      navigate("/dashboard"); // connexion réussie → on va au tableau de bord
    } catch {
      setError("Email ou mot de passe incorrect.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div style={{ maxWidth: 360, margin: "80px auto", fontFamily: "system-ui" }}>
      <h1>PRESTGO Admin</h1>
      <p style={{ color: "#666" }}>Connectez-vous pour accéder au back-office.</p>

      <form onSubmit={handleSubmit} style={{ display: "grid", gap: 12 }}>
        <label style={{ display: "grid", gap: 4 }}>
          Email
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            style={{ padding: 8 }}
          />
        </label>

        <label style={{ display: "grid", gap: 4 }}>
          Mot de passe
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
            style={{ padding: 8 }}
          />
        </label>

        {/* Message d'erreur affiché seulement s'il y en a un */}
        {error && <p style={{ color: "crimson", margin: 0 }}>{error}</p>}

        <button type="submit" disabled={loading} style={{ padding: 10, cursor: "pointer" }}>
          {loading ? "Connexion…" : "Se connecter"}
        </button>
      </form>
    </div>
  );
}
