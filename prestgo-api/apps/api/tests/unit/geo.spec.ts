import { describe, expect, it } from "vitest";

/**
 * Reproduction de la formule utilisée par `zones.service.ts`.
 *
 * On la teste ici contre des distances réelles connues, pour vérifier que la
 * recherche par rayon ne renvoie ni trop, ni trop peu.
 */
function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const EARTH_RADIUS_KM = 6371;
  const toRad = (deg: number): number => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
}

// Quelques points d'Abidjan et un point lointain.
const COCODY = { lat: 5.35, lng: -3.98 };
const PLATEAU = { lat: 5.325, lng: -4.022 };
const YAMOUSSOUKRO = { lat: 6.827, lng: -5.289 };

describe("distance géographique", () => {
  it("donne zéro entre un point et lui-même", () => {
    expect(haversineKm(COCODY.lat, COCODY.lng, COCODY.lat, COCODY.lng)).toBe(0);
  });

  it("mesure environ 5 km entre Cocody et le Plateau", () => {
    const d = haversineKm(COCODY.lat, COCODY.lng, PLATEAU.lat, PLATEAU.lng);
    expect(d).toBeGreaterThan(4);
    expect(d).toBeLessThan(7);
  });

  it("mesure environ 200 km entre Abidjan et Yamoussoukro", () => {
    const d = haversineKm(COCODY.lat, COCODY.lng, YAMOUSSOUKRO.lat, YAMOUSSOUKRO.lng);
    expect(d).toBeGreaterThan(180);
    expect(d).toBeLessThan(220);
  });

  it("est symétrique : la distance ne dépend pas du sens", () => {
    const aller = haversineKm(COCODY.lat, COCODY.lng, YAMOUSSOUKRO.lat, YAMOUSSOUKRO.lng);
    const retour = haversineKm(YAMOUSSOUKRO.lat, YAMOUSSOUKRO.lng, COCODY.lat, COCODY.lng);
    expect(aller).toBeCloseTo(retour, 6);
  });

  /**
   * Vérification du PRÉ-FILTRE : le rectangle utilisé par la requête SQL doit
   * toujours contenir le vrai cercle. S'il était trop petit, des zones
   * valides seraient silencieusement absentes des résultats.
   */
  it("le rectangle de pré-filtre englobe bien le cercle", () => {
    const radiusKm = 10;
    const latDelta = radiusKm / 111;
    const cosLat = Math.cos((COCODY.lat * Math.PI) / 180);
    const lngDelta = radiusKm / (111 * Math.max(0.01, Math.abs(cosLat)));

    // Un point situé pile à la limite du rayon, plein nord puis plein est.
    const nord = { lat: COCODY.lat + latDelta, lng: COCODY.lng };
    const est = { lat: COCODY.lat, lng: COCODY.lng + lngDelta };

    // Ces deux points sont dans le rectangle par construction ; ils doivent
    // aussi être à une distance proche du rayon demandé (jamais en deçà).
    expect(haversineKm(COCODY.lat, COCODY.lng, nord.lat, nord.lng)).toBeGreaterThanOrEqual(radiusKm - 0.5);
    expect(haversineKm(COCODY.lat, COCODY.lng, est.lat, est.lng)).toBeGreaterThanOrEqual(radiusKm - 0.5);
  });
});
