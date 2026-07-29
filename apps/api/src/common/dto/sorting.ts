import { BadRequestException } from "@nestjs/common";

export type SortDirection = "asc" | "desc";

/**
 * Description d'un champ triable.
 *
 * `path` permet de trier sur une colonne d'une relation : `["pack", "price"]`
 * devient `{ pack: { price: "asc" } }` côté Prisma. L'appelant du tri ne
 * manipule donc jamais que des noms publics (`price`, `rating`, `distance`…),
 * jamais des noms de colonnes.
 */
export interface SortableField {
  path: string[];
  /** Sens appliqué quand l'appelant ne le précise pas. */
  defaultDirection?: SortDirection;
}

export type SortAllowList = Record<string, SortableField | string[]>;

export interface ParsedSort {
  field: string;
  direction: SortDirection;
}

export interface SortParseOptions {
  /**
   * Un champ inconnu ou un sens de tri invalide redevient « pas de tri
   * demandé » (`null`) au lieu de lever une exception.
   *
   * Réservé aux listes de la surface mobile (§12) : une application qui
   * envoie un `sort` malformé à cause d'un bug ne doit pas se retrouver avec
   * une erreur bloquante en plein usage — elle doit simplement recevoir la
   * liste dans son ordre habituel. Les listes du back-office, elles,
   * continuent de lever une erreur explicite : un agent qui compose l'URL à
   * la main veut savoir immédiatement que le champ demandé n'existe pas.
   *
   * Comportement par défaut inchangé (`false`) : ne pas casser les appelants
   * existants qui comptent sur le rejet explicite.
   */
  lenient?: boolean;
}

/**
 * Analyse le paramètre `sort` d'une requête.
 *
 * Deux écritures sont acceptées, celles qu'on rencontre le plus souvent :
 *   - `sort=-createdAt` (le tiret = décroissant) ;
 *   - `sort=createdAt:desc`.
 *
 * Le champ est ensuite confronté à une LISTE BLANCHE propre à chaque ressource.
 * C'est le point important : sans elle, `sort` deviendrait un moyen de trier
 * sur n'importe quelle colonne — y compris `passwordHash` — et de deviner son
 * contenu par comparaisons successives.
 *
 * Jusqu'au Lot 7, `sort` était validé puis ignoré : l'API acceptait le
 * paramètre sans jamais changer l'ordre des résultats, ce qui trompait
 * silencieusement l'appelant.
 */
export function parseSort(
  sort: string | undefined,
  allowed: SortAllowList,
  options?: SortParseOptions
): ParsedSort | null {
  const raw = sort?.trim();
  if (!raw) {
    return null;
  }

  let field = raw;
  let direction: SortDirection | undefined;

  if (field.startsWith("-")) {
    direction = "desc";
    field = field.slice(1);
  } else if (field.startsWith("+")) {
    direction = "asc";
    field = field.slice(1);
  }

  const separator = field.indexOf(":");
  if (separator !== -1) {
    const suffix = field.slice(separator + 1).toLowerCase();
    if (suffix !== "asc" && suffix !== "desc") {
      if (options?.lenient) {
        return null;
      }
      throw new BadRequestException(`Sens de tri inconnu : « ${suffix} » (attendu « asc » ou « desc »)`);
    }
    direction = suffix;
    field = field.slice(0, separator);
  }

  field = field.trim();
  const definition = allowed[field];
  if (!definition) {
    if (options?.lenient) {
      return null;
    }
    const names = Object.keys(allowed).sort().join(", ");
    throw new BadRequestException(`Tri impossible sur « ${field} ». Champs triables : ${names}`);
  }

  const resolved = Array.isArray(definition) ? { path: definition } : definition;
  return { field, direction: direction ?? resolved.defaultDirection ?? "asc" };
}

/**
 * Traduit `sort` en clause `orderBy` Prisma.
 *
 * `fallback` est l'ordre appliqué quand l'appelant ne demande rien — ou,
 * en mode `lenient`, quand ce qu'il a demandé n'est pas exploitable. Chaque
 * liste garde ainsi son tri naturel (le plus souvent « les plus récents
 * d'abord »).
 */
export function buildOrderBy<T>(
  sort: string | undefined,
  allowed: SortAllowList,
  fallback: T,
  options?: SortParseOptions
): T {
  const parsed = parseSort(sort, allowed, options);
  if (!parsed) {
    return fallback;
  }

  const definition = allowed[parsed.field]!;
  const path = Array.isArray(definition) ? definition : definition.path;

  // On reconstruit l'objet imbriqué de la feuille vers la racine :
  // ["pack", "price"] + "asc" -> { pack: { price: "asc" } }
  let orderBy: unknown = parsed.direction;
  for (let i = path.length - 1; i >= 0; i -= 1) {
    orderBy = { [path[i]!]: orderBy };
  }

  return orderBy as T;
}
