import { randomBytes, scrypt, timingSafeEqual } from "node:crypto";

const KEY_LENGTH = 64;
const SCRYPT_PREFIX = "scrypt";

/**
 * Paramètres de coût de scrypt, écrits DANS l'empreinte.
 *
 * Avant le Lot 7, le format stocké était `scrypt$sel$empreinte` : les
 * paramètres n'y figuraient pas, ils étaient implicitement ceux de Node. Les
 * durcir plus tard aurait invalidé tous les mots de passe existants, puisque
 * la vérification aurait recalculé l'empreinte avec d'autres réglages.
 *
 * Le format est désormais `scrypt$N$r$p$sel$empreinte` : chaque empreinte
 * porte les réglages avec lesquels elle a été produite. On peut donc monter
 * `N` quand le matériel le permet — les anciennes empreintes continuent de se
 * vérifier avec leurs propres paramètres, et sont ré-encodées à la connexion.
 */
export interface ScryptParams {
  N: number;
  r: number;
  p: number;
}

// Coût actuel. `N` est le curseur : le doubler double le temps ET la mémoire.
export const CURRENT_SCRYPT_PARAMS: ScryptParams = { N: 32_768, r: 8, p: 1 };

/**
 * Paramètres implicites des empreintes de l'ancien format.
 *
 * Ce sont les valeurs par défaut de Node : c'est avec elles que les empreintes
 * `scrypt$sel$empreinte` ont été produites. Les inscrire ici noir sur blanc est
 * ce qui permet de continuer à les vérifier.
 */
const LEGACY_SCRYPT_PARAMS: ScryptParams = { N: 16_384, r: 8, p: 1 };

/**
 * Plafond mémoire à passer à Node.
 *
 * scrypt consomme environ `128 × N × r` octets. Le plafond par défaut de Node
 * est de 32 Mo : au-delà de N = 16384 il refuse de calculer. On le relève donc
 * en fonction des paramètres demandés, avec une marge.
 */
function maxmemFor(params: ScryptParams): number {
  return Math.max(32 * 1024 * 1024, 256 * params.N * params.r);
}

/**
 * Enveloppe promise autour de `crypto.scrypt`.
 *
 * `promisify` ne convient pas ici : il choisit la signature à trois arguments
 * et perd donc les options de coût — c'est précisément ce qu'on veut passer.
 */
async function derive(plain: string, salt: Buffer, params: ScryptParams, keyLength: number): Promise<Buffer> {
  return new Promise<Buffer>((resolve, reject) => {
    scrypt(
      plain,
      salt,
      keyLength,
      { N: params.N, r: params.r, p: params.p, maxmem: maxmemFor(params) },
      (error, derivedKey) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(derivedKey);
      }
    );
  });
}

/**
 * Transforme un mot de passe en clair en une empreinte sécurisée avec scrypt,
 * l'algorithme intégré à Node (aucune dépendance à installer/compiler).
 * Format stocké : `scrypt$N$r$p$<selHex>$<empreinteHex>` (le sel est aléatoire).
 * On ne stocke JAMAIS le mot de passe en clair, seulement cette empreinte.
 */
export async function hashPassword(plain: string, params: ScryptParams = CURRENT_SCRYPT_PARAMS): Promise<string> {
  const salt = randomBytes(16);
  const derived = await derive(plain, salt, params, KEY_LENGTH);
  return [SCRYPT_PREFIX, params.N, params.r, params.p, salt.toString("hex"), derived.toString("hex")].join("$");
}

/**
 * Décompose une empreinte stockée.
 *
 * Deux formats sont acceptés :
 *   - `scrypt$N$r$p$sel$empreinte` (actuel, paramètres explicites) ;
 *   - `scrypt$sel$empreinte` (ancien, paramètres implicites de Node).
 *
 * Renvoie `null` si la chaîne n'est pas exploitable, pour que la vérification
 * réponde « faux » au lieu de planter.
 */
function parseStored(stored: string): { params: ScryptParams; salt: Buffer; expected: Buffer } | null {
  const parts = stored.split("$");
  if (parts[0] !== SCRYPT_PREFIX) {
    return null;
  }

  if (parts.length === 6) {
    const [, rawN, rawR, rawP, saltHex, hashHex] = parts;
    const N = Number(rawN);
    const r = Number(rawR);
    const p = Number(rawP);
    // `N` doit être une puissance de deux supérieure à 1 : c'est une exigence
    // de scrypt, et une valeur absurde ferait lever une exception à Node.
    if (!Number.isInteger(N) || N < 2 || (N & (N - 1)) !== 0) return null;
    if (!Number.isInteger(r) || r < 1 || !Number.isInteger(p) || p < 1) return null;
    if (!saltHex || !hashHex) return null;
    return { params: { N, r, p }, salt: Buffer.from(saltHex, "hex"), expected: Buffer.from(hashHex, "hex") };
  }

  if (parts.length === 3) {
    const [, saltHex, hashHex] = parts;
    if (!saltHex || !hashHex) return null;
    return {
      params: LEGACY_SCRYPT_PARAMS,
      salt: Buffer.from(saltHex, "hex"),
      expected: Buffer.from(hashHex, "hex")
    };
  }

  return null;
}

/**
 * Vérifie qu'un mot de passe en clair correspond à l'empreinte stockée.
 * Renvoie false si le format est invalide, au lieu de planter. On recalcule
 * l'empreinte avec le même sel ET les mêmes paramètres de coût, puis on compare.
 */
export async function verifyPassword(plain: string, stored: string): Promise<boolean> {
  const parsed = parseStored(stored);
  if (!parsed) {
    return false;
  }

  const { params, salt, expected } = parsed;
  if (expected.length === 0) {
    return false;
  }

  let derived: Buffer;
  try {
    derived = await derive(plain, salt, params, expected.length);
  } catch {
    // Paramètres hors des limites acceptées par Node : empreinte inexploitable.
    return false;
  }

  if (derived.length !== expected.length) {
    return false;
  }

  // timingSafeEqual compare sans fuite de temps (protection contre certaines attaques).
  return timingSafeEqual(derived, expected);
}

/**
 * Indique si une empreinte a été produite avec des paramètres dépassés.
 *
 * Sert à ré-encoder l'empreinte à la volée lors d'une connexion réussie : les
 * comptes anciens gagnent le coût courant sans qu'on demande quoi que ce soit
 * à leur propriétaire.
 */
export function needsRehash(stored: string, params: ScryptParams = CURRENT_SCRYPT_PARAMS): boolean {
  const parsed = parseStored(stored);
  if (!parsed) {
    return true;
  }
  return parsed.params.N < params.N || parsed.params.r < params.r || parsed.params.p < params.p;
}
