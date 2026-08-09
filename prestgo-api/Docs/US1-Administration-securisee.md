# US1 — Administrer la plateforme en sécurité (MVP)

> Documentation de l'implémentation de l'US1. Objectif : que les utilisateurs internes
> (admins, agents) se connectent, ne voient que les modules autorisés, et ne fassent que
> les actions permises — le tout tracé dans un journal d'audit.

**Statut : ✅ Terminée et testée en vrai** (backend + back-office, tâches T024 → T037).

---

## 1. Vue d'ensemble

L'application est un **monorepo** : plusieurs projets dans un seul dépôt.

```
apps/
├── api/     → le backend (NestJS) : reçoit les requêtes HTTP, parle à la base de données
└── admin/   → le back-office (React) : les écrans que l'admin utilise dans son navigateur
```

Le navigateur (React) envoie des requêtes à l'API (NestJS), qui lit/écrit dans PostgreSQL.

```
[Navigateur / React]  --HTTP-->  [API / NestJS]  --SQL-->  [PostgreSQL]
     port 5173                       port 3000
```

---

## 2. Ce qui a été implémenté

### Backend (`apps/api`)
| Fonctionnalité | Fichiers clés |
|---|---|
| Connexion / déconnexion / rafraîchissement du token | `src/modules/auth/` |
| Hachage réel des mots de passe (scrypt) | `src/common/security/password.ts` |
| Vérification du token + des permissions | `src/modules/auth/jwt-auth.guard.ts`, `src/common/guards/permissions.guard.ts` |
| Utilisateurs : liste, détail, changement de statut | `src/modules/users/` |
| Rôles & permissions | `src/modules/roles/` |
| Tableau de bord (chiffres clés) | `src/modules/admin/` |
| Journal d'audit | `src/modules/audit/` |
| Compte super admin de départ | `prisma/seed.ts` |

### Back-office (`apps/admin`)
| Écran | Fichier |
|---|---|
| Connexion | `src/features/auth/LoginPage.tsx` |
| Mémoire de session (garder connecté) | `src/features/auth/auth.store.tsx` |
| Tableau de bord | `src/features/dashboard/DashboardPage.tsx` |
| Liste des utilisateurs | `src/features/users/UsersPage.tsx` |
| Détail d'un utilisateur | `src/features/users/UserDetailPage.tsx` |
| Navigation protégée + routes | `src/app/App.tsx`, `src/app/AdminShell.tsx` |

---

## 3. Explication de quelques parties du code

### 3.1 Le hachage du mot de passe — `common/security/password.ts`

On ne stocke **jamais** un mot de passe en clair. On le transforme en une « empreinte »
impossible à inverser, avec l'algorithme **scrypt** (intégré à Node).

- `hashPassword("prestgo123!")` → produit `scrypt$<sel>$<empreinte>` que l'on met en base.
- À la connexion, `verifyPassword(saisie, empreinteStockée)` recalcule l'empreinte et compare.

Le **sel** est une valeur aléatoire ajoutée avant le hachage : deux personnes avec le même
mot de passe auront des empreintes différentes (protection contre les attaques par dictionnaire).

### 3.2 Les « guards » (videurs) — la sécurité des routes

Un **guard** dans NestJS est comme un videur à l'entrée d'une route : il laisse passer ou refuse.
Sur les routes admin, il y en a **deux à la suite** :

```ts
@UseGuards(JwtAuthGuard, PermissionsGuard)   // s'exécutent AVANT chaque route du contrôleur
```

1. **`JwtAuthGuard`** (`modules/auth/jwt-auth.guard.ts`)
   Lit le token « Bearer » envoyé par le navigateur, le vérifie, et attache l'utilisateur
   décodé sur `request.user`. Pas de token valide → **401 (non connecté)**.

2. **`PermissionsGuard`** (`common/guards/permissions.guard.ts`)
   Regarde la permission exigée par la route (via `@Permissions("...")`) et vérifie que
   `request.user.permissions` la contient. Sinon → **403 (interdit)**.

Exemple sur le dashboard (`modules/admin/dashboard.controller.ts`) :

```ts
@Get("summary")
@Permissions("admin.dashboard.read")   // il faut CETTE permission pour entrer
async summary() { ... }
```

### 3.3 D'où viennent les permissions ? — le token JWT

À la connexion, le serveur met les rôles et permissions **dans le token** lui-même :

```ts
const payload = { sub: user.id, roles, permissions };   // auth.service.ts
```

Le token est une chaîne `entête.données.signature`. Les « données » contiennent la liste des
permissions. Le back-office les **décode** (fonction `decodeToken` dans `auth.store.tsx`) pour
afficher uniquement les menus autorisés — sans appel serveur supplémentaire.

### 3.4 La réponse standard de l'API — `common/contracts/api-response.ts`

Toutes les réponses ont la **même forme**, ce qui simplifie le front :

```json
{ "success": true, "message": "OK", "data": { ... }, "meta": { "page": 1, "total": 42 } }
```

On l'obtient avec la fonction `ok(data, meta)`. Pour une liste paginée :

```ts
return ok(result.data, { page: result.page, limit: result.limit, total: result.total });
```

### 3.5 Le journal d'audit — `modules/audit/audit.service.ts`

Chaque action sensible est enregistrée en base via `audit.record(...)`. Exemple à la connexion :

```ts
await this.audit.record({ actorId: user.id, action: "auth.login", entity: "User", entityId: user.id });
```

C'est ce que tu vois dans « Activité récente » sur le tableau de bord.

### 3.6 Côté React : rester connecté — `features/auth/auth.store.tsx`

- Le **contexte React** (`AuthProvider`) partage l'état de connexion à toute l'app.
- Le token est sauvegardé dans le `localStorage` du navigateur → tu restes connecté même
  après avoir rafraîchi la page.
- `useAuth()` est un petit raccourci pour lire cet état depuis n'importe quel écran.

### 3.7 Protéger les pages — `app/App.tsx`

Le composant `Protected` vérifie que tu es connecté ; sinon il te renvoie vers `/login`.

```tsx
<Route path="/dashboard" element={<Protected><DashboardPage /></Protected>} />
```

---

## 4. Comment lancer le projet

Prérequis : **PostgreSQL** installé et démarré, base `prestgo` créée, mot de passe renseigné
dans `apps/api/.env`.

```powershell
# 1. Créer les tables (une seule fois, ou après un changement de schéma)
corepack pnpm --filter @prestgo/api exec prisma db push

# 2. Créer le compte super admin + rôles + permissions (une seule fois)
corepack pnpm --filter @prestgo/api exec prisma db seed

# 3. Démarrer les deux serveurs (dans deux terminaux séparés)
corepack pnpm --filter @prestgo/api dev      # API   → http://localhost:3000
corepack pnpm --filter @prestgo/admin dev    # front → http://localhost:5173
```

**Connexion :** `admin@prestgo.test` / `prestgo123!`

---

## 5. Choix techniques et limites à connaître

- **PostGIS désactivé** pour l'instant (commenté dans `prisma/schema.prisma`). Il ne sert
  qu'aux zones géographiques de l'**US4** ; on le réactivera à ce moment-là.
- **`pendingProviders`** sur le dashboard compte provisoirement les utilisateurs « en attente »,
  car le modèle *Prestataire* n'existe pas encore (il arrive en **US2**).
- Le lien **« Audit »** du menu ramène au dashboard pour l'instant : la vraie page Audit est
  prévue en **US5**.
- Les tests `T024`–`T026` sont des tests « placeholder » (vérifications simples), pas encore
  de vrais tests branchés sur la base.

---

## 6. Sécurité — les garde-fous en place

- 🔒 Mots de passe hachés (jamais en clair).
- 🔒 Chaque route admin exige un token valide **et** la bonne permission.
- 🔒 Sans token → 401 ; sans la permission → 403.
- 🔒 Chaque connexion et chaque changement de statut sont tracés dans l'audit.