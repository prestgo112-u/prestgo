import { useEffect, useState, type ReactElement, type ReactNode } from "react";
import { Link } from "react-router-dom";
import { apiClient } from "../../lib/api-client";
import { BarChart, LineChart, type Point } from "../../components/Charts";

// Forme des données renvoyées par GET /admin/dashboard/summary.
interface DashboardSummary {
  totalUsers: number;
  activeUsers: number;
  approvedProviders: number;
  pendingProviders: number;
  missionsToday: number;
  missionsInProgress: number;
  openDisputes: number;
  reviewsToModerate: number;
  recentActivity: { action: string; entity: string; createdAt: string }[];
  latestProviders: { id: string; publicName: string; validationStatus: string; createdAt: string }[];
  latestDisputes: { id: string; reason: string; status: string; createdAt: string }[];
  documentsToReview: { id: string; type: string; providerName: string; createdAt: string }[];
}

// Forme des données renvoyées par GET /admin/dashboard/charts.
interface DashboardCharts {
  signupsByDay: Point[];
  missionsByCategory: Point[];
  missionsByCity: Point[];
  missionsByStatus: Point[];
  cancellationRate: number;
  averageValidationHours: number | null;
}

// Petite carte réutilisable pour afficher un chiffre clé.
// `to` rend la carte cliquable vers l'écran correspondant.
function MetricCard({ label, value, to }: { label: string; value: number; to?: string }): ReactElement {
  const card = (
    <div style={{ border: "1px solid #e0e0e0", borderRadius: 8, padding: 16, minWidth: 150 }}>
      <div style={{ fontSize: 28, fontWeight: 700 }}>{value}</div>
      <div style={{ color: "#666" }}>{label}</div>
    </div>
  );
  return to ? (
    <Link to={to} style={{ textDecoration: "none", color: "inherit" }}>
      {card}
    </Link>
  ) : (
    card
  );
}

function Panel({ title, children }: { title: string; children: ReactNode }): ReactElement {
  return (
    <section style={{ border: "1px solid #eee", borderRadius: 8, padding: 16, flex: "1 1 320px", minWidth: 300 }}>
      <h3 style={{ marginTop: 0 }}>{title}</h3>
      {children}
    </section>
  );
}

const PERIODS = [
  { days: 7, label: "7 jours" },
  { days: 30, label: "30 jours" },
  { days: 90, label: "90 jours" }
];

export function DashboardPage(): ReactElement {
  const [summary, setSummary] = useState<DashboardSummary | null>(null);
  const [charts, setCharts] = useState<DashboardCharts | null>(null);
  const [days, setDays] = useState(30);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    apiClient
      .get<DashboardSummary>("/admin/dashboard/summary")
      .then(setSummary)
      .catch(() => setError("Impossible de charger le tableau de bord."));
  }, []);

  // Les graphiques se rechargent quand on change la période.
  useEffect(() => {
    apiClient
      .get<DashboardCharts>(`/admin/dashboard/charts?days=${days}`)
      .then(setCharts)
      .catch(() => setCharts(null));
  }, [days]);

  if (error) return <p style={{ color: "crimson" }}>{error}</p>;
  if (!summary) return <p>Chargement…</p>; // tant que les données ne sont pas arrivées

  return (
    <div>
      <h1>Tableau de bord</h1>

      {/* Les 8 cartes du CDC §4.2 */}
      <div style={{ display: "flex", gap: 12, flexWrap: "wrap", marginBottom: 24 }}>
        <MetricCard label="Utilisateurs total" value={summary.totalUsers} to="/users" />
        <MetricCard label="Utilisateurs actifs" value={summary.activeUsers} to="/users" />
        <MetricCard label="Prestataires validés" value={summary.approvedProviders} to="/providers" />
        <MetricCard label="Prestataires en attente" value={summary.pendingProviders} to="/providers" />
        <MetricCard label="Missions du jour" value={summary.missionsToday} to="/missions" />
        <MetricCard label="Missions en cours" value={summary.missionsInProgress} to="/missions" />
        <MetricCard label="Litiges ouverts" value={summary.openDisputes} to="/disputes" />
        <MetricCard label="Avis à modérer" value={summary.reviewsToModerate} to="/reviews" />
      </div>

      {/* Filtre de période, appliqué aux graphiques */}
      <div style={{ display: "flex", gap: 8, alignItems: "center", marginBottom: 16 }}>
        <span style={{ color: "#666" }}>Période :</span>
        {PERIODS.map((period) => (
          <button
            key={period.days}
            onClick={() => setDays(period.days)}
            style={{ padding: "4px 10px", fontWeight: days === period.days ? "bold" : "normal" }}
          >
            {period.label}
          </button>
        ))}
      </div>

      {charts && (
        <>
          <div style={{ display: "flex", gap: 16, flexWrap: "wrap", marginBottom: 16 }}>
            <Panel title={`Inscriptions sur ${days} jours`}>
              <LineChart points={charts.signupsByDay} />
            </Panel>
            <Panel title="Indicateurs">
              <div style={{ display: "flex", gap: 16, flexWrap: "wrap" }}>
                <MetricCard label="Taux d'annulation (%)" value={charts.cancellationRate} />
                <MetricCard
                  label="Délai moyen de validation (h)"
                  value={charts.averageValidationHours ?? 0}
                />
              </div>
              {charts.averageValidationHours === null && (
                <p style={{ color: "#888", fontSize: 12 }}>Aucun document encore revu.</p>
              )}
            </Panel>
          </div>

          <div style={{ display: "flex", gap: 16, flexWrap: "wrap", marginBottom: 24 }}>
            <Panel title="Missions par catégorie">
              <BarChart points={charts.missionsByCategory} />
            </Panel>
            <Panel title="Missions par zone">
              <BarChart points={charts.missionsByCity} />
            </Panel>
            <Panel title="Missions par statut">
              <BarChart points={charts.missionsByStatus} />
            </Panel>
          </div>
        </>
      )}

      {/* Listes rapides du CDC §4.2 */}
      <div style={{ display: "flex", gap: 16, flexWrap: "wrap", marginBottom: 24 }}>
        <Panel title="Derniers prestataires inscrits">
          {summary.latestProviders.length === 0 ? (
            <p style={{ color: "#666" }}>Aucun prestataire.</p>
          ) : (
            <ul>
              {summary.latestProviders.map((provider) => (
                <li key={provider.id}>
                  <Link to={`/providers/${provider.id}`}>{provider.publicName}</Link> — {provider.validationStatus}
                </li>
              ))}
            </ul>
          )}
        </Panel>

        <Panel title="Documents à vérifier">
          {summary.documentsToReview.length === 0 ? (
            <p style={{ color: "#666" }}>Rien à vérifier.</p>
          ) : (
            <ul>
              {summary.documentsToReview.map((doc) => (
                <li key={doc.id}>
                  {doc.type} — {doc.providerName}
                </li>
              ))}
            </ul>
          )}
          <Link to="/verifications">Ouvrir la file de vérification →</Link>
        </Panel>

        <Panel title="Derniers litiges">
          {summary.latestDisputes.length === 0 ? (
            <p style={{ color: "#666" }}>Aucun litige.</p>
          ) : (
            <ul>
              {summary.latestDisputes.map((dispute) => (
                <li key={dispute.id}>
                  <Link to={`/disputes/${dispute.id}`}>{dispute.reason}</Link> — {dispute.status}
                </li>
              ))}
            </ul>
          )}
        </Panel>
      </div>

      <h2>Activité récente</h2>
      {summary.recentActivity.length === 0 ? (
        <p style={{ color: "#666" }}>Aucune activité pour le moment.</p>
      ) : (
        <ul>
          {summary.recentActivity.map((activity, index) => (
            <li key={index}>
              <strong>{activity.action}</strong> sur {activity.entity} —{" "}
              {new Date(activity.createdAt).toLocaleString("fr-FR")}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
