# US3 — Superviser missions, litiges, avis et messages

> Documentation de l'implémentation de l'US3. Objectif : les équipes support et modération
> supervisent les **missions**, traitent les **litiges**, lisent le contexte des **messages** et
> modèrent les **avis** signalés — avec décisions motivées et traçabilité.

**Statut : ✅ Terminée et testée en vrai** (backend + back-office, tâches T050 → T067).

---

## 1. Ce qui a été implémenté

### Backend (`apps/api`)
| Domaine | Machine à états / règles | Service | Contrôleur |
|---|---|---|---|
| Missions | `missions/mission-status.machine.ts` | `missions/missions.service.ts` | `missions/admin-missions.controller.ts` |
| Litiges | `disputes/dispute-status.machine.ts` | `disputes/disputes.service.ts` | `disputes/admin-disputes.controller.ts` |
| Avis | `reviews/review-status.rules.ts` | `reviews/reviews.service.ts` | `reviews/admin-reviews.controller.ts` |
| Messages | — | `messages/messages.service.ts` | `messages/admin-messages.controller.ts` |

Tout est regroupé dans le module `operations/operations.module.ts`.

### Back-office (`apps/admin`)
| Écran | Fichier |
|---|---|
| Liste des missions + détail (historique, actions) | `features/missions/MissionsPage.tsx`, `MissionDetailPage.tsx` |
| Liste des litiges + détail (décisions, messages) | `features/disputes/DisputesPage.tsx`, `DisputeDetailPage.tsx` |
| Modération des avis | `features/reviews/ReviewsPage.tsx` |
| Supervision des messages | `features/messages/MessagesPage.tsx` |

### Principaux endpoints
| Méthode | URL | Permission |
|---|---|---|
| GET/PATCH | `/admin/missions`, `/admin/missions/:id/status` | `admin.missions.read` / `admin.missions.manage` |
| POST | `/admin/missions/:id/reschedule`, `/admin/missions/:id/cancel` | `admin.missions.manage` |
| GET | `/admin/messages/threads`, `/admin/messages/threads/:id` | `admin.messages.read` |
| GET/PATCH | `/admin/reviews`, `/admin/reviews/:id/status` | `admin.reviews.read` / `admin.reviews.moderate` |
| GET/POST/PATCH | `/admin/disputes`, `/admin/disputes/:id/assign`, `/admin/disputes/:id/status`, `/admin/disputes/:id/messages` | `admin.disputes.read` / `admin.disputes.manage` |

---

## 2. Explication des parties importantes

### 2.1 Trois machines à états, une même idée

Comme pour les prestataires (US2), chaque domaine a ses transitions autorisées :

**Mission** (`mission-status.machine.ts`) :
```text
draft → pending_provider → confirmed → in_progress → completed → closed
        (à tout moment : confirmed/pending → cancelled, avec motif)
        in_progress/completed → disputed → completed | closed | cancelled
```

**Litige** (`dispute-status.machine.ts`) :
```text
open → in_review → (waiting_client | waiting_provider) → resolved → closed
                    in_review → rejected → closed
```
> `resolved`, `rejected` et `closed` exigent une **décision** (ou motif).

**Avis** (`review-status.rules.ts`) : pas une machine stricte — un modérateur peut publier,
masquer ou rejeter depuis n'importe quel état. **Masquer** et **rejeter** exigent un **motif**.

Le point commun : une fonction `assert...` qui lève une erreur **400** si la transition est
interdite ou si un motif obligatoire manque. C'est cette règle qui protège la cohérence des données.

### 2.2 L'historique des missions — traçabilité

À chaque changement de statut d'une mission, on écrit une ligne dans `MissionStatusHistory`
(ancien statut, nouveau statut, qui, pourquoi). Cela se fait dans une **transaction** avec la mise
à jour de la mission : soit les deux réussissent, soit aucun (pas d'incohérence).

```ts
await this.prisma.$transaction([
  this.prisma.mission.update({ where: { id }, data: { status } }),
  this.prisma.missionStatusHistory.create({ data: { missionId: id, oldStatus, newStatus: status, changedBy, reason } })
]);
```

L'écran détail de la mission affiche cet historique de bas en haut.

### 2.3 Le fil de discussion d'un litige

Un litige (`Dispute`) a des messages (`DisputeMessage`). L'agent peut ajouter un message via
`POST /admin/disputes/:id/messages`, et changer le statut avec une décision motivée. Chaque
décision est tracée dans l'audit.

### 2.4 Côté back-office — actions guidées par le statut

Comme pour les prestataires, chaque écran détail calcule les boutons disponibles à partir du
statut courant (objet `STATUS_ACTIONS`). Quand une action exige un motif/décision, le navigateur
le demande avant l'envoi, et le backend revérifie (double sécurité).

---

## 3. Données de démonstration

Le seed crée un scénario complet autour d'une mission (client **Awa Client** ↔ prestataire
**Kofi Plomberie**) :
- 1 **mission** au statut `confirmed`, avec son historique ;
- 1 **fil de discussion** de 2 messages ;
- 1 **avis** noté 2/5, **signalé** (à modérer) ;
- 1 **litige** ouvert (« Prestation incomplète »).

Les rôles reçoivent les bonnes permissions (super admin a tout).

---

## 4. Comment tester dans le navigateur

Connexion `admin@prestgo.test` / `prestgo123!`, puis dans le menu :
- **Missions** → Superviser → changer le statut / annuler (motif) / voir l'historique.
- **Litiges** → Traiter → passer en revue, résoudre (décision requise), ajouter un message.
- **Avis** → filtrer « reported » → Publier / Masquer (motif) / Rejeter (motif).
- **Messages** → sélectionner un fil pour lire l'échange (lecture seule).

---

## 5. Limites connues

- Les filtres `city` (mission) ne sont pas branchés (dépendent des zones — US4).
- La création de missions/avis/messages par les utilisateurs finaux est hors périmètre (apps
  clients) ; le back-office les **supervise** seulement. Les données viennent du seed.
- `T050`, `T051`, `T053` sont des tests placeholder ; `T052` teste réellement les 3 machines à états.
