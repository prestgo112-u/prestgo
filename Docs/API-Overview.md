# PRESTGO — Vue d'ensemble de l'API

Document de référence : **toutes les fonctionnalités exposées par le backend**,
mises en regard du cahier des charges v1.2.

**Version :** 29 juillet 2026 · **155 opérations** · **47 tables** · **31 permissions** · **16 écrans**

> Ce document décrit ce qui existe réellement dans le code, pas ce qui était
> prévu. Chaque route listée a été relevée dans les contrôleurs.

> **Surface mobile.** Les routes `/me`, `/providers/me`, `/providers/search` et
> le cycle de vie des missions ont été ajoutés par les
> [Lots 6 et 7](Lot6-7-Surface-mobile-et-production.md), qui font foi pour ces
> domaines.

---

## Sommaire

1. [Principes généraux](#1-principes-généraux)
2. [Authentification](#2-authentification)
3. [Sécurité et permissions](#3-sécurité-et-permissions)
4. [Surface publique](#4-surface-publique-sans-compte)
5. [Espace prestataire](#5-espace-prestataire)
6. [Espace client et prestataire](#6-espace-client-et-prestataire)
7. [Back-office — administration](#7-back-office--administration)
8. [Fichiers](#8-fichiers)
9. [Modèle de données](#9-modèle-de-données)
10. [Statuts métier](#10-statuts-métier)
11. [Écarts avec le cahier des charges](#11-écarts-avec-le-cahier-des-charges)
12. [Écrans du back-office](#12-écrans-du-back-office)

---

## 1. Principes généraux

### Adresse de base

Toutes les routes sont préfixées par **`/api/v1`**.

```
http://localhost:3000/api/v1/...
```

Documentation interactive (Swagger) : **http://localhost:3000/api/docs**

### Format de réponse

Toutes les réponses suivent le même format (CDC §8) :

```jsonc
// Succès
{
  "success": true,
  "message": "OK",
  "data": { ... },
  "meta": { "page": 1, "limit": 20, "total": 42 }
}

// Erreur
{
  "success": false,
  "message": "Statut de mission inconnu",
  "errors": [{ "code": "validation_error", "message": "Statut de mission inconnu" }],
  "meta": { "correlationId": "3f88b235-ca11-412f-9734-169ac4345eb3" }
}
```

Le **`correlationId`** identifie la requête de bout en bout. Il figure aussi dans
l'en-tête `x-correlation-id` de **chaque** réponse, et permet de retrouver la
ligne correspondante dans les journaux du serveur.

### Codes HTTP

| Code | Signification |
|---|---|
| `200` | succès |
| `201` | création réussie |
| `202` | accepté, traitement en cours (exports, notifications) |
| `400` | données invalides — le détail est dans `errors` |
| `401` | jeton absent, invalide ou expiré |
| `403` | connecté, mais pas le droit d'accéder à cette ressource |
| `404` | ressource introuvable |
| `409` | conflit (email déjà utilisé) |
| `429` | trop d'appels, limite de débit atteinte |

### Pagination

Toutes les listes acceptent :

| Paramètre | Défaut | Contrainte |
|---|---|---|
| `page` | 1 | ≥ 1 |
| `limit` | 20 | ≤ 100 |
| `sort` | propre à chaque liste | **appliqué**, sur une liste blanche de champs par ressource |

`sort` s'écrit `sort=champ`, `sort=-champ` (décroissant) ou `sort=champ:desc`.
Un champ hors de la liste blanche est **refusé** avec la liste des champs
acceptés — l'API n'absorbe plus silencieusement un tri sans effet (§15.4).

Un filtre laissé vide (`?status=`) est traité comme absent.

### Limites de débit

Par adresse IP et par minute :

| Portée | Limite |
|---|---|
| Toutes les routes | 300 |
| `POST /auth/login` | 10 |
| Inscription, mot de passe oublié, envoi de code | 5 |
| Renouvellement de jeton, vérification de code | 30 |

Configurable par variables d'environnement (`THROTTLE_*`).

---

## 2. Authentification

### Principe

Connexion par **JWT** : un `accessToken` (valable 15 minutes) accompagne chaque
requête dans l'en-tête `Authorization: Bearer <token>`. Un `refreshToken`
permet d'en obtenir un nouveau sans redemander le mot de passe.

**Toutes les routes exigent un jeton par défaut.** Les exceptions sont marquées
explicitement dans le code par le décorateur `@Public()` — l'ouverture est donc
un geste volontaire, jamais un oubli.

### Routes

| Méthode | Route | Rôle |
|---|---|---|
| `POST` | `/auth/register` | créer un compte |
| `POST` | `/auth/login` | se connecter |
| `POST` | `/auth/refresh` | renouveler l'`accessToken` |
| `POST` | `/auth/logout` | fermer la session |
| `POST` | `/auth/forgot-password` | demander un lien de réinitialisation |
| `POST` | `/auth/reset-password` | changer son mot de passe |
| `POST` | `/auth/otp/send` | envoyer un code à usage unique |
| `POST` | `/auth/otp/verify` | vérifier ce code (et activer le compte) |

### Parcours d'inscription

```
register  ->  compte créé au statut « pending » (connexion refusée)
   |
otp/send  ->  code à 6 chiffres envoyé
   |
otp/verify -> compte activé (statut « active »)
   |
login     ->  accessToken + refreshToken
```

### Règles de sécurité appliquées

| Règle | Détail |
|---|---|
| Mot de passe | 8 caractères minimum, **au moins une lettre et un chiffre** |
| Jeton de réinitialisation | usage unique, 30 minutes, les précédents sont annulés |
| Code OTP | 6 chiffres, 10 minutes, **5 tentatives maximum** |
| Stockage des secrets | **seule l'empreinte est conservée**, jamais la valeur |
| Non-divulgation | `forgot-password` répond la même chose que le compte existe ou non |
| Activation | seuls les comptes `pending` peuvent être activés — un compte suspendu ne peut pas se réactiver seul |

> **En développement**, aucun email ni SMS n'est envoyé. Ajouter
> `AUTH_EXPOSE_DEV_CODES=true` dans `.env` renvoie le code dans la réponse
> (`devCode` / `devToken`). **Absent par défaut**, donc jamais actif en production.

---

## 3. Sécurité et permissions

### Trois gardes, dans cet ordre

```
Requête
  ↓
1. Limiteur de débit   -> 429 si trop d'appels
  ↓
2. Vérification du jeton -> 401 si absent ou invalide
  ↓
3. Vérification des droits -> 403 si permission manquante
  ↓
Traitement
```

Ces gardes sont déclarées **globalement** : une route nouvellement ajoutée est
protégée d'office.

### Les 31 permissions

| Domaine | Permissions |
|---|---|
| Tableau de bord | `admin.dashboard.read` |
| Utilisateurs | `admin.users.read`, `admin.users.status.update` |
| Clients | `admin.clients.read`, `admin.clients.notes` |
| Prestataires | `admin.providers.read`, `admin.providers.update`, `admin.providers.status.update` |
| Vérifications | `admin.verifications.documents.review` |
| Catalogue | `admin.catalog.read`, `admin.catalog.manage` |
| Zones | `admin.zones.read`, `admin.zones.manage` |
| Disponibilités | `admin.availability.read`, `admin.availability.manage` |
| Missions | `admin.missions.read`, `admin.missions.manage` |
| Messages | `admin.messages.read` |
| Avis | `admin.reviews.read`, `admin.reviews.moderate` |
| Litiges | `admin.disputes.read`, `admin.disputes.manage` |
| Notifications | `admin.notifications.read`, `admin.notifications.send` |
| Réglages | `admin.settings.read`, `admin.settings.update` |
| Rôles | `admin.roles.manage` |
| Audit | `audit.read` |
| Fichiers | `files.any.read`, `files.sensitive.read` |

### Les 6 rôles (CDC §5.1)

`super_admin` · `admin` · `agent_support` · `agent_validation` · `moderator` · `read_only`

Le super admin reçoit automatiquement toutes les permissions. Les autres rôles
se configurent depuis l'écran **Rôles & permissions**.

### Le contrôle d'appartenance

Les routes non-admin (mission, conversation, litige) ne se contentent pas de
vérifier une permission : elles vérifient que **la personne est partie prenante**.

Sont autorisés : le client de la mission, le prestataire qui la réalise, ou un
agent porteur de la permission correspondante. Tout autre compte connecté reçoit
un `403`.

De même, les routes `/providers/me/...` résolvent le prestataire **à partir du
jeton**, jamais d'un identifiant fourni dans l'URL.

---

## 4. Surface publique (sans compte)

8 routes accessibles sans authentification. Elles ne montrent que ce qui est
**actif** et **publié** : une catégorie désactivée ou un avis masqué n'y
apparaît pas.

| Méthode | Route | Contenu |
|---|---|---|
| `GET` | `/categories` | catégories et types de service actifs |
| `GET` | `/zones` | zones actives |
| `GET` | `/zones/nearby` | zones dans un rayon donné, triées par distance |
| `GET` | `/providers/:id/service-packs` | formules d'un prestataire |
| `GET` | `/providers/:id/availabilities` | agenda hebdomadaire |
| `GET` | `/providers/:id/unavailabilities` | absences annoncées |
| `GET` | `/providers/:id/reviews` | avis publiés + note moyenne |

### Recherche géographique

```
GET /zones/nearby?latitude=5.325&longitude=-4.022&radiusKm=10
```

```json
{
  "data": [{
    "name": "Cocody",
    "city": { "name": "Abidjan", "slug": "abidjan" },
    "distanceKm": 5.42
  }]
}
```

**Comment ça marche :** PostGIS n'étant pas installé, la recherche procède en
deux temps — un pré-filtre par rectangle (résolu par l'index
`latitude, longitude`), puis un calcul de distance exact par la formule de
haversine. Le résultat est identique à PostGIS ; seule la montée en charge
diffère.

---

## 5. Espace prestataire

Routes réservées au prestataire connecté. Le profil est déduit du jeton.

| Méthode | Route | Rôle |
|---|---|---|
| `POST` | `/providers/me/service-packs` | créer une formule |
| `PATCH` | `/providers/me/service-packs/:id` | modifier une formule |
| `PUT` | `/providers/me/availabilities` | remplacer tout l'agenda hebdomadaire |
| `POST` | `/providers/me/unavailabilities` | déclarer une absence |
| `DELETE` | `/providers/me/unavailabilities/:id` | annuler une absence |

### Le remplacement de l'agenda

`PUT /providers/me/availabilities` attend l'agenda **complet** :

```json
{ "slots": [
  { "weekday": 1, "startTime": "08:00", "endTime": "12:00" },
  { "weekday": 3, "startTime": "14:00", "endTime": "18:00" }
]}
```

`weekday` : 0 = dimanche … 6 = samedi.

**Tous les créneaux sont validés avant la moindre écriture.** Si le cinquième
est invalide, l'agenda existant reste intact — le prestataire ne se retrouve
jamais avec un agenda à moitié effacé.

Règles refusées : heure de fin avant l'heure de début, créneaux qui se
chevauchent, plus de 50 créneaux.

---

## 6. Espace client et prestataire

Routes accessibles aux **parties prenantes d'une mission**.

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/missions/:id/history` | historique des statuts et reports |
| `GET` | `/messages/threads/:id/messages` | lire la conversation |
| `POST` | `/messages/threads/:id/messages` | écrire dans la conversation |
| `POST` | `/disputes` | ouvrir un litige sur sa mission |
| `GET` | `/disputes/:id` | suivre son litige |

> `GET /disputes/:id` **masque les commentaires internes** des agents. Le
> back-office, lui, voit tout.

Un fil de discussion clos n'accepte plus de message.

---

## 7. Back-office — administration

### 7.1 Tableau de bord

| Méthode | Route | Permission |
|---|---|---|
| `GET` | `/admin/dashboard/summary` | `admin.dashboard.read` |
| `GET` | `/admin/dashboard/charts?days=30` | `admin.dashboard.read` |

`summary` renvoie les 8 indicateurs du CDC §4.2 (utilisateurs total et actifs,
prestataires validés et en attente, missions du jour et en cours, litiges
ouverts, avis à modérer) plus trois listes rapides.

`charts` renvoie : inscriptions par jour, missions par catégorie, par ville et
par statut, taux d'annulation, délai moyen de validation.

### 7.2 Utilisateurs et clients

| Méthode | Route | Permission |
|---|---|---|
| `GET` | `/admin/users` | `admin.users.read` |
| `GET` | `/admin/users/:id` | `admin.users.read` |
| `PATCH` | `/admin/users/:id/status` | `admin.users.status.update` |
| `PATCH` | `/admin/users/:id/roles` | `admin.roles.manage` |
| `POST` | `/admin/users/:id/notes` | `admin.users.read` |
| `GET` | `/admin/clients` | `admin.clients.read` |
| `GET` | `/admin/clients/:id` | `admin.clients.read` |
| `GET` | `/admin/clients/:id/missions` | `admin.clients.read` |
| `POST` | `/admin/clients/:id/notes` | `admin.clients.notes` |

**Un « client »** est un utilisateur sans profil prestataire et sans rôle
interne. Donner un rôle à un compte le fait donc sortir de cette liste.

Filtres : `search` (nom, email, téléphone), `status`.

### 7.3 Rôles et permissions

| Méthode | Route | Permission |
|---|---|---|
| `GET` | `/admin/roles` | `admin.roles.manage` |
| `POST` | `/admin/roles` | `admin.roles.manage` |
| `PATCH` | `/admin/roles/:id` | `admin.roles.manage` |
| `PATCH` | `/admin/roles/:id/permissions` | `admin.roles.manage` |
| `GET` | `/admin/permissions` | `admin.roles.manage` |

### 7.4 Prestataires et vérifications

| Méthode | Route | Permission |
|---|---|---|
| `GET` | `/admin/providers` | `admin.providers.read` |
| `GET` | `/admin/providers/:id` | `admin.providers.read` |
| `PATCH` | `/admin/providers/:id` | `admin.providers.update` |
| `PATCH` | `/admin/providers/:id/status` | `admin.providers.status.update` |
| `POST` | `/admin/providers/:id/notes` | `admin.providers.update` |
| `GET` | `/admin/verifications/providers` | `admin.verifications.documents.review` |
| `GET` | `/admin/verifications/documents/:id` | `admin.verifications.documents.review` |
| `POST` | `/admin/verifications/documents/:id/file` | `admin.verifications.documents.review` |
| `POST` | `/admin/verifications/documents/:id/approve` | `admin.verifications.documents.review` |
| `POST` | `/admin/verifications/documents/:id/reject` | `admin.verifications.documents.review` |

Recherche prestataire : nom public, email **et** téléphone.

**Joindre un justificatif remet le document en attente de revue** : la décision
précédente ne portait plus sur le bon fichier.

Le rejet exige un motif.

### 7.5 Catalogue, zones, disponibilités

| Méthode | Route | Permission |
|---|---|---|
| `GET` | `/admin/categories` | `admin.catalog.read` |
| `POST` | `/admin/categories` | `admin.catalog.manage` |
| `PATCH` | `/admin/categories/:id` | `admin.catalog.manage` |
| `DELETE` | `/admin/categories/:id` | `admin.catalog.manage` |
| `POST` | `/admin/service-types` | `admin.catalog.manage` |
| `PATCH` | `/admin/service-types/:id` | `admin.catalog.manage` |
| `POST` | `/admin/provider-services` | `admin.catalog.manage` |
| `GET` | `/admin/zones` | `admin.zones.read` |
| `POST` | `/admin/zones` | `admin.zones.manage` |
| `PATCH` | `/admin/zones/:id` | `admin.zones.manage` |
| `POST` | `/admin/zones/:id/providers/:providerId` | `admin.zones.manage` |
| `GET` | `/admin/providers/:providerId/availability` | `admin.availability.read` |
| `POST` | `/admin/providers/:providerId/availability` | `admin.availability.manage` |
| `DELETE` | `/admin/providers/:providerId/availability/:slotId` | `admin.availability.manage` |

`DELETE /admin/categories/:id` **désactive** sans supprimer : les missions
passées y font référence.

Une zone active exige latitude, longitude et un rayon positif.

### 7.6 Missions

| Méthode | Route | Permission |
|---|---|---|
| `GET` | `/admin/missions` | `admin.missions.read` |
| `GET` | `/admin/missions/:id` | `admin.missions.read` |
| `PATCH` | `/admin/missions/:id/status` | `admin.missions.manage` |
| `POST` | `/admin/missions/:id/reschedule` | `admin.missions.manage` |
| `POST` | `/admin/missions/:id/cancel` | `admin.missions.manage` |

Filtres : `status`, `from`, `to` (période sur la date planifiée), `providerId`,
`search` (client, prestataire, ville).

Les changements de statut suivent une **machine à états** : une transition non
autorisée est refusée. L'annulation exige un motif. **Rien n'efface
l'historique.**

### 7.7 Messages, avis, litiges

| Méthode | Route | Permission |
|---|---|---|
| `GET` | `/admin/messages/threads` | `admin.messages.read` |
| `GET` | `/admin/messages/threads/:id` | `admin.messages.read` |
| `GET` | `/admin/reviews` | `admin.reviews.read` |
| `PATCH` | `/admin/reviews/:id/status` | `admin.reviews.moderate` |
| `GET` | `/admin/disputes` | `admin.disputes.read` |
| `GET` | `/admin/disputes/:id` | `admin.disputes.read` |
| `POST` | `/admin/disputes` | `admin.disputes.manage` |
| `PATCH` | `/admin/disputes/:id/assign` | `admin.disputes.manage` |
| `PATCH` | `/admin/disputes/:id/status` | `admin.disputes.manage` |
| `POST` | `/admin/disputes/:id/messages` | `admin.disputes.manage` |
| `POST` | `/admin/disputes/:id/files` | `admin.disputes.manage` |

**Commentaire interne** — `POST /admin/disputes/:id/messages` accepte
`internalOnly: true`. Ces messages sont **invisibles du client et du
prestataire** (CDC §4.5).

Masquer ou rejeter un avis exige un motif. Résoudre ou clôturer un litige exige
une décision.

### 7.8 Notifications

| Méthode | Route | Permission |
|---|---|---|
| `GET` | `/admin/notifications` | `admin.notifications.read` |
| `POST` | `/admin/notifications/send` | `admin.notifications.send` |
| `GET` | `/admin/notification-templates` | `admin.notifications.read` |
| `PATCH` | `/admin/notification-templates/:id` | `admin.notifications.send` |
| `GET` | `/admin/notifications/templates` | `admin.notifications.read` |

Canaux : `in_app` (défaut), `email`, `sms`.

Cycle de vie : `queued` → `sent` (avec `sentAt`) ou `failed`.

> **Aucun fournisseur email/SMS n'est configuré.** Les messages sont écrits dans
> `storage/outbox/email.log` et `sms.log` — réellement produits, horodatés et
> consultables. Brancher un vrai SMTP consiste à remplacer une ligne dans
> `buildTransports()`.

Le `code` d'un modèle n'est pas modifiable : c'est la clé utilisée par le code
applicatif.

### 7.9 Réglages, audit, exports

| Méthode | Route | Permission |
|---|---|---|
| `GET` | `/admin/settings` | `admin.settings.read` |
| `PATCH` | `/admin/settings/:key` | `admin.settings.update` |
| `GET` | `/admin/audit-logs` | `audit.read` |
| `GET` | `/admin/exports` | `admin.exports.manage` |
| `POST` | `/admin/exports` | `admin.exports.manage` |
| `GET` | `/admin/exports/:id` | `admin.exports.manage` |

**Audit :** 46 points d'écriture répartis sur 14 modules. Chaque action
sensible enregistre qui, quoi, quand, avant/après. Filtres : `entity`, `action`,
`actorId`.

**Exports :** 5 types (`users`, `providers`, `missions`, `disputes`, `reviews`).
Le CSV utilise le **point-virgule** et un **BOM UTF-8**, pour s'ouvrir
correctement dans Excel français. Le fichier produit est en visibilité
`restricted` : seul son demandeur ou un admin porteur de `files.any.read` peut
le lire.

**Réglages :** la valeur est vérifiée contre le type déclaré (`number`,
`boolean`, `json`).

---

## 8. Fichiers

| Méthode | Route | Rôle |
|---|---|---|
| `POST` | `/files/upload` | envoyer un fichier (multipart, champ `file`) |
| `GET` | `/files/:id` | métadonnées |
| `GET` | `/files/:id/content` | **contenu réel** |
| `DELETE` | `/files/:id` | désactiver (sans supprimer) |

### Contraintes à l'envoi

| Règle | Valeur |
|---|---|
| Taille maximale | 10 Mo |
| Types acceptés | JPEG, PNG, WebP, PDF, texte, CSV |
| Chemin de stockage | **toujours calculé par le serveur** |
| Visibilité demandable | `restricted` (défaut) ou `sensitive` uniquement |

Un client ne peut donc ni rendre son fichier public, ni choisir où il est écrit.

### Les quatre niveaux de visibilité

| Visibilité | Qui peut lire |
|---|---|
| `public` | tout le monde, même sans compte |
| `authenticated` | tout utilisateur connecté |
| `restricted` | **son propriétaire**, ou `files.any.read` |
| `sensitive` | **son propriétaire**, ou `files.sensitive.read` |

Les justificatifs de vérification sont en `sensitive` et appartiennent au
prestataire. Le rôle `agent_validation` reçoit `files.sensitive.read` — sans
quoi il ne pourrait pas ouvrir les pièces qu'il doit examiner.

---

## 9. Modèle de données

**42 tables, 60 clés étrangères, 9 énumérations.**

| Domaine | Tables |
|---|---|
| Comptes | `User`, `Role`, `Permission`, `UserRole`, `RolePermission` |
| Profils | `AdminProfile`, `ClientProfile`, `ProviderProfile` |
| Authentification | `PasswordResetToken`, `OtpCode` |
| Vérification | `ProviderDocument`, `ProviderInternalNote` |
| Catalogue | `CatalogCategory`, `ServiceType`, `ProviderService`, `ServicePack`, `ServicePackOption` |
| Géographie | `City`, `Zone`, `ProviderZone`, `Address` |
| Disponibilités | `ProviderAvailability`, `ProviderUnavailability` |
| Missions | `Mission`, `MissionStatusHistory`, `MissionReschedule`, `MissionCancellation` |
| Conversations | `ChatThread`, `ChatMessage`, `ChatMessageFile` |
| Qualité | `Review`, `ReviewReport` |
| Litiges | `Dispute`, `DisputeMessage`, `DisputeFile` |
| Fichiers | `File`, `ProviderPortfolioItem` |
| Système | `SystemSetting`, `NotificationTemplate`, `Notification`, `ExportJob`, `AuditLog` |

### Choix structurants

**`onDelete: SetNull` sur les auteurs.** Si un compte est supprimé, la ligne
d'historique ou d'audit **survit** avec un auteur à `NULL`. L'historique ne doit
jamais disparaître parce que son auteur n'existe plus.

**Aucune suppression réelle** pour les catégories et les fichiers : on désactive.

**PostGIS non utilisé** : l'extension n'est pas disponible. Les coordonnées sont
des nombres simples, indexés en `(latitude, longitude)`.

---

## 10. Statuts métier

Conformité **totale** au CDC §9 — les trois jeux sont des énumérations natives.

### Utilisateur

`draft` · `pending` · `active` · `rejected` · `suspended` · `deleted`

### Prestataire (validation)

`profile_incomplete` · `pending_review` · `approved` · `changes_requested` ·
`rejected` · `suspended`

### Mission

`draft` · `pending_provider` · `confirmed` · `in_progress` · `completed` ·
`closed` · `cancelled` · `disputed`

Les transitions sont contrôlées par une machine à états. Une transition non
prévue est refusée avec un message explicite.

### Autres

| Énumération | Valeurs |
|---|---|
| Document | `pending`, `approved`, `rejected` |
| Litige | `open`, `in_review`, `waiting_client`, `waiting_provider`, `resolved`, `rejected`, `closed` |
| Avis | `published`, `reported`, `hidden`, `rejected` |
| Signalement | `pending`, `reviewed`, `dismissed` |
| Reprogrammation | `requested`, `accepted`, `rejected`, `applied` |
| Fichier | `public`, `authenticated`, `restricted`, `sensitive` |

---

## 11. Écarts avec le cahier des charges

### Couverture

| Axe CDC | État |
|---|---|
| §8 Catalogue des API | **155 opérations** — les 77 du CDC, plus la surface mobile du Lot 6 |
| §7 Modèle de données | **47 tables** — les 40 du CDC, plus `PasswordResetToken`, `OtpCode` et les 5 tables du Lot 6 |
| §9 Statuts métier | **conformité totale** |
| §5.2 Sécurité | JWT, RBAC, rate limiting, contrôle d'accès fichiers, hashage ✅ |
| §10 Audit | 46 points d'écriture ✅ |
| §10 Documentation | Swagger à jour ✅ |

### Différences de chemin assumées

| CDC | Implémentation | Raison |
|---|---|---|
| `POST /disputes` | existe, **plus** `POST /admin/disputes` | ouverture côté client et côté back-office |
| `/admin/notification-templates` | existe, **plus** `/admin/notifications/templates` | l'ancien chemin est conservé pour ne rien casser |

### Ajouts hors CDC

`GET /zones/nearby`, `PATCH /admin/users/:id/roles`,
`PATCH /admin/roles/:id/permissions`, `POST /admin/disputes/:id/files`,
`GET/POST/DELETE` sur les indisponibilités, `GET /files/:id/content`,
`GET /admin/exports`.

### Ce qui n'est pas satisfait

| Point CDC | État |
|---|---|
| §10 « recherches par zone via index géographiques » | **partiellement** — index B-tree + haversine, PostGIS en dette assumée |
| §2 WebSocket temps réel | **absent** — noté « si nécessaire » dans le CDC, non bloquant |
| Notation croisée client↔prestataire | `targetId` en place, **dépôt limité au client en V1** |

Résolus par les [Lots 6 et 7](Lot6-7-Surface-mobile-et-production.md) :
`sort` est désormais réellement appliqué sur une liste blanche par ressource, la
file tourne sur Redis/BullMQ dès qu'une `REDIS_URL` est configurée,
`audit_logs.ip` est renseigné via le contexte de requête, et les canaux SMS
(Termii, Africa's Talking) et push (FCM/APNs) disposent d'un transport réel —
avec repli sur le journal fichier tant qu'aucun compte fournisseur n'est
configuré.

### Points techniques repris par le Lot 7

1. **Migrations versionnées** ✅ — `db push` est remplacé par
   `prisma migrate`, l'historique est committé
   (`baseline` + `lot6_surface_mobile` + `provider_avatar`). Un environnement
   neuf se reconstruit par `migrate deploy`, et les tests empruntent ce même
   chemin.
2. **Paramètres de hashage** ✅ — le format est désormais
   `scrypt$N$r$p$sel$empreinte`. Durcir le coût n'invalide plus rien ; les
   empreintes de l'ancien format restent vérifiables et sont ré-encodées à la
   première connexion réussie.
3. **File d'attente persistante** ✅ — driver sélectionnable
   (`QUEUE_DRIVER=bullmq|memory|inline`) derrière l'interface `JobQueue`
   inchangée. Les cinq jobs planifiés du §14 en dépendent.

---

## 12. Écrans du back-office

Application `apps/admin` : **React + Vite + react-router-dom**. Elle ne
contient aucune logique métier — chaque écran appelle l'API décrite plus haut
via un client HTTP unique (`src/lib/api-client.ts`) qui attache le jeton
`Authorization: Bearer`, et sait aussi récupérer le **contenu binaire** d'un
fichier protégé (`fetchBlobUrl`) puisqu'un `<img src="...">` classique ne peut
pas porter d'en-tête d'authentification.

**16 écrans**, listés dans `src/routes/protected-routes.tsx` — c'est ce fichier,
et lui seul, qui définit à la fois l'entrée de menu, son URL et la permission
qui la protège (CDC §4.1).

### 12.1 Le cadre commun

| Élément | Rôle |
|---|---|
| `AdminShell` | menu latéral + zone de contenu ; le menu **filtre** ses entrées selon les permissions de l'utilisateur connecté |
| `Protected` | garde de route : redirige vers `/login` si non connecté, affiche **« Accès refusé »** si la permission requise pour l'URL manque |
| `DefaultRedirect` | après connexion (ou sur `/`), renvoie vers la **première page autorisée** — pas systématiquement le tableau de bord, que tout le monde ne peut pas forcément voir |

**Le contrôle de permission est côté URL, pas seulement côté menu** : avant ce
garde, masquer une entrée de menu ne suffisait pas à empêcher d'ouvrir la page
en tapant l'adresse directement. Toute route, y compris les pages de détail
(`/users/:id`, `/missions/:id`...), est associée explicitement à une
permission dans `ROUTE_PERMISSIONS`.

### 12.2 Connexion

| Route | Permission | Contenu |
|---|---|---|
| `/login` | — (publique) | formulaire email + mot de passe → `POST /auth/login` ; les permissions du compte sont chargées dans le même appel et pilotent tout le reste de l'interface |

### 12.3 Les 16 écrans protégés

| # | Route | Écran | Permission | Consomme (API) |
|---|---|---|---|---|
| 1 | `/dashboard` | Tableau de bord | `admin.dashboard.read` | `GET /admin/dashboard/summary`, `GET /admin/dashboard/charts` |
| 2 | `/users`, `/users/:id` | Utilisateurs | `admin.users.read` | `GET/PATCH /admin/users...` |
| 3 | `/clients`, `/clients/:id` | Clients | `admin.clients.read` | `GET /admin/clients...` |
| 4 | `/providers`, `/providers/:id` | Prestataires | `admin.providers.read` | `GET/PATCH /admin/providers...` |
| 5 | `/verifications` | Vérifications | `admin.verifications.documents.review` | `GET/POST /admin/verifications/...` |
| 6 | `/catalog` | Catalogue | `admin.catalog.read` / `.manage` | `GET/POST/PATCH/DELETE /admin/categories`, `/admin/service-types` |
| 7 | `/zones` | Zones | `admin.zones.read` / `.manage` | `GET/POST/PATCH /admin/zones` |
| 8 | `/missions`, `/missions/:id` | Missions | `admin.missions.read` / `.manage` | `GET/PATCH/POST /admin/missions...` |
| 9 | `/messages` | Messages | `admin.messages.read` | `GET /admin/messages/threads...` |
| 10 | `/reviews` | Avis | `admin.reviews.read` / `.moderate` | `GET/PATCH /admin/reviews...` |
| 11 | `/disputes`, `/disputes/:id` | Litiges | `admin.disputes.read` / `.manage` | `GET/PATCH/POST /admin/disputes...` |
| 12 | `/notifications` | Notifications | `admin.notifications.read` / `.send` | `GET/POST /admin/notifications...` |
| 13 | `/roles` | Rôles & permissions | `admin.roles.manage` | `GET/POST/PATCH /admin/roles`, `/admin/permissions` |
| 14 | `/settings` | Réglages | `admin.settings.read` / `.update` | `GET/PATCH /admin/settings...` |
| 15 | `/audit` | Audit | `audit.read` | `GET /admin/audit-logs` |
| 16 | `/exports` | Exports | `admin.exports.manage` | `GET/POST /admin/exports...` |

### 12.4 Détail des écrans

**Tableau de bord** — les 8 cartes chiffrées du CDC §4.2 (utilisateurs total et
actifs, prestataires validés et en attente, missions du jour et en cours,
litiges ouverts, avis à modérer), chacune cliquable vers l'écran correspondant.
Sélecteur de période 7/30/90 jours appliqué à 4 graphiques (inscriptions par
jour, missions par catégorie/ville/statut, taux d'annulation, délai moyen de
validation).

**Utilisateurs** — recherche (nom, email, téléphone) + filtre par statut.
Actions sur chaque ligne : **Suspendre** / **Réactiver**. Page de détail :
affectation de rôles (`admin.roles.manage`), ajout d'une note interne.

**Clients** — recherche ; page de détail : adresses enregistrées, historique
des missions passées, notes internes.

**Prestataires** — file filtrable par statut de validation
(`pending_review`, `approved`, `rejected`…) et recherche (nom public, email,
téléphone). Page de détail :
- liste des documents avec **Joindre**/**Remplacer**, **Approuver**,
  **Rejeter** (grisés tant qu'aucun fichier n'est attaché — CDC : jamais de
  décision à l'aveugle) ;
- panneau **Disponibilités** : ajout/suppression de créneaux hebdomadaires ;
- notes internes ;
- **décision sur le prestataire** : transitions contextuelles selon le statut
  actuel (Approuver, Rejeter, Suspendre, Réactiver), certaines exigeant un
  motif.

**Vérifications** — vue transverse (tous prestataires confondus) de la file de
documents à examiner : filtre `pending`/`approved`/`rejected` + recherche par
nom de prestataire. **Consulter** ouvre l'aperçu du fichier (via
`fetchBlobUrl`, donc avec le jeton) avant de décider.

**Catalogue** — ajout de catégorie, activer/désactiver (jamais de suppression
réelle — CDC : l'historique des missions y fait référence), et par catégorie,
`ServiceTypeEditor` pour ajouter des types de service.

**Zones** — liste, activer/désactiver, `ZoneEditor` pour créer une zone
(nom, latitude, longitude, rayon en km).

**Missions** — filtres statut / période / recherche (client, prestataire,
ville), bouton **Réinitialiser**. Page de détail : actions contextuelles selon
le statut (state machine — ex. **Clôturer**, **Annuler** avec motif
obligatoire), formulaire de **reprogrammation**, historique complet des
changements de statut.

**Messages** — écran de **supervision en lecture seule** : liste des fils par
mission (statut + nombre de messages), sélection d'un fil pour lire les
échanges. Aucune action d'écriture côté back-office ici.

**Avis** — modération : **Publier**, **Masquer**, **Rejeter**.

**Litiges** — page de détail : **Affecter** un agent, actions contextuelles
selon le statut (**Résoudre**, **Rejeter**, **Clôturer**, certaines exigeant
une décision), zone de message. La case **« commentaire interne »**
(`internalOnly`, CDC §4.5) existe côté API mais **pas encore côté
interface** — l'agent ne peut donc pas encore poster un commentaire invisible
du client depuis cet écran (à faire manuellement via l'API/Swagger en
attendant).

**Notifications** — formulaire titre + message pour un envoi manuel, plus
historique des notifications déjà envoyées.

**Rôles & permissions** — colonne de gauche : liste des rôles (avec nombre de
permissions et badge « système » pour les rôles non modifiables) et formulaire
de création (code, nom, description). Colonne de droite : matrice de
permissions à cocher pour le rôle sélectionné, regroupées par module,
sauvegardées en un appel.

**Réglages** — liste des réglages système, édition de la valeur puis
**Enregistrer** (le type déclaré — `number`/`boolean`/`json` — est vérifié côté
API avant écriture).

**Audit** — filtre par entité (ex. `Mission`, `ProviderProfile`), tableau
paginé (action, entité, acteur, date) avec navigation **Précédent**/**Suivant**.

**Exports** — choix du type (`users`, `providers`, `missions`, `disputes`,
`reviews`), **Demander un export**, puis **Télécharger le CSV** dès que le job
passe à `completed`.

### 12.5 Ce qui n'a pas encore d'écran

Fonctionnalités déjà exposées par l'API (§7) mais sans interface dédiée dans
`apps/admin` :

| Fonctionnalité API | Route API | Contournement actuel |
|---|---|---|
| Commentaire interne sur un litige | `POST /admin/disputes/:id/messages` (`internalOnly: true`) | Swagger ou appel direct |
| Preuves jointes à un litige | `POST /admin/disputes/:id/files` | Swagger ou appel direct |
| Indisponibilités exceptionnelles d'un prestataire | `POST/GET/DELETE .../unavailabilities` | Swagger ou appel direct |
| Gestion des `provider-services` (rattacher un prestataire à un type de service) | `POST /admin/provider-services` | Swagger ou appel direct |
| Modèles de notification | `GET/PATCH /admin/notification-templates` | Swagger ou appel direct |

Ces routes sont documentées et testées côté API (§7.7, §7.8) ; seul l'écran
manque.

---

## Documents liés

- [README](README.md) — démarrage et guide de test
- [Cahier des charges v1.2](Cahier_des_charges_PRESTGO_Backoffice_Backend_API_v1.2.md)
- [Lot 0](Lot0-Securite-socle.md) · [Lot 1](Lot1-Fonctionnel-bloquant.md) · [Lot 2](Lot2-Ecrans-manquants.md) · [Lot 3](Lot3-API-complete.md) · [Lot 4](Lot4-Modele-de-donnees.md) · [Lot 5](Lot5-Fiabilite.md)
