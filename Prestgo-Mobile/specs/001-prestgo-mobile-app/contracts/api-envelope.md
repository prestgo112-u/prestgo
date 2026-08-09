# Contrat — Enveloppe de réponse, erreurs et pagination

**Portée** : `lib/core/api/`. Ce contrat est le seul point de l'application qui
connaît la forme brute des réponses du service.

## 1. Enveloppe

Toute réponse du service, succès comme erreur, respecte :

```json
{ "success": bool, "message": string?, "data": T?, "errors": ApiErrorDetail[]?, "meta": ApiMeta? }
```

```
ApiErrorDetail = { field?: string, code: string, message: string }
ApiMeta        = { page?: int, limit?: int, total?: int, correlationId?: string }
```

Le filtre d'exception du service est global : **aucune** réponse ne sort de ce
format, y compris les erreurs non prévues.

### Modèles applicatifs

| Modèle | Rôle |
|---|---|
| `ApiEnvelope<T>` | décodage générique ; `data` interprété par un `parse` fourni par l'appelant |
| `ApiErrorDetail` | `{ field?, code, message }` |
| `ApiMeta` | `{ page?, limit?, total?, correlationId? }` + `hasMore` |
| `ApiException` | exception **unique** exposée aux dépôts et aux écrans |

`ApiException` porte `statusCode`, `message`, `errors`, `correlationId` et les
prédicats `isUserFixable` (400/409), `isAuth` (401), `isForbidden` (403),
`isNotFound` (404), `isRateLimited` (429), `isServer` (≥ 500), plus
`messageForField(String field)`.

## 2. Trois formes de `data`

| Forme | Exemples | Conséquence |
|---|---|---|
| **Objet** | `GET /me`, `GET /missions/{id}`, `GET /providers/me` | `parse` → modèle |
| **Tableau** | `GET /me/addresses`, `GET /me/missions`, `GET /providers/search`, `GET /providers/{id}/reviews` | `parse` → `List<T>` |
| **Objet structuré non paginé** | `GET /providers/me/documents` (`requiredTypes`, `missingTypes`, `current`, `documents`) | `parse` → modèle de vue dédié |

⚠️ `GET /providers/{id}/reviews` renvoie désormais un **tableau** dans `data` avec la
pagination dans `meta` (correction de l'écart n°15). Toute documentation antérieure
décrivant `data.reviews` est obsolète.

## 3. Pagination

- Une réponse paginée porte `meta { page, limit, total }` ; une réponse non paginée
  n'a **pas** de `meta` de pagination.
- Paramètres communs : `page` (≥ 1), `limit`, `sort`.
- Plafonds de `limit` : **50** sur `GET /providers/search`, **100** ailleurs, défaut
  applicatif **20**.
- `sort` accepte `champ` ou `-champ` selon les routes ; sur les listes de missions et
  d'avis, une valeur inconnue **ne provoque pas d'erreur** (retour au tri par défaut).
- Tris par défaut à **ne pas** contredire localement : missions client
  `scheduledAt` décroissant ; missions prestataire `scheduledAt` croissant ; messages
  `createdAt` croissant.

## 4. Erreurs — règles d'affichage

| Code | Traitement |
|---|---|
| **400** | `message` affichable tel quel ; associer chaque `errors[].field` à son champ de formulaire quand il est présent |
| **401** | Traité par l'intercepteur (renouvellement puis rejeu unique). Les messages `Bearer token required` et `Invalid access token` ne sont **jamais** affichés |
| **403** | Message affichable ; `Ce compte n'a pas de profil prestataire` déclenche un retour au parcours de création de profil |
| **404** | Message affichable ; recharger la ressource parente |
| **409** | Métier (doublon, requête identique en cours) — voir [retry-and-idempotency.md](./retry-and-idempotency.md) |
| **429** | Message d'attente générique + désactivation temporaire de l'action. **Jamais de rejeu** |
| **≥ 500** | « Le service est momentanément indisponible. » + action de reprise |
| **réseau / 0** | « Connexion impossible. Vérifiez votre réseau. » |

**Messages à ne pas afficher tels quels** (techniques ou trompeurs) :
`Invalid credentials` → « Email ou mot de passe incorrect » ;
`Account is not active` → message générique + deux issues (vérifier / support) ;
`Bearer token required`, `Invalid access token` → jamais affichés ;
messages de disponibilité côté prestataire (« Le prestataire ne travaille pas sur ce
créneau ») → reformulés à la deuxième personne.

**Tous les autres messages métier sont affichés tels quels**, y compris ceux
contenant un nombre interpolé (missions bloquantes, sessions fermées, délais) : les
reconstruire côté client produirait des textes faux.

## 5. `field` dans `errors[]`

Depuis la correction de l'écart n°13, les erreurs de validation du service portent
un `field` complet, y compris pour un élément de tableau imbriqué
(`slots.1.startTime`). L'application associe donc chaque message à son champ.

Deux limites subsistent :
- `message` (en-tête) reste un texte unique — bon pour une bannière, pas pour un
  champ ;
- les erreurs **métier** posées à la main par un service (ex. `409 Cet email ou ce
  numéro est déjà utilisé`) n'ont pas de `field` → bannière de formulaire.

## 6. `correlationId`

Présent dans `meta` de **toutes** les erreurs. Il est systématiquement joint au
rapport d'incident (FR-091, SC-010) et jamais affiché à l'utilisateur, sauf sur un
écran d'erreur technique où il peut être proposé en copie pour le support.

## 7. Règles d'équipe (porte G2)

1. Aucun écran, aucun dépôt ne lit `response.data['data']`.
2. Aucun écran, aucun dépôt ne teste un code HTTP : seuls les prédicats
   d'`ApiException` sont utilisés.
3. La conversion erreur → `ApiException` a lieu dans **un seul** intercepteur.
4. En-têtes systématiques : `Authorization: Bearer <accessToken>` sur les routes
   protégées, `User-Agent` applicatif lisible (`PRESTGO-Android/1.0.0 (Pixel 7)`),
   `Idempotency-Key` sur `POST /missions`.
5. La base d'API configurée contient déjà `/api/v1` : aucun code ne le rajoute.
