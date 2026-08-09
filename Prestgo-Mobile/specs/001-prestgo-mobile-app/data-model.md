# Phase 1 — Modèle de données (côté application)

**Feature**: Application mobile PRESTGO (client + prestataire)
**Date**: 2026-07-30

Ce document décrit les **modèles de domaine de l'application mobile** : ce qu'elle
lit, ce qu'elle écrit, ce qu'elle valide avant d'écrire, et ce qu'elle conserve
localement. Il ne décrit pas le schéma de la base du service, qui n'est pas de son
ressort.

Conventions :
- Tous les modèles sont **immuables** (`freezed`) avec sérialisation
  (`json_serializable`), suffixés `Dto` pour la couche `data` et sans suffixe pour
  le domaine quand une transformation est nécessaire.
- « **L** » = validé localement avant envoi (confort de saisie) ; « **S** » = règle
  arbitrée par le service, jamais recalculée par l'application (porte G1).
- Les identifiants sont des UUID transportés en `String`.
- Les montants sont des nombres nus, affichés en XOF par le formateur unique.

---

## 1. Session et compte

### 1.1 `AuthTokens`

| Champ | Type | Notes |
|---|---|---|
| `accessToken` | String | JWT, durée de vie 15 min |
| `refreshToken` | String | chaîne opaque hexadécimale, 7 jours, **tournante** |

**Persistance** : `flutter_secure_storage` **uniquement**. Jamais en base locale,
jamais dans un journal, jamais dans un rapport d'incident.

**Règle de rotation (S)** : chaque renouvellement révoque l'ancien jeton de
renouvellement. L'écriture des deux jetons est **atomique** : un remplacement
partiel déconnecte l'utilisateur au renouvellement suivant.

### 1.2 `Me` — utilisateur connecté

| Champ | Type | Règles / usage |
|---|---|---|
| `id` | String | identité de « moi » pour tous les tests d'appartenance |
| `firstName`, `lastName` | String? | repli sur l'email pour le nom affiché |
| `email`, `phone` | String? | au moins un des deux existe |
| `status` | enum `UserStatus` | `draft`, `pending`, `active`, `rejected`, `suspended`, `deleted` |
| `emailVerified`, `phoneVerified` | bool | pastille « non vérifié » |
| `roles` | List\<String\> | rôles d'administration — **jamais utilisé pour l'aiguillage** |
| `hasClientProfile` | bool | **informatif seulement** (comptes historiques à `false`) |
| `hasProviderProfile` | bool | pilote l'aiguillage |
| `providerId` | String? | identité prestataire, sert à empêcher l'auto-réservation |
| `providerValidationStatus` | enum? `ProviderValidationStatus` | pilote l'aiguillage |
| `createdAt` | DateTime | « membre depuis » |
| `pendingVerifications` | List\<PendingVerification\> | **présent seulement en réponse à une modification de profil** |

`PendingVerification` : `{ channel: 'email' | 'sms', target: String }`.
⚠️ `channel == 'sms'` correspond au motif de vérification `phone_verification` — le
mapping doit être explicite.

**Règle d'accès (S)** : l'espace client est ouvert dès que `status == active`,
indépendamment de `hasClientProfile`.

**Persistance** : mise en cache **persistante** jusqu'à invalidation — c'est elle qui
permet de router au démarrage sans réseau.

### 1.3 `UserDevice`

| Champ | Type | Règles |
|---|---|---|
| `platform` | enum | `android`, `ios` (`web` non ciblé) |
| `token` | String | 10 à 512 caractères (**L**) ; jamais renvoyé par le service |
| `active`, `lastSeenAt` | bool, DateTime | affichage « appareils connectés » |

**Persistance** : le jeton d'appareil courant est conservé en **stockage sécurisé**
(il faut pouvoir le désenregistrer avant déconnexion et lors d'un changement de
jeton).

### 1.4 Aiguillage — table de décision (S)

| `hasProviderProfile` | `providerValidationStatus` | Destination |
|---|---|---|
| `false` | `null` | Espace client (+ entrée « Devenir prestataire ») |
| `true` | `profile_incomplete` | Reprise de l'onboarding (hub checklist) |
| `true` | `pending_review` | Écran d'attente ; espace client toujours accessible |
| `true` | `changes_requested` | Écran de correction avec motif |
| `true` | `rejected` | Écran d'information + re-soumission si non bloquée |
| `true` | `approved` | Espace prestataire complet |
| `true` | `suspended` | Écran d'information, contact support |

---

## 2. Profil, adresses, favoris

### 2.1 `Address`

| Champ | Type | Validation |
|---|---|---|
| `id` | String | — |
| `label` | String | 1 à 50 caractères, obligatoire (**L**) |
| `city` | String | 1 à 80 caractères, obligatoire (**L**) |
| `commune` | String? | ≤ 80 ; chaîne vide traitée comme absente (**L**) |
| `details` | String? | ≤ 255 (**L**) |
| `latitude`, `longitude` | double | **obligatoires**, coordonnées valides (**L**) |
| `isDefault` | bool | modifiable par une action dédiée uniquement |
| `createdAt` | DateTime | — |

**Invariants** : au plus **10** adresses par compte (**L** : l'ajout est indisponible
au-delà) ; l'adresse par défaut est renvoyée en premier par le service ; une adresse
sans coordonnées ne peut pas servir de lieu d'intervention (**S**).

**Suppression** : deux issues possibles — retrait réel, ou archivage si l'adresse est
référencée par des missions passées. Dans les deux cas la ligne disparaît du carnet ;
le motif renvoyé est affiché tel quel.

**Persistance** : cache **persistant** jusqu'à invalidation.

### 2.2 `FavoriteProvider`

`{ id, publicName, bio, score, reviewsCount, categories: List<String>, available, favoritedAt }`

⚠️ `available` signifie « validé et non suspendu » (**S**), **pas** une disponibilité
d'agenda. Un favori à `available == false` reste listé, grisé, non réservable.

---

## 3. Catalogue et recherche

### 3.1 `Category` / `ServiceType`

`Category { id, name, slug, description?, iconFileId?, active, displayOrder, serviceTypes: List<ServiceType> }`
`ServiceType { id, name, slug, description? }`

Liste **non paginée**. Sélecteur à deux niveaux (catégorie → type de service).
**Persistance** : cache persistant, durée de vie 24 h (quasi statique).

### 3.2 `Zone`

`{ id, name, latitude, longitude, radiusKm, active, city: { id?, name } }`
Liste **non paginée** ; cache persistant 24 h.

### 3.3 `ProviderSearchResult`

`{ id, publicName, score, reviewsCount, distanceKm?, categories: List<String>, startingPrice?, avatarFileId?, availableNow }`

Pièges de rendu :
- `score == 0` **et** `reviewsCount == 0` → afficher « Nouveau », pas « 0 étoile ».
- `distanceKm == null` (aucune position envoyée) → masquer la ligne de distance.
- `startingPrice == null` → masquer le prix d'appel.
- `categories` est ici un **tableau de chaînes**, alors que la fiche publique renvoie
  des **objets** : deux modèles distincts, à ne pas fusionner.

**Paramètres de recherche** (`ProviderSearchQuery`, tous facultatifs) :
`categoryId`, `serviceTypeId` (prioritaire sur `categoryId`), `latitude`,
`longitude`, `radiusKm` (1 à 50, défaut 10), `zoneId` (ignoré si position fournie),
`date` (AAAA-MM-JJ), `startTime` (HH:MM), `minRating` (0 à 5), `q` (≤ 120),
`sort` (`distance` | `rating` | `recent`), `page`, `limit` (≤ **50**).

**Combinaisons interdites (L, à prévenir avant l'appel)** : `sort=distance` sans
position ; `date` sans `startTime` ou l'inverse.

**Persistance** : **mémoire seulement** (résultats dépendants de la position et de
l'heure).

### 3.4 `ProviderPublicProfile`

`{ id, publicName, bio, experienceYears, avatarFileId?, availableNow, score,
reviewsCount, startingPrice?, categories: List<CategoryRef>, services:
List<PublicService>, portfolio: List<PortfolioItem>, availability:
List<WeeklySlot>, upcomingUnavailabilities: List<Unavailability>, zones:
List<ZoneRef>, ratingDistribution: Map<String,int>, latestReviews: List<Review>,
memberSince }`

`PublicService { id, title, description?, serviceType: { id, name, category },
packs: List<ServicePack> }`

**Un seul chargement alimente tout l'écran** : ne pas fragmenter en appels séparés
vers les formules, l'agenda ou les avis.

**Persistance** : mémoire seulement.

---

## 4. Offre du prestataire

### 4.1 `ProviderProfile` (vue « mon dossier »)

| Champ | Type | Règles |
|---|---|---|
| `id` | String | le `providerId` |
| `publicName` | String | 2 à 120 caractères (**L**) |
| `bio` | String? | ≤ 2000 ; facultative à la création mais **exigée par la checklist** |
| `experienceYears` | int? | 0 à 70 (**L**) |
| `validationStatus` | enum | cf. §1.4 |
| `availabilityStatus` | enum | `available`, `busy`, `unavailable` |
| `score`, `reviewsCount` | double, int | lecture seule |
| `checklist` | `ProviderChecklist` | **calculée par le service** (**S**) |
| `requiredDocumentTypes` | List\<String\> | **source unique** de l'écran justificatifs |
| `rejectionReason` | String? | affiché en tête des écrans de correction |
| `resubmissionBlocked` | bool | masque définitivement la re-soumission |
| `submittedAt` | DateTime? | date de dépôt du dossier |
| `canSubmit` | bool | **pilote le bouton « Soumettre »** (**S**) |
| `avatarFileId` | String? | photo publique |

`ProviderChecklist { profile, services, zones, availabilities, documents }` — cinq
booléens, **jamais recalculés localement**. Chaque ligne fausse ouvre l'étape
correspondante.

**Sémantique de `availabilityStatus` (S)** :

| Valeur | Effet |
|---|---|
| `available` | visible en recherche, pastille « disponible » |
| `busy` | **toujours visible et réservable** ; seule la pastille change |
| `unavailable` | disparaît de la recherche et refuse toute réservation |

**Verrou (S)** : en `pending_review`, toute modification de `publicName`, `bio`,
`experienceYears` ou `avatarFileId` est refusée ; `availabilityStatus` **seul** reste
modifiable.

### 4.2 `ProviderService`

`{ id, title, description?, active, createdAt, serviceType: { id, name, category },
packs: List<ServicePack> }`

Validation : `serviceTypeId` obligatoire, `title` 3 à 150 caractères, `description`
≤ 1000 (**L**). **Pas de suppression** : `active: false` désactive.

### 4.3 `ServicePack` et `PackOption`

`ServicePack { id, title, description?, price, durationMinutes, active, options: List<PackOption> }`

| Champ | Validation (**L**) |
|---|---|
| `title` | 2 à 150 caractères |
| `description` | ≤ 2000 |
| `price` | nombre ≥ 0 |
| `durationMinutes` | entier 5 à 1440 |

`PackOption { id, title, price, durationMinutes, active }` — `title` 2 à 150,
`price` ≥ 0, `durationMinutes` 0 à 1440 (défaut 0).

**Effet de bord à afficher (S)** : un changement de prix ne modifie **pas** le montant
des missions déjà créées ; désactiver toutes les formules d'un prestataire le fait
disparaître de la recherche.

### 4.4 `WeeklySlot` (agenda hebdomadaire)

| Champ | Type | Validation |
|---|---|---|
| `weekday` | int | 0 à 6, **0 = dimanche** (**L**) |
| `startTime`, `endTime` | String `HH:MM` | format 24 h (**L**) |

**Règles reproduites localement (L, messages serveur non contractualisés)** :
`endTime > startTime` ; aucun chevauchement sur un même `weekday` ; au plus **50**
créneaux.

⚠️ Les heures sont des **chaînes**, manipulées sans conversion de fuseau. Le contrôle
de disponibilité côté service compare le jour et l'heure **UTC** de l'intervention à
ces créneaux.

**Écriture** : remplacement intégral de la liste.

### 4.5 `Unavailability`

`{ id, startAt, endAt, reason? }` — `endAt > startAt`, pas de chevauchement avec une
absence existante (**L**), `reason` ≤ 300.

### 4.6 `ProviderDocument`

`{ id, type, status: 'pending'|'approved'|'rejected', version, rejectionReason?,
reviewedAt?, createdAt, file: FileRef }`

Vue d'écran fournie par le service : `requiredTypes`, `missingTypes`, `current`
(dernière version par type), `documents` (toutes les versions).

**Règles (S)** :
- Un document `approved` ne se remplace pas.
- Un nouveau dépôt crée une **version**, il n'écrase rien.
- Un dépôt alors que le dossier est en `changes_requested` le renvoie
  **automatiquement** en `pending_review` → recharger le dossier après chaque dépôt.
- Pas de suppression.

### 4.7 `PortfolioItem`

`{ id, title?, description?, displayOrder, createdAt, file: FileRef }` — `title`
≤ 120, `description` ≤ 1000, `displayOrder` 0 à 100, **20 réalisations au maximum**,
images uniquement. Le réordonnancement se fait élément par élément (aucune route de
lot).

---

## 5. Missions

### 5.1 `MissionListItem`

`{ id, status, scheduledAt, quotedAmount?, durationMinutes, packTitle, clientName,
providerId, providerName, providerAvatarFileId?, city, commune, createdAt }`

⚠️ `quotedAmount` peut être `null` (missions antérieures au montant figé) : afficher
« — », jamais « 0 XOF ».

**Tris par défaut (S, non re-triés localement)** : client → `scheduledAt`
décroissant ; prestataire → `scheduledAt` **croissant**.

### 5.2 `MissionDetail`

`{ id, status, scheduledAt, instructions?, quotedAmount?, createdAt,
client: { id, firstName, lastName },
provider: { id, publicName, score, reviewsCount, avatarFileId? },
pack: { id, title, price, durationMinutes, providerService: {...} },
options: List<PackOption>, address: Address,
thread: { id, status }?, cancellation: Cancellation?,
reschedules: List<RescheduleRequest>, reviews: List<{ id, authorId, rating }> }`

Usages dérivés :
- `thread.id` : porte d'entrée de la messagerie ; le fil existe dès la création.
- `reschedules` ne contient que les demandes **en attente**, pas l'historique.
- `reviews` sert uniquement à savoir si **moi** j'ai déjà noté
  (`reviews.any((r) => r.authorId == me.id)`).
- `cancellation { reason, details?, late, createdAt }` : `late` est affiché
  explicitement.
- **Aucune coordonnée personnelle** de l'autre partie n'est exposée.

### 5.3 Machine à états des missions (S — lecture seule)

```
draft            → pending_provider
pending_provider → confirmed | cancelled
confirmed        → in_progress | cancelled
in_progress      → completed | disputed
completed        → closed | disputed
disputed         → completed | closed | cancelled
cancelled        → (terminal)
closed           → (terminal)
```

**L'application ne réimplémente pas cette machine.** Elle en dérive uniquement
l'affichage des actions :

| Statut | Actions prestataire | Actions client | Communes |
|---|---|---|---|
| `pending_provider` | Accepter, Refuser | Annuler | Message, Proposer un report |
| `confirmed` | Démarrer (fenêtre), Annuler | Annuler | Message, Report, Répondre à un report |
| `in_progress` | Terminer | — | Message |
| `completed` | — | Laisser un avis (fenêtre) | Message, Ouvrir un litige |
| `closed`, `cancelled` | — | — | Consultation seule |
| `disputed` | — | — | Suivi du litige |

Règles associées :
- **Refuser ≠ Annuler** : refus avant acceptation, annulation après. Jamais les deux
  boutons ensemble.
- `closed` et `disputed` ne sont **jamais** atteignables par un bouton (tâche
  planifiée ou parcours de litige).
- Un motif d'au moins 3 caractères est exigé pour refus, annulation et refus de
  report.
- Aucune transition n'est **jamais** rejouée automatiquement.

### 5.4 `BookingDraft` (état local, jamais envoyé tel quel)

| Champ | Type | Règles |
|---|---|---|
| `providerId`, `packId` | String | issus de la fiche publique |
| `optionIds` | List\<String\> | uniques, **≤ 10** (**L**) |
| `scheduledAt` | DateTime | envoyé en **UTC** (**L**) |
| `addressId` | String | adresse du carnet, géolocalisée |
| `instructions` | String? | ≤ 500, compteur affiché (**L**) |
| `idempotencyKey` | String (UUID v4) | **généré une fois** à l'affichage du récapitulatif |

**Calculs locaux, identiques à ceux du service** :
`totalPrice = pack.price + Σ options.price` ;
`totalDuration = pack.durationMinutes + Σ options.durationMinutes`.

**Cycle de vie de la clé d'idempotence** : générée à l'ouverture du récapitulatif,
réutilisée à chaque tentative sur le **même contenu** (y compris après coupure
réseau), **renouvelée dès qu'un élément du contenu change**. Ne jamais la générer
dans une méthode de construction de widget.

**Contrôles locaux avant envoi (L)** : créneau contenu entièrement dans un créneau
hebdomadaire hors absences ; délai minimum de réservation en vigueur respecté ;
prestataire ≠ moi-même ; adresse géolocalisée.

### 5.5 `RescheduleRequest`

`{ id, oldScheduledAt, newScheduledAt, reason?, status: 'requested'|'accepted'|
'rejected'|'applied', createdBy, decidedBy?, decidedAt?, decisionReason?, createdAt }`

Règles d'affichage : **une seule demande en attente par mission** ; les actions
Accepter/Refuser sont masquées sur `createdBy == me.id` ; le créneau est **revalidé
au moment de l'acceptation** (une contre-proposition est proposée en cas d'échec).

### 5.6 `MissionHistoryEntry`

`{ id, oldStatus?, newStatus, reason?, createdAt }` — alimente la frise
chronologique. Sert aussi à dater l'entrée en `completed` pour la fenêtre de dépôt
d'avis.

---

## 6. Avis

`Review { id, rating: 1..5, comment?, status: 'published'|'reported'|'hidden'|
'rejected', createdAt, mission?: { id, scheduledAt, provider } }`

Validation locale : `rating` entier 1 à 5, `comment` ≤ 1000.

**Conditions d'affichage du bouton « Laisser un avis » (calculables localement)** :
mission `completed` ou `closed` **et** je suis le client **et** aucun avis de moi
**et** la fenêtre de dépôt en vigueur n'est pas écoulée (date d'entrée en `completed`
lue dans l'historique). Le service reste l'autorité.

**Modération** : un avis `reported` **reste visible** ; `hidden` et `rejected`
affichent une mention de retrait à la place du contenu. **Ni modification ni
suppression** ne sont possibles.

**Signalement** : motif de 3 à 500 caractères, impossible sur ses propres avis, au
plus 20 par jour.

---

## 7. Messagerie

`Thread { id, missionId, missionStatus, scheduledAt, status: 'open'|..., counterpartName,
counterpartAvatarFileId?, lastMessage?, unreadCount, createdAt }`

`Message { id, senderId?, message, createdAt, readAt?, files: List<FileRef> }`

- `counterpartName` est **déjà résolu du bon côté** par le service : aucune logique
  conditionnelle par rôle.
- `senderId == null` → message système ; `senderId == me.id` → « moi ».
- Envoi : `message` de 1 à 4000 caractères, au plus **3** pièces jointes distinctes
  (**L**).
- Un fil non `open` masque la saisie.
- Ordre par défaut **croissant** : la page 1 est le **début** du fil ; l'écran demande
  l'ordre décroissant pour ouvrir sur les messages récents.

**Persistance** : cache persistant par fil (relecture hors ligne).

---

## 8. Notifications

`AppNotification { id, type, title, body, data: NotificationPayload, readAt?, createdAt }`

`NotificationPayload` — quatre formes, **identiques en push et en interne** :

| Type | Charge utile |
|---|---|
| `mission` | `{ missionId }` |
| `chat` | `{ missionId, threadId }` |
| `reschedule` | `{ missionId, rescheduleId }` |
| `review` | `{ missionId, reviewId }` |

Codes émis : `mission.created`, `mission.accepted`, `mission.refused`,
`mission.started`, `mission.completed`, `mission.cancelled`, `mission.expired`,
`mission.reminder`, `mission.reschedule.requested`, `mission.reschedule.accepted`,
`review.received`, `review.request`, `provider.approved`,
`provider.changes_requested`, `provider.rejected`, `dispute.opened`,
`dispute.message`, `dispute.decided`, `chat.message`.

**Règles** : marquage lu idempotent (mise à jour optimiste sans risque) ; **pas de
suppression** ; l'auteur d'une action n'est jamais notifié de sa propre action.

**Persistance** : mémoire seulement.

---

## 9. Fichiers

`FileRef { id, originalName, mimeType, size, visibility: 'public'|'restricted'|'sensitive' }`

Règles d'envoi (**L**) : ≤ **10 Mo** ; types acceptés `image/jpeg`, `image/png`,
`image/webp`, `application/pdf`, `text/plain`, `text/csv` ; avatar, portfolio et
réalisations restreints aux images.

Effets de visibilité (**S**) : un justificatif rattaché passe en `sensitive` ; un
avatar ou une réalisation passe en `public` ; le retrait d'une réalisation la ramène
en `restricted` (invalider le cache d'image correspondant).

**Persistance** : les contenus `public` (avatars, portfolio) peuvent être mis en
cache disque ; les contenus `sensitive` **jamais** (FR-098).

---

## 10. Réglages publics

`PublicSettings { missionMinLeadTimeMinutes, missionCancellationNoticeHours,
missionStartWindowMinutes, missionPendingExpiryHours, missionAutoCloseDays,
reviewsWindowDays }`

Lus **une fois au démarrage**, conservés en mémoire, avec valeurs de repli en cas
d'échec : 60 min, 6 h, 120 min, 24 h, 7 j, 14 j. Les constantes ne sont **jamais** la
source de vérité une fois la route jointe (porte G3).

---

## 11. Litige

`Dispute { id, missionId, reason, status, messages: List<DisputeMessage>, createdAt }`

Structure contractualisée côté service mais non capturée en appel réel : les écrans
d'ouverture et de suivi sont volontairement minimalistes en V1 et seront ajustés
contre le service au moment du développement. Les commentaires internes de modération
ne sont jamais renvoyés.

---

## 12. Persistance locale — synthèse

| Donnée | Support | Durée de vie | Motif |
|---|---|---|---|
| Jetons de session, jeton d'appareil | Stockage sécurisé | jusqu'à déconnexion | secrets |
| `Me` | Base locale | jusqu'à invalidation | routage au démarrage hors ligne |
| Catégories, zones | Base locale | 24 h | quasi statiques |
| Carnet d'adresses | Base locale | jusqu'à invalidation | peu volumineux, très consulté |
| Missions (1re page, par rôle) | Base locale | affichée avec son âge | agenda du jour hors ligne |
| Détail de mission | Base locale | affiché avec son âge | adresse et instructions sur place |
| Messages par fil | Base locale | affiché avec son âge | relecture hors ligne |
| Recherche, fiche publique | Mémoire | session | dépendants de la position et de l'heure |
| Notifications, compteurs | Mémoire | session | volatils par nature |
| Contenus de fichiers `public` | Cache d'images | géré par le cache | avatars, portfolio |
| Contenus de fichiers `sensitive` | **Jamais** | — | justificatifs (FR-098) |

**Purge** : la déconnexion et la désactivation de compte effacent le stockage
sécurisé **et** l'intégralité de la base locale, puis recréent le conteneur d'état
(SC-012).
