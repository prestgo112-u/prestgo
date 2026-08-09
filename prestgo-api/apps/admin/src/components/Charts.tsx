import type { ReactElement } from "react";

export interface Point {
  label: string;
  value: number;
}

// Palette volontairement sobre et contrastée (CDC §10 : contrastes corrects).
const COLORS = ["#2563eb", "#0891b2", "#7c3aed", "#c2410c", "#15803d", "#a16207", "#be123c", "#4b5563"];

/**
 * Graphiques dessinés en SVG, sans aucune librairie externe.
 *
 * Pourquoi : le back-office n'a que React et React Router comme dépendances.
 * Ajouter une librairie de graphiques pour quatre visuels simples aurait
 * alourdi le paquet livré au navigateur sans réel bénéfice.
 */

// Courbe d'évolution (inscriptions par jour).
export function LineChart({ points, height = 160 }: { points: Point[]; height?: number }): ReactElement {
  const first = points[0];
  const last = points[points.length - 1];
  if (!first || !last) {
    return <p style={{ color: "#666" }}>Pas encore de données.</p>;
  }

  const width = 640;
  const padding = 28;
  const max = Math.max(1, ...points.map((point) => point.value));
  const stepX = points.length > 1 ? (width - padding * 2) / (points.length - 1) : 0;

  // Conversion valeur → coordonnée verticale (l'axe SVG part du haut).
  const toY = (value: number): number => height - padding - (value / max) * (height - padding * 2);
  const path = points.map((point, index) => `${index === 0 ? "M" : "L"} ${padding + index * stepX} ${toY(point.value)}`).join(" ");

  return (
    <svg viewBox={`0 0 ${width} ${height}`} style={{ width: "100%", height: "auto" }} role="img" aria-label="Courbe">
      {/* Axes */}
      <line x1={padding} y1={height - padding} x2={width - padding} y2={height - padding} stroke="#ccc" />
      <line x1={padding} y1={padding} x2={padding} y2={height - padding} stroke="#ccc" />
      {/* Repères de valeur */}
      <text x={4} y={padding + 4} fontSize="10" fill="#888">
        {max}
      </text>
      <text x={4} y={height - padding} fontSize="10" fill="#888">
        0
      </text>
      <path d={path} fill="none" stroke={COLORS[0]} strokeWidth="2" />
      {/* Première et dernière date, pour situer la période */}
      <text x={padding} y={height - 8} fontSize="10" fill="#888">
        {first.label}
      </text>
      <text x={width - padding} y={height - 8} fontSize="10" fill="#888" textAnchor="end">
        {last.label}
      </text>
    </svg>
  );
}

// Barres horizontales (missions par catégorie, par ville, par statut).
export function BarChart({ points, max = 8 }: { points: Point[]; max?: number }): ReactElement {
  if (points.length === 0) {
    return <p style={{ color: "#666" }}>Pas encore de données.</p>;
  }

  const shown = points.slice(0, max);
  const highest = Math.max(1, ...shown.map((point) => point.value));

  return (
    <div>
      {shown.map((point, index) => (
        <div key={point.label} style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 6 }}>
          <span style={{ width: 150, fontSize: 13, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
            {point.label}
          </span>
          <span
            style={{
              // La largeur est proportionnelle à la plus grande valeur.
              width: `${(point.value / highest) * 100}%`,
              minWidth: 2,
              height: 16,
              background: COLORS[index % COLORS.length],
              borderRadius: 2
            }}
          />
          <span style={{ fontSize: 13, color: "#444" }}>{point.value}</span>
        </div>
      ))}
      {points.length > max && <p style={{ color: "#888", fontSize: 12 }}>… et {points.length - max} autre(s)</p>}
    </div>
  );
}
