# Lot 0 — Correctifs de sécurité du socle

**Date :** 19 juillet 2026
**Périmètre :** `apps/api` uniquement (aucun changement côté back-office React)
**Origine :** audit de conformité au cahier des charges v1.2 (§5.2 Règles de sécurité, §10 Exigences non fonctionnelles)

---

## 1. Pourquoi ce lot

L'audit du code par rapport au cahier des charges a montré que trois briques de
sécurité étaient **écrites mais jamais branchées** : elles existaient sous forme
de fichiers, mais aucune requête ne passait dedans. À cela s'ajoutaient deux
failles réelles sur les fichiers et l'absence totale de limitation d'appels.

Ce lot ne rajoute presque pas de code : il **connecte ce qui existait déjà** et
ferme les trous. C'est pour ça qu'il est traité en premier — beaucoup d'effet
pour peu de modifications.

---

## 2. Ce qui a été fait

### 2.1 Les gardes s'appliquent maintenant à toute l'application

**Avant :** chaque contrôleur devait penser à écrire `@UseGuards(JwtAuthGuard, PermissionsGuard)`.
Les 16 contrôleurs admin le faisaient bien, mais **un contrôleur ajouté sans cette
ligne aurait été accessible sans aucun token**. La sécurité reposait donc sur la
vigilance du développeur.

**Après :** les gardes sont déclarées une seule fois dans `app.module.ts` via
`APP_GUARD`. Elles s'appliquent d'office à **toutes** les routes, y compris celles
qui seront ajoutées demain.

```ts
// apps/api/src/app.module.ts
providers: [
  { provide: APP_GUARD, useClass: FriendlyThrottlerGuard }, // 1. limite les appels
  { provide: APP_GUARD, useClass: JwtAuthGuard },           // 2. vérifie le token
  { provide: APP_GUARD, useClass: PermissionsGuard }        // 3. vérifie les droits
]
```

L'ordre compte : le limiteur passe en premier pour qu'une attaque par force
brute soit bloquée avant même qu'on essaie de décoder un token.

**Le décorateur `@Public()`** (nouveau fichier `common/decorators/public.decorator.ts`)
est désormais la seule façon d'ouvrir une route sans connexion. Il est posé sur
`AuthController` — logique, puisque ces routes servent justement à obtenir un
token. L'exception devient **visible et volontaire**, au lieu d'être un oubli
silencieux.

> Note : les `@UseGuards(...)` déjà présents sur les contrôleurs ont été laissés
> en place. Ils ne gênent pas (la garde est simplement évaluée deux fois) et les
> retirer aurait fait un très gros diff sans bénéfice.

### 2.2 Les erreurs ne fuitent plus d'informations techniques

**Avant :** le fichier `http-exception.filter.ts` existait mais n'était monté
nulle part → NestJS utilisait son format par défaut. Et même monté, il renvoyait
`exception.message` pour **toute** erreur : une panne Prisma aurait exposé au
client les noms de tables et de colonnes de la base.

**Après :** le filtre est monté globalement dans `main.ts`, et il fait la
distinction :

| Type d'erreur | Ce que reçoit le client | Ce qui est journalisé |
|---|---|---|
| Erreur HTTP volontaire (401, 403, 404…) | son message métier | rien |
| Erreur serveur (bug, panne base…) | `"Erreur interne du serveur"` | la trace complète + l'id de corrélation |

Toutes les réponses d'erreur suivent maintenant le format du CDC :

```json
{
  "success": false,
  "message": "Permission denied",
  "errors": [],
  "meta": { "correlationId": "3f88b235-ca11-412f-9734-169ac4345eb3" }
}
```

### 2.3 L'identifiant de corrélation est enfin posé

**Avant :** `CorrelationInterceptor` existait, n'était monté nulle part, et
n'aurait de toute façon pas suffi. Un interceptor s'exécute **après** les gardes :
une requête refusée en 401 ou 403 n'aurait donc jamais eu d'identifiant.

**Après :** la logique est passée en **middleware**
(`common/middleware/correlation.middleware.ts`), qui s'exécute **avant** les
gardes. Chaque requête, y compris celles qui sont rejetées, porte son identifiant
dans la réponse et dans l'en-tête `x-correlation-id`.

À quoi ça sert concrètement : quand quelqu'un signale une erreur, il donne cet
identifiant et on retrouve immédiatement la ligne de log correspondante.

L'ancien interceptor a été supprimé (il aurait fait doublon).

### 2.4 Faille corrigée : les fichiers restreints d'autrui étaient lisibles

C'est la correction la plus importante du lot.

**Avant :** dans `file-access.policy.ts`, la visibilité `restricted` était traitée
exactement comme `authenticated` — « être connecté suffit ». Or les fichiers
d'export sont créés en `restricted` (`exports.service.ts`). Résultat :
**n'importe quel compte connecté pouvait lire les exports d'un autre
administrateur**. Aucun contrôle d'appartenance n'existait nulle part.

**Après :** la politique prend maintenant en compte le propriétaire du fichier.

| Visibilité | Qui peut lire |
|---|---|
| `public` | tout le monde, même sans compte |
| `authenticated` | n'importe quel utilisateur connecté |
| `restricted` | **son propriétaire**, ou un admin ayant `files.any.read` |
| `sensitive` | **son propriétaire**, ou un admin ayant `files.sensitive.read` |

Une nouvelle permission `files.any.read` a été ajoutée au seed. Le rôle
`super_admin` la reçoit automatiquement (le seed lui donne toutes les permissions).

### 2.5 Faille corrigée : l'upload laissait tout choisir au client

**Avant :** `POST /files/upload` acceptait tels quels le `storageKey` **et** la
`visibility` envoyés par le client. Deux conséquences :
- un utilisateur pouvait déclarer son propre fichier `public` ;
- il pouvait choisir un chemin de stockage arbitraire, donc écraser le fichier
  d'un autre utilisateur ou sortir du dossier de stockage.

**Après :**
- le `storageKey` est **toujours** calculé par le serveur, à partir d'un UUID ;
- seule l'extension du nom d'origine est reprise, et uniquement si elle est
  simple (lettres/chiffres) ;
- la `visibility` demandée est filtrée par une liste blanche : seuls `restricted`
  (défaut) et `sensitive` sont acceptés. `public` et `authenticated` ne peuvent
  plus être demandés par un client.

### 2.6 Limitation du nombre d'appels (rate limiting)

**Avant :** rien. `POST /auth/login` pouvait être appelé indéfiniment — un robot
pouvait donc essayer des milliers de mots de passe.

**Après :** `@nestjs/throttler` est installé et branché.

| Portée | Limite |
|---|---|
| Toutes les routes | 300 appels / minute / IP |
| `POST /auth/login` | 10 appels / minute / IP |
| `POST /auth/refresh` | 30 appels / minute / IP |

Le message de blocage a été traduit (`FriendlyThrottlerGuard`) : la librairie
renvoyait « ThrottlerException: Too Many Requests », on renvoie désormais
« Trop de tentatives en peu de temps. Merci de réessayer dans une minute. »

### 2.7 Nettoyage

`file-access.guard.ts` a été supprimé : cette garde faisait double emploi avec
`canAccessFile`, et surtout elle n'était **posée sur aucune route** — elle lisait
un champ `request.fileVisibility` que rien ne remplissait jamais.

---

## 3. Fichiers touchés

| Fichier | Nature |
|---|---|
| `src/common/decorators/public.decorator.ts` | créé |
| `src/common/middleware/correlation.middleware.ts` | créé |
| `src/common/guards/throttler.guard.ts` | créé |
| `src/common/interceptors/correlation.interceptor.ts` | supprimé |
| `src/modules/files/file-access.guard.ts` | supprimé |
| `src/app.module.ts` | gardes globales + middleware + throttler |
| `src/main.ts` | filtre d'exception global |
| `src/common/filters/http-exception.filter.ts` | réécrit (anti-fuite + logs) |
| `src/modules/files/file-access.policy.ts` | réécrit (contrôle d'appartenance) |
| `src/modules/files/files.controller.ts` | upload verrouillé |
| `src/modules/files/files.module.ts` | nettoyé |
| `src/modules/auth/jwt-auth.guard.ts` | prise en charge de `@Public()` |
| `src/modules/auth/auth.controller.ts` | `@Public()` + `@Throttle()` |
| `src/common/guards/permissions.guard.ts` | commentaire d'explication |
| `prisma/seed.ts` | permission `files.any.read` |
| `tests/integration/admin-operations.integration.spec.ts` | tests de la nouvelle politique |
| `package.json` | ajout de `@nestjs/throttler` |

---

## 4. Vérifications effectuées

`typecheck` ✅ · `build` ✅ · `vitest` : **88 tests passent** ✅

L'API a ensuite été démarrée réellement (port 3999) et les scénarios suivants ont
été exécutés contre la base :

| # | Scénario | Attendu | Obtenu |
|---|---|---|---|
| 1 | `GET /admin/users` sans token | 401 au format CDC | ✅ 401 + `correlationId` |
| 2 | `POST /auth/login` (bons identifiants) | 200 + tokens | ✅ |
| 3 | `GET /admin/users` avec token super admin | 200 | ✅ |
| 4 | Erreur 404 sur un fichier inexistant | message propre | ✅ |
| 5 | Upload avec `visibility:"public"` + `storageKey` pirate | valeurs ignorées | ✅ `restricted` + clé UUID serveur |
| 6a | Le propriétaire lit son fichier restreint | 200 | ✅ |
| 6b | **Un autre compte lit ce même fichier** | **403** | ✅ (c'était 200 avant le Lot 0) |
| 7 | 12 tentatives de login ratées | blocage | ✅ 429 dès la 10ᵉ |
| 8 | Message de blocage | phrase en français | ✅ |
| 9 | Compte prestataire sur `/admin/users` | 403 | ✅ `Permission denied` |
| 10 | Token invalide | 401 sans détail technique | ✅ `Invalid access token` |

---

## 5. À faire après ce lot

**Relancer le seed** pour que la permission `files.any.read` existe en base :

```bash
corepack pnpm --filter @prestgo/api db:seed
```

> ⚠️ Le seed est idempotent pour les permissions et les rôles (il utilise
> `upsert`), mais **pas** pour les données de démonstration (missions, zones,
> avis) qui seraient dupliquées. Si tu veux repartir propre, recrée la base avant.

**Point d'attention repéré au passage :** le script `start` de
`apps/api/package.json` pointe vers `dist/main.js`, alors que le build produit
`dist/src/main.js` (parce que le dossier `tests/` est inclus dans le `tsconfig`).
`pnpm start` échoue donc en l'état. Ça ne gêne pas `pnpm dev`, mais c'est à
corriger — ce n'était pas dans le périmètre du Lot 0.

---

## 6. Ce que le Lot 0 ne règle PAS

Ces points restent ouverts et seront traités dans les lots suivants :

- **Validation des entrées** : le `ValidationPipe` est global mais tourne à vide
  (aucun fichier `.dto.ts`, `class-validator` jamais importé). → **Lot 1**
- **Hashage** : scrypt est utilisé sans paramètres de coût explicites, et le
  format stocké ne les contient pas — impossible de durcir plus tard sans
  invalider les mots de passe existants.
- **Format de réponse** : appliqué à la main via `ok()` dans chaque contrôleur,
  aucun interceptor ne le garantit.
- **`sort`** : déclaré dans `PaginationQuery` mais implémenté nulle part.
- **IP dans l'audit** : le champ `ip` existe dans `AuditService` mais aucun
  appelant ne le renseigne.
