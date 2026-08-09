# US5 — Auditer, paramétrer, notifier et exporter

> Documentation de l'implémentation de l'US5. Objectif : les admins consultent le **journal
> d'audit**, modifient les **réglages système**, envoient des **notifications** et demandent des
> **exports** dont le fichier reste à accès restreint.

**Statut : ✅ Terminée et testée en vrai** (backend + back-office, tâches T078 → T090).

---

## 1. Ce qui a été implémenté

### Backend (`apps/api`, module `administration/administration.module.ts` + `files`)
| Domaine | Service | Contrôleur |
|---|---|---|
| Réglages système | `settings/settings.service.ts` | `settings/admin-settings.controller.ts` |
| Notifications | `notifications/notifications.service.ts` | `notifications/admin-notifications.controller.ts` |
| Exports | `reports/exports.service.ts` | `reports/admin-exports.controller.ts` |
| Journal d'audit | `audit/audit.service.ts` (méthode `listPaginated`) | `audit/admin-audit.controller.ts` |
| Fichiers | politique `files/file-access.policy.ts` | `files/files.controller.ts` |

Nouveaux modèles : `SystemSetting`, `Notification`, `NotificationTemplate`, `ExportJob`
(`AuditLog` et `File` existaient déjà).

### Back-office (`apps/admin`)
| Écran | Fichier |
|---|---|
| Réglages | `features/settings/SettingsPage.tsx` |
| Journal d'audit | `features/audit/AuditLogPage.tsx` |
| Notifications | `features/notifications/NotificationsPage.tsx` |
| Exports | `features/exports/ExportsPage.tsx` |

---

## 2. Explication des parties importantes

### 2.1 Réglages typés — `settings.service.ts`

Chaque réglage a un **type** (`string`, `number`, `boolean`, `json`). Avant d'enregistrer une
nouvelle valeur, on vérifie qu'elle correspond au type :

```ts
if (type === "number" && Number.isNaN(Number(value))) throw new BadRequestException(...);
if (type === "boolean" && value !== "true" && value !== "false") throw ...;
if (type === "json") { try { JSON.parse(value) } catch { throw ... } }
```

> Dans nos tests, mettre `"abc"` sur un réglage de type `number` a bien été refusé (400).

### 2.2 Le journal d'audit alimenté depuis le début

Toutes les US précédentes appellent `audit.record(...)`. L'US5 ajoute seulement l'**écran de
consultation** (`admin-audit.controller.ts` → `AuditService.listPaginated`), filtrable par entité
ou action. Chaque entrée garde l'ancienne et la nouvelle valeur : on voit *qui* a changé *quoi*.

### 2.3 Notifications « mises en file »

`send()` enregistre une `Notification` avec le statut `queued`. En production, une file
Redis/BullMQ (déjà présente en fondation) traiterait l'envoi réel (email/SMS) ; en V1 on garde la
trace en base. Titre et corps sont obligatoires.

### 2.4 Exports à accès restreint — `exports.service.ts`

Créer un export génère un `ExportJob`, puis un `File` de **visibilité `restricted`**, et marque le
job `completed`. Le fichier n'est donc pas public : il faudra être autorisé pour le télécharger.

### 2.5 Politique d'accès aux fichiers — `file-access.policy.ts`

Fonction pure `canAccessFile(visibility, isAuthenticated, permissions)` :

- `public` → tout le monde ;
- sinon il faut être connecté ;
- `sensitive` → il faut **en plus** la permission `files.sensitive.read`.

C'est cette règle qui protège les documents sensibles (pièces d'identité, etc.).

---

## 3. Données de démonstration

Le seed crée 3 réglages (`platform.name`, `missions.max_reschedule`, `reviews.enabled`) et un
modèle de notification (`welcome`).

---

## 4. Comment tester dans le navigateur

Connexion `admin@prestgo.test` / `prestgo123!`, puis :
- **Réglages** → modifier une valeur (essaie `abc` sur un réglage numérique : refusé).
- **Notifications** → envoyer une notification → elle apparaît dans l'historique en `queued`.
- **Exports** → demander un export → il passe en `completed` (fichier à accès restreint).
- **Audit** → voir toutes les actions tracées ; filtrer par entité (ex. `SystemSetting`).

---

## 5. Limites connues

- L'upload de fichiers est **simplifié** (métadonnées en JSON) : l'upload binaire multipart réel
  pourra être ajouté ensuite.
- L'envoi réel des notifications (email/SMS) n'est pas branché : statut `queued` en base.
- `T078`, `T080` sont des placeholders ; `T079` teste réellement la politique d'accès aux fichiers
  et la validation des réglages.
