/**
 * Limites de débit, configurables par variables d'environnement.
 *
 * Pourquoi ne pas les écrire en dur : les tests d'intégration enchaînent des
 * dizaines d'appels en quelques secondes et se bloqueraient eux-mêmes. Un
 * déploiement derrière un proxy peut aussi avoir besoin de valeurs différentes.
 *
 * Les valeurs par défaut sont celles voulues en production.
 */
function limitFrom(name: string, fallback: number): number {
  const raw = Number(process.env[name]);
  return Number.isFinite(raw) && raw > 0 ? raw : fallback;
}

const ONE_MINUTE = 60_000;

// Plafond général : protège d'un emballement sans gêner le back-office.
export const THROTTLE_DEFAULT = { name: "default", ttl: ONE_MINUTE, limit: limitFrom("THROTTLE_LIMIT", 300) };

// Connexion : c'est la porte d'entrée, donc la cible des attaques par force brute.
export const THROTTLE_LOGIN = { default: { ttl: ONE_MINUTE, limit: limitFrom("THROTTLE_AUTH_LIMIT", 10) } };

// Inscription et envoi de code : limiter la création de comptes et de SMS.
export const THROTTLE_SENSITIVE = { default: { ttl: ONE_MINUTE, limit: limitFrom("THROTTLE_SENSITIVE_LIMIT", 5) } };

// Renouvellement de token et vérification de code : plus fréquents, moins risqués.
export const THROTTLE_MODERATE = { default: { ttl: ONE_MINUTE, limit: limitFrom("THROTTLE_MODERATE_LIMIT", 30) } };

// === Débit de la surface mobile (§14.5) ===
//
// Ces trois plafonds s'expriment à l'heure ou au jour, pas à la minute : une
// limite à la minute sur l'enregistrement d'un appareil laisserait passer
// 43 000 appels quotidiens, elle n'aurait rien borné.
//
// Ils passent par `limitFrom` comme tous les autres, et c'est essentiel :
// les suites de tests enchaînent des dizaines de réservations et
// d'enregistrements d'appareils en quelques secondes. Un plafond écrit en dur
// bloquerait les tests eux-mêmes — le limiteur compte par adresse IP, et
// toutes les suites partagent 127.0.0.1.

const ONE_HOUR = 60 * ONE_MINUTE;
const ONE_DAY = 24 * ONE_HOUR;

// Réservation : 10 par heure et par utilisateur (§14.5).
export const THROTTLE_BOOKING = { default: { ttl: ONE_HOUR, limit: limitFrom("THROTTLE_BOOKING_LIMIT", 10) } };

// Signalement d'avis : 20 par jour. C'est un outil de modération, pas une arme
// à répétition contre un concurrent.
export const THROTTLE_REPORT = { default: { ttl: ONE_DAY, limit: limitFrom("THROTTLE_REPORT_LIMIT", 20) } };

// Enregistrement d'un jeton push : 30 par jour. Une application légitime
// s'enregistre au démarrage, soit quelques fois par jour.
export const THROTTLE_DEVICE = { default: { ttl: ONE_DAY, limit: limitFrom("THROTTLE_DEVICE_LIMIT", 30) } };
