# US2 — Valider les prestataires

> Documentation de l'implémentation de l'US2. Objectif : les agents de validation examinent
> les profils prestataires et leurs documents, puis **approuvent, rejettent ou demandent des
> corrections** — avec motif obligatoire et traçabilité (audit).

**Statut : ✅ Terminée et testée en vrai** (backend + back-office, tâches T038 → T049).

---

## 1. Ce qui a été implémenté

### Backend (`apps/api`)
| Fonctionnalité | Fichiers clés |
|---|---|
| Modèles prestataire / document / note interne | `prisma/schema.prisma` |
| Machine à états de validation (transitions autorisées) | `src/modules/providers/provider-status.machine.ts` |
| Service prestataires (liste, détail, changement de statut) | `src/modules/providers/providers.service.ts` |
| Service documents (approuver / rejeter avec motif) | `src/modules/documents/provider-documents.service.ts` |
| Endpoints prestataires | `src/modules/providers/admin-providers.controller.ts` |
| Endpoints vérification documents | `src/modules/documents/admin-verifications.controller.ts` |
| Prestataires de démonstration | `prisma/seed.ts` |

### Back-office (`apps/admin`)
| Écran | Fichier |
|---|---|
| File de validation (liste filtrable par statut) | `src/features/providers/ProviderValidationQueue.tsx` |
| Détail prestataire + documents + décisions | `src/features/providers/ProviderDetailPage.tsx` |

### Nouveaux endpoints de l'API
| Méthode | URL | Permission | Rôle |
|---|---|---|---|
| GET | `/admin/providers` | `admin.providers.read` | Liste (filtre `validationStatus`) |
| GET | `/admin/providers/:id` | `admin.providers.read` | Détail + documents + notes |
| PATCH | `/admin/providers/:id` | `admin.providers.update` | Modifier nom/bio/expérience |
| PATCH | `/admin/providers/:id/status` | `admin.providers.status.update` | Changer le statut de validation |
| POST | `/admin/verifications/documents/:id/approve` | `admin.verifications.documents.review` | Approuver un document |
| POST | `/admin/verifications/documents/:id/reject` | `admin.verifications.documents.review` | Rejeter (motif obligatoire) |

---

## 2. Explication des parties importantes

### 2.1 La machine à états — `provider-status.machine.ts`

Un prestataire passe par plusieurs statuts. On ne peut pas sauter n'importe où : la « machine à
états » définit les chemins autorisés.

```text
profile_incomplete → pending_review
pending_review     → approved | rejected | changes_requested
changes_requested  → pending_review
approved           → suspended
suspended          → approved | rejected
rejected           → (état final)
```

Dans le code, c'est un simple tableau associatif :

```ts
const TRANSITIONS = {
  pending_review: ["approved", "rejected", "changes_requested"],
  approved: ["suspended"],
  // ...
};
```

La fonction `assertTransition(from, to, reason)` fait **deux vérifications** :
1. La transition `from → to` est-elle dans la liste ? Sinon → erreur **400**.
2. Le statut d'arrivée exige-t-il un motif (`rejected`, `changes_requested`, `suspended`) ?
   Si oui et qu'aucun motif n'est fourni → erreur **400**.

> C'est cette fonction qui a bloqué, dans nos tests, la transition `approved → pending_review`
> et le rejet sans motif.

### 2.2 Motif obligatoire pour un rejet — `provider-documents.service.ts`

Règle métier US2 : **on ne rejette jamais un document sans expliquer pourquoi**.

```ts
if (!reason || reason.trim() === "") {
  throw new BadRequestException("Un motif de rejet est obligatoire");
}
```

Quand un document est approuvé/rejeté, on enregistre aussi **qui** l'a revu (`reviewedBy`) et
**quand** (`reviewedAt`), pour la traçabilité.

### 2.3 Les nouveaux modèles de données — `schema.prisma`

- **ProviderProfile** : le profil du prestataire (nom public, bio, statut de validation…).
  Il est relié à un `User` (relation un-à-un via `userId @unique`).
- **ProviderDocument** : un justificatif (identité, assurance…), avec son statut
  (`pending` / `approved` / `rejected`) et son motif de rejet éventuel.
- **ProviderInternalNote** : une note interne d'agent, non visible du prestataire.

Le mot-clé Prisma `@relation(...)` relie ces tables entre elles ; `onDelete: Cascade` signifie
que si on supprime un prestataire, ses documents et notes sont supprimés avec lui.

### 2.4 Côté back-office — décisions guidées par le statut

Dans `ProviderDetailPage.tsx`, les boutons d'action proposés dépendent du statut actuel, pour
refléter la machine à états du backend :

```ts
const STATUS_ACTIONS = {
  pending_review: [ Approuver, Demander des corrections (motif), Rejeter (motif) ],
  approved: [ Suspendre (motif) ],
  // ...
};
```

Quand une action exige un motif, le navigateur le demande (`window.prompt`) avant l'envoi.
Si le backend refuse quand même (double sécurité), un message d'erreur s'affiche.

---

## 3. Données de démonstration

Le seed crée 2 prestataires en attente de revue (mot de passe `prestgo123!`) :
- **Kofi Plomberie** (`kofi.plombier@prestgo.test`) — 2 documents
- **Ama Électricité** (`ama.electricite@prestgo.test`) — 1 document

Le rôle **agent_validation** reçoit les permissions de validation (en plus du super admin qui a tout).

---

## 4. Comment tester dans le navigateur

1. Connexion : `admin@prestgo.test` / `prestgo123!`
2. Menu **« Prestataires »** → la file de validation.
3. Choisir le filtre **« En attente de revue »** → cliquer **Examiner** sur un prestataire.
4. Sur le détail : **Approuver** / **Rejeter** un document (le rejet demande un motif),
   puis **Approuver** / **Demander des corrections** / **Rejeter** le prestataire.
5. Chaque décision est tracée dans l'audit (visible sur le tableau de bord).

---

## 5. Limites connues

- Les filtres `city` et `categoryId` de la liste (prévus dans l'OpenAPI) ne sont pas encore
  branchés : ils dépendent des zones et du catalogue (**US4**).
- Les documents n'ont pas encore de fichier réel attaché (upload de fichiers = **US5**) ; on gère
  pour l'instant leur type et leur statut de validation.
- Les tests `T038` et `T040` sont des placeholders ; `T039` teste réellement la machine à états.
