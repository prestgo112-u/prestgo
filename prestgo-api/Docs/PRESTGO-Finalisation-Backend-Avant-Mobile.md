# PRESTGO — Finalisation du backend avant le développement mobile

Cahier des charges de clôture du backend. Il rassemble **tout ce qui manque**
pour considérer l'API prête à alimenter les applications mobiles client et
prestataire : la surface fonctionnelle mobile (Lot 6), l'infrastructure de
production (Lot 7) et les améliorations issues de la revue.

**Version :** 1.0 · **29 juillet 2026**
Complète le [CDC v1.2](Cahier_des_charges_PRESTGO_Backoffice_Backend_API_v1.2.md)
et la [Vue d'ensemble de l'API](API-Overview.md).

> Principe directeur (CDC §1.4) : le backend est le cœur unique. Ce document
> **expose** de nouvelles routes qui réutilisent la logique métier existante ;
> il ne la duplique pas.

---

## Sommaire

**Partie I — Diagnostic**
1. [État des lieux : ce qui est solide](#1-état-des-lieux--ce-qui-est-solide)
2. [Pourquoi le backend n'est pas encore prêt pour le mobile](#2-pourquoi-le-backend-nest-pas-encore-prêt-pour-le-mobile)

**Partie II — Lot 6 : Surface fonctionnelle mobile**
3. [Profil commun `/me`](#3-profil-commun-me)
4. [Adresses et favoris du client](#4-adresses-et-favoris-du-client)
5. [Profil prestataire en libre-service](#5-profil-prestataire-en-libre-service)
6. [Documents, portfolio et zones du prestataire](#6-documents-portfolio-et-zones-du-prestataire)
7. [Recherche de prestataires (moteur de la plateforme)](#7-recherche-de-prestataires)
8. [Missions — côté client](#8-missions--côté-client)
9. [Missions — côté prestataire](#9-missions--côté-prestataire)
10. [Reprogrammation à deux parties](#10-reprogrammation-à-deux-parties)
11. [Avis et signalements](#11-avis-et-signalements)
12. [Notifications, appareils, conversations](#12-notifications-appareils-conversations)
13. [Modèle de données — ajouts](#13-modèle-de-données--ajouts)
14. [Règles métier transverses et jobs planifiés](#14-règles-métier-transverses-et-jobs-planifiés)

**Partie III — Lot 7 : Infrastructure de production**
15. [Points techniques à corriger](#15-points-techniques-à-corriger)
16. [Améliorations d'infrastructure pour le mobile](#16-améliorations-dinfrastructure-pour-le-mobile)

**Partie IV — Pilotage**
17. [Critères d'acceptation consolidés](#17-critères-dacceptation-consolidés)
18. [Roadmap et séquencement](#18-roadmap-et-séquencement)

---

# Partie I — Diagnostic

## 1. État des lieux : ce qui est solide

Le socle construit est de bonne qualité et n'est pas à refaire. Sont acquis et
validés :

| Acquis | Détail |
|---|---|
| Format de réponse unifié | `success / message / data / errors / meta` + `correlationId` de bout en bout |
| Trois gardes globales | débit → jeton → droits ; toute route neuve est protégée par défaut |
| RBAC complet | 6 rôles, 31 permissions, super admin automatique |
| Contrôle d'appartenance | client/prestataire d'une mission résolus depuis le jeton, jamais depuis l'URL |
| Machine à états missions | transitions interdites refusées avec message explicite |
| Fichiers à 4 visibilités | justificatifs en `sensitive`, chemin de stockage calculé serveur |
| Audit | 46 points d'écriture, avant/après |
| Rien ne s'efface | catégories et fichiers désactivés, historique préservé (`onDelete: SetNull` sur les auteurs) |
| Statuts métier | conformité totale au CDC §9 |
| Couverture CDC | 96 routes / 77 prévues, 42 tables / 40 prévues, Swagger à jour |

**Conclusion :** l'ossature backend et le back-office sont prêts. Le travail
restant n'est pas de la reprise, c'est de l'**extension**.

## 2. Pourquoi le backend n'est pas encore prêt pour le mobile

Le CDC v1.2 couvrait volontairement le back-office et le socle (§1.3 :
« interfaces finales traitées dans un cahier séparé »). Conséquence : **les
routes que les applications mobiles consommeront n'existent pas encore**. La
revue de la Vue d'ensemble le confirme, domaine par domaine.

### 2.1 Ce qui manque côté client

| Besoin produit | Route attendue | État actuel |
|---|---|---|
| **Réserver une prestation** | `POST /missions` | ❌ absent — seules des routes admin de consultation existent |
| **Trouver un prestataire** | `GET /providers/search` | ❌ absent — on ne peut voir un prestataire que si l'on connaît déjà son `id` |
| **Déposer un avis** | `POST /missions/:id/review` | ❌ absent — le client peut *lire* les avis, pas en *déposer* |
| Gérer ses adresses | `GET/POST/PATCH /me/addresses` | ❌ absent — indispensable au partage de position |
| Favoris | `GET/POST/DELETE /me/favorites` | ❌ absent (prévu CDC ClientsModule) |
| Voir son profil | `GET /me`, `PATCH /me` | ❌ absent |
| Lister ses missions | `GET /me/missions` | ❌ absent — seul l'admin le peut |

### 2.2 Ce qui manque côté prestataire

| Besoin produit | Route attendue | État actuel |
|---|---|---|
| **Créer / compléter son profil** | `POST/PATCH /providers/me` | ❌ absent — seul l'admin modifie un profil |
| **Soumettre ses documents** | `POST /providers/me/documents` | ❌ inversé — aujourd'hui c'est l'admin qui joint le fichier (contraire au workflow §6.1) |
| **Accepter / refuser une mission** | `POST /missions/:id/accept` … | ❌ absent — la machine à états existe mais n'est déclenchée que par l'admin |
| Démarrer / terminer une mission | `/start`, `/complete` | ❌ absent |
| Voir ses missions à venir | `GET /providers/me/missions` | ❌ absent |
| Portfolio | `/providers/me/portfolio` | ❌ absent (table `provider_portfolio_items` présente, aucune route) |

### 2.3 Le diagnostic en une phrase

> Vous avez construit un excellent back-office et un excellent socle. Il reste
> à ouvrir **la surface mobile** — environ 55 routes `me` / publiques qui
> réutilisent la logique déjà écrite — et à **durcir l'infrastructure** avant
> de lancer l'app. La logique métier délicate (machine à états, appartenance,
> statuts, audit) est déjà là : ce lot l'expose, il ne la réécrit pas.

---

# Partie II — Lot 6 : Surface fonctionnelle mobile

Principes communs : préfixe `/api/v1` ; format de réponse identique ; JWT
Bearer ; les routes `me` résolvent l'utilisateur **depuis le jeton** ; le
contrôle est l'**appartenance** (aucune permission admin nouvelle) ; `sort`
réellement appliqué (dette Lot 5 levée ici) ; chaque route documentée dans
Swagger avec DTO et exemples avant d'être livrée.

## 3. Profil commun `/me`

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/me` | profil : identité, statut, rôles, existence des profils client/prestataire |
| `PATCH` | `/me` | modifier `firstName`, `lastName`, `email`, `phone` |
| `POST` | `/me/password` | changer son mot de passe (ancien + nouveau) |
| `DELETE` | `/me` | désactiver son compte → statut `deleted` (données conservées, CDC §9.1) |

**Règles :** modifier email/téléphone remet le champ en non vérifié et
déclenche un OTP ; `POST /me/password` exige l'ancien mot de passe et **révoque
tous les refresh tokens** sauf la session courante ; `DELETE /me` refusé s'il
existe une mission `confirmed` ou `in_progress`.

```jsonc
// GET /me (réponse)
{
  "id": "…", "firstName": "Awa", "lastName": "Koné",
  "email": "awa@example.ci", "phone": "+2250700000000",
  "status": "active", "emailVerified": true, "phoneVerified": true,
  "hasClientProfile": true, "hasProviderProfile": false,
  "providerValidationStatus": null
}
```

## 4. Adresses et favoris du client

### Adresses (partage de position)

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/me/addresses` | lister |
| `POST` | `/me/addresses` | créer |
| `PATCH` | `/me/addresses/:id` | modifier |
| `DELETE` | `/me/addresses/:id` | supprimer (désactivation logique si référencée) |
| `POST` | `/me/addresses/:id/default` | définir par défaut |

```jsonc
// POST /me/addresses
{
  "label": "Maison",            // requis, ≤ 50
  "city": "Abidjan",            // requis
  "commune": "Cocody",          // optionnel
  "details": "Rue des Jardins, portail vert", // ≤ 255
  "latitude": 5.3599, "longitude": -4.0083,   // requis
  "isDefault": false
}
```

**Règles :** max 10 adresses ; la première devient l'adresse par défaut ; une
seule par défaut (bascule en transaction).

### Favoris

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/me/favorites` | lister ses prestataires favoris |
| `POST` | `/me/favorites/:providerId` | ajouter (idempotent) |
| `DELETE` | `/me/favorites/:providerId` | retirer |

**Règles :** seul un prestataire `approved` s'ajoute ; un prestataire suspendu
reste listé avec `available: false`.

## 5. Profil prestataire en libre-service

Corrige l'inversion du workflow §6.1 : le **prestataire** construit et soumet,
l'agent décide.

| Méthode | Route | Rôle |
|---|---|---|
| `POST` | `/providers/me` | créer son profil (statut `profile_incomplete`) |
| `GET` | `/providers/me` | profil + statut + **checklist de complétude** |
| `PATCH` | `/providers/me` | modifier `publicName`, `bio`, `experienceYears` |
| `POST` | `/providers/me/services` | déclarer un service (`serviceTypeId`, `title`, `description`) |
| `PATCH` | `/providers/me/services/:id` | modifier / désactiver |
| `POST` | `/providers/me/submit` | **soumettre le dossier** → `pending_review` |

```jsonc
// GET /providers/me → checklist
{
  "validationStatus": "profile_incomplete",
  "checklist": {
    "profile": true, "services": true, "zones": false,
    "availabilities": true, "documents": false
  },
  "rejectionReason": null,
  "canSubmit": false
}
```

**Règles :** `submit` refusé (avec la checklist dans `errors`) tant que tout
n'est pas vert ; depuis `changes_requested`, le prestataire corrige et
re-soumet (le motif lui est visible) ; un profil `rejected` peut re-soumettre
sauf drapeau admin `resubmission_blocked` ; transitions autorisées côté
prestataire **uniquement** `profile_incomplete → pending_review` et
`changes_requested → pending_review` ; chaque soumission journalisée.

## 6. Documents, portfolio et zones du prestataire

### Documents auto-soumis

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/providers/me/documents` | lister ses documents, statuts, motifs de rejet |
| `POST` | `/providers/me/documents` | soumettre `{ "type": "id_card", "fileId": "…" }` |

**Règles :** le fichier est envoyé via `POST /files/upload` existant puis passé
en `sensitive` au rattachement ; types obligatoires paramétrés
(`provider.required_document_types`) ; re-soumettre crée une **nouvelle
version** `pending` (l'ancienne est conservée) et remet le dossier en file ;
`fileId` doit appartenir au connecté ; la route admin de dépôt à la place du
prestataire est **conservée** comme outil de support.

### Portfolio et zones

| Méthode | Route | Rôle |
|---|---|---|
| `GET/POST/PATCH/DELETE` | `/providers/me/portfolio[/:id]` | réalisations (images publiques, max 20) |
| `GET` | `/providers/me/zones` | ses zones d'intervention |
| `PUT` | `/providers/me/zones` | remplacer la liste `{ "zoneIds": [...] }` (tout ou rien, max 15, zones `active` uniquement) |

## 7. Recherche de prestataires

**Le moteur de la plateforme** — l'écran d'accueil client. Route publique.

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/providers/search` | rechercher |
| `GET` | `/providers/:id/public` | fiche publique complète |

### Paramètres de `GET /providers/search`

| Paramètre | Rôle |
|---|---|
| `categoryId` / `serviceTypeId` | filtrer par offre |
| `latitude`, `longitude`, `radiusKm` (défaut 10, max 50) | recherche géographique |
| `zoneId` | alternative à la géoposition |
| `date`, `startTime` | ne garder que les prestataires **disponibles** à ce créneau |
| `minRating` | note minimale |
| `q` | recherche texte (nom public, titres de services) |
| `sort` | `distance` (défaut si géoposition), `rating`, `recent` |
| `page`, `limit` | pagination |

### Filtres appliqués d'office (non contournables)

Un prestataire n'apparaît que si **toutes** ces conditions sont réunies :
`validation_status = approved` ; compte `active` ; `availability_status`
disponible ; une zone couvre la position/zone demandée ; si `date`/`startTime`
fournis, un créneau hebdomadaire couvre l'horaire **et** aucune indisponibilité
ne le recouvre.

```jsonc
// élément de liste
{
  "id": "…", "publicName": "Kouassi Plomberie",
  "score": 4.7, "reviewsCount": 23, "distanceKm": 3.2,
  "categories": ["Plomberie"], "startingPrice": 5000,
  "avatarFileId": "…", "availableNow": true
}
```

`GET /providers/:id/public` agrège en un appel : profil public, services et
packs actifs avec options, portfolio, agenda, indisponibilités à venir, note
moyenne, distribution des notes, derniers avis. **Aucune donnée interne.**

**Technique :** réutilise le pré-filtre rectangle + haversine de
`zones/nearby` ; croisement disponibilités en SQL. Index à prévoir :
`(validation_status, availability_status)` sur `provider_profiles`,
`(provider_id, weekday)` sur `provider_availabilities`.

## 8. Missions — côté client

| Méthode | Route | Rôle |
|---|---|---|
| `POST` | `/missions` | créer une réservation |
| `GET` | `/me/missions` | ses missions (`status`, `from`, `to`) |
| `GET` | `/missions/:id` | détail (partie prenante — contrôle existant) |
| `POST` | `/missions/:id/cancel` | annuler avec motif |
| `POST` | `/missions/:id/reschedule` | demander une reprogrammation (§10) |

```jsonc
// POST /missions
{
  "providerId": "…", "packId": "…",
  "optionIds": ["…"],
  "scheduledAt": "2026-08-02T09:00:00Z",  // futur, ≥ délai mini
  "addressId": "…",
  "instructions": "Portail vert, sonner deux fois"  // ≤ 500
}
```

**Règles de création :** créée au statut `pending_provider` ; validations en
transaction (prestataire `approved` et disponible ; pack actif et lui
appartenant ; options du pack ; adresse du client ; adresse dans une zone du
prestataire ; créneau couvert ; `scheduledAt ≥ min_lead_time_minutes` ;
anti-doublon même client/prestataire/créneau) ; à la création : notification au
prestataire + création du `chat_thread` + entrée `mission_status_history` ; le
montant indicatif est **figé** dans `quoted_amount`.

**Annulation client :** depuis `pending_provider` et `confirmed` ; à moins de
`cancellation_notice_hours` de l'horaire, acceptée mais marquée `late: true` ;
motif obligatoire ; notification à l'autre partie.

## 9. Missions — côté prestataire

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/providers/me/missions` | ses missions (tri `scheduledAt asc`) |
| `POST` | `/missions/:id/accept` | → `confirmed` |
| `POST` | `/missions/:id/refuse` | → `cancelled` (motif) |
| `POST` | `/missions/:id/start` | → `in_progress` |
| `POST` | `/missions/:id/complete` | → `completed` |
| `POST` | `/missions/:id/cancel` | annuler une mission `confirmed` (motif) |

**Règles :** chaque transition passe par la **machine à états existante** (ces
routes ne font qu'appeler le service commun avec l'acteur « prestataire ») ;
`accept/refuse` depuis `pending_provider` seulement ; `start` depuis
`confirmed`, au plus tôt `start_window_minutes` avant l'horaire ; `complete`
depuis `in_progress`, déclenche la notification « donnez votre avis » ; `closed`
reste une transition admin ou automatique (job §14) ; toute transition notifie
l'autre partie.

## 10. Reprogrammation à deux parties

La table `mission_reschedules` et ses statuts existent ; ce lot expose le cycle.

| Méthode | Route | Acteur |
|---|---|---|
| `POST` | `/missions/:id/reschedule` | client **ou** prestataire propose `{ newDate, reason }` |
| `POST` | `/missions/:id/reschedule/:rid/accept` | **l'autre partie** accepte |
| `POST` | `/missions/:id/reschedule/:rid/reject` | l'autre partie refuse (motif) |

**Règles :** une seule demande `requested` à la fois ; nouvelle date validée
contre l'agenda ; l'acceptation passe en `applied`, met à jour `scheduled_at`,
écrit dans l'historique ; l'auteur ne peut pas accepter sa propre demande ; la
reprogrammation admin existante reste applicable sans acceptation.

## 11. Avis et signalements

Cœur de la boucle de confiance (le « comme Jumia / Yango »).

| Méthode | Route | Rôle |
|---|---|---|
| `POST` | `/missions/:id/review` | déposer un avis `{ rating 1–5, comment ≤ 1000 }` |
| `GET` | `/me/reviews` | ses avis déposés |
| `POST` | `/reviews/:id/report` | signaler `{ reason }` |

**Règles :** réservé aux missions `completed`/`closed` ; **un seul avis par
mission et par auteur** (contrainte unique) ; le client note le prestataire
(V1 ; `target_id` prêt pour la notation croisée future) ; fenêtre de dépôt
`reviews.window_days` ; publication immédiate (`published`), modération a
posteriori (§6.3 inchangé) ; le dépôt et toute modération **recalculent**
`provider_profiles.score` et `reviews_count` ; un signalement passe l'avis en
`reported` sans le masquer tant qu'un modérateur n'a pas tranché.

## 12. Notifications, appareils, conversations

### Notifications & appareils (push)

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/me/notifications` | lister (`unread=true`) |
| `PATCH` | `/me/notifications/:id/read` | marquer lue |
| `POST` | `/me/notifications/read-all` | tout marquer lu |
| `GET` | `/me/notifications/unread-count` | badge |
| `POST` | `/me/devices` | enregistrer un jeton `{ platform, token }` |
| `DELETE` | `/me/devices/:token` | désenregistrer |

**Règles :** nouveau canal `push` ; enregistrement de jeton idempotent
(réaffecté au connecté) ; jeton refusé par FCM/APNs désactivé ; envoi via la
file existante (BullMQ/Redis au Lot 7). Modèles à créer :
`mission.created/accepted/refused/started/completed/cancelled/expired`,
`mission.reschedule.requested/accepted`, `mission.reminder`,
`review.received/request`, `provider.approved/changes_requested/rejected`,
`dispute.opened/message/decided`, `chat.message`.

### Conversations (confort mobile — routes de base déjà existantes)

| Méthode | Route | Rôle |
|---|---|---|
| `GET` | `/me/threads` | ses conversations + dernier message + non-lus |
| `GET` | `/missions/:id/thread` | retrouver le fil d'une mission |
| `PATCH` | `/messages/threads/:id/read` | marquer lu (`read_at`) |

**Règles :** pièce jointe via `fileId` (`restricted`, lisible des deux parties
et du support) ; fil clos consultable mais non modifiable ; regroupement des
push (max 1 par fil et par minute).

## 13. Modèle de données — ajouts

| Table nouvelle | Champs | Remarques |
|---|---|---|
| `client_favorites` | `client_id`, `provider_id`, `created_at` | PK composite, `onDelete: Cascade` |
| `device_tokens` | `id`, `user_id`, `platform`, `token` (unique), `active`, `last_seen_at`, `created_at` | jeton réaffectable |

| Champ à ajouter | Table | Rôle |
|---|---|---|
| `quoted_amount` (nullable) | `missions` | montant indicatif figé |
| `late` (bool) | `mission_cancellations` | annulation tardive |
| `resubmission_blocked` (bool) | `provider_profiles` | blocage re-soumission |
| `reviews_count` (int) | `provider_profiles` | dénormalisation recherche |
| contrainte unique `(review_id, reporter_id)` | `review_reports` | un signalement par personne |
| contrainte unique `(mission_id, author_id)` | `reviews` | un avis par mission |

| Réglage `system_settings` | Défaut |
|---|---|
| `provider.required_document_types` | `["id_card"]` |
| `mission.min_lead_time_minutes` | `60` |
| `mission.cancellation_notice_hours` | `6` |
| `mission.start_window_minutes` | `120` |
| `mission.pending_expiry_hours` | `24` |
| `mission.auto_close_days` | `7` |
| `reviews.window_days` | `14` |

> Ces évolutions de schéma sont les **premières** à livrer via
> `prisma migrate` versionné (§15.1), pas `db push`.

## 14. Règles métier transverses et jobs planifiés

### Transverses

1. **Zéro duplication** : `accept/refuse/start/complete/cancel` appellent le
   même service de transition que `PATCH /admin/missions/:id/status`.
2. Chaque transition écrit `mission_status_history` avec l'acteur réel
   (client, prestataire, ou `system` pour les jobs).
3. `403` (jamais `404` menteur) pour une mission existante mais étrangère.
4. Suspension d'un prestataire : disparaît de la recherche et des favoris
   actifs ; ses missions `confirmed` restent visibles jusqu'à traitement.
5. **Débit mobile** : `POST /missions` 10/h par utilisateur ;
   `POST /reviews/:id/report` 20/j ; `POST /me/devices` 30/j.
6. **Idempotence** : `POST /missions` accepte `Idempotency-Key` (même clé
   sous 10 min = même mission, pas de doublon).

### Jobs planifiés (file existante, Redis au Lot 7)

| Job | Fréquence | Effet |
|---|---|---|
| Expiration missions | 15 min | `pending_provider` trop vieux → `cancelled` (`expired`) + notifications |
| Clôture auto | quotidien | `completed` sans litige depuis `auto_close_days` → `closed` |
| Rappel de mission | quotidien | notification la veille aux deux parties |
| Relance d'avis | quotidien | `completed` sans avis après 48 h → `review.request` (une fois) |
| Nettoyage jetons push | hebdo | désactivation des jetons inactifs 90 j |

Chaque action de job est tracée (`audit_logs`, acteur `system`).

---

# Partie III — Lot 7 : Infrastructure de production

Ces points sont **bloquants pour la mise en production**, indépendamment du
mobile. Plusieurs sont d'autant plus urgents qu'ils deviennent coûteux à
corriger une fois de vrais utilisateurs présents.

## 15. Points techniques à corriger

### 15.1 Migrations Prisma versionnées — priorité haute

Le schéma est appliqué par `prisma db push`, **sans historique**. Impossible de
rejouer proprement les changements sur un autre environnement (préproduction,
production). À corriger **maintenant**, tant que la base peut être recréée sans
douleur : basculer sur `prisma migrate dev` / `migrate deploy`, committer le
dossier `migrations/`. Les ajouts du Lot 6 (§13) constituent la première
migration versionnée.

### 15.2 Format du hash de mot de passe — priorité haute

`scrypt` utilise les valeurs par défaut de Node et le format stocké
(`scrypt$sel$empreinte`) **ne contient pas les paramètres de coût**. Les durcir
plus tard invaliderait tous les mots de passe existants. À corriger **avant**
d'avoir de vrais comptes : stocker le format complet
(`scrypt$N$r$p$sel$empreinte`) et lire les paramètres depuis la chaîne à la
vérification.

### 15.3 File d'attente persistante (Redis + BullMQ) — priorité haute pour le mobile

La file en mémoire ne survit pas à un redémarrage. Un service d'entretien
reprend les notifications restées en attente, mais la file volatile devient
critique dès que les **notifications push** et les **jobs planifiés** (§14)
arrivent. Le code est prêt à basculer : brancher Redis, activer BullMQ.

### 15.4 Paramètre `sort` réellement appliqué

`sort` est accepté et validé mais **pas appliqué** (tris figés sur
`createdAt desc`). Une API qui absorbe silencieusement un paramètre sans effet
piège l'équipe mobile. À implémenter dans ce lot (allow-list de colonnes triables
par ressource) — ou à retirer de la doc, mais l'implémenter est préférable car
la recherche prestataire (§7) en a besoin.

### 15.5 `audit_logs.ip` renseigné

Le champ existe mais n'est **jamais renseigné**. Récupérer l'IP réelle
(en-tête `X-Forwarded-For` derrière un proxy) et la journaliser sur les actions
sensibles.

### 15.6 PostGIS — dette assumée, non bloquante

Le pré-filtre rectangle + haversine donne un résultat identique à PostGIS pour
la volumétrie d'Abidjan au lancement. À garder en dette explicite : le jour où
la montée en charge le justifie, activer l'extension et remplacer le calcul.
**Pas bloquant** pour le mobile.

## 16. Améliorations d'infrastructure pour le mobile

Absentes des deux documents existants, indispensables au scénario « Yango-like ».

### 16.1 Notifications push (FCM / APNs) — indispensable

Une app mobile sans push est morte. Le canal `push` et la table `device_tokens`
(§13) sont définis côté données ; il reste à brancher un **transport réel**
(Firebase Cloud Messaging pour Android, APNs pour iOS) derrière l'interface de
file. Écrire le code contre l'interface, jamais contre le fournisseur.

### 16.2 Fournisseur SMS réel pour l'OTP — indispensable en Côte d'Ivoire

L'inscription se fera massivement par téléphone. Aujourd'hui l'OTP est écrit
dans un journal fichier. Brancher un agrégateur adapté au marché local
(ex. Termii, Africa's Talking, ou un agrégateur couvrant Orange / MTN / Moov CI)
en remplaçant le transport dans `buildTransports()`. Prévoir un repli et une
gestion des échecs d'envoi.

### 16.3 Moteur de matching complet

`zones/nearby` existe ; le vrai besoin est **« prestataires disponibles près de
moi, pour ce service, à cette date »** — c'est exactement ce que résout
`GET /providers/search` (§7). Il est classé ici car c'est le **cœur produit** :
sans lui, pas d'écran d'accueil client.

### 16.4 Expiration automatique et cycle de vie autonome

Le statut mission prévoit « expirer » : le job d'expiration (§14) le concrétise.
Sans lui, des missions restent `pending_provider` indéfiniment. Dépend de
Redis/BullMQ (§15.3).

### 16.5 Politique d'annulation paramétrable

Délai avant lequel un client annule sans conséquence : porté par
`mission.cancellation_notice_hours` (§13) et le drapeau `late` (§8).
`system_settings` est déjà prêt pour ce type de réglage.

### 16.6 WebSocket temps réel pour le chat — optionnel

En REST, le chat fonctionne (lecture/écriture + `read_at`). Un WebSocket
(Socket.IO, CDC §2 « si nécessaire ») améliorera l'expérience de conversation
en direct façon Yango. **Non bloquant** : peut s'ajouter sans changer le
contrat des routes messages.

### Synthèse des améliorations par priorité

| Amélioration | Priorité | Bloquant mobile |
|---|---|---|
| Push FCM/APNs | haute | oui |
| SMS réel (OTP) | haute | oui |
| Matching `providers/search` | haute | oui (dans Lot 6) |
| Redis/BullMQ + jobs | haute | oui |
| Migrations versionnées | haute | non (mais avant prod) |
| Format hash scrypt | haute | non (mais avant vrais comptes) |
| `sort` appliqué | moyenne | non |
| `audit_logs.ip` | moyenne | non |
| WebSocket chat | basse | non |
| PostGIS | basse | non |

---

# Partie IV — Pilotage

## 17. Critères d'acceptation consolidés

**Surface mobile (Lot 6)**

- Un utilisateur consulte/modifie son profil, change son mot de passe (sessions
  révoquées), gère jusqu'à 10 adresses géolocalisées.
- Un prestataire construit seul son dossier (profil, services, zones, agenda,
  documents), suit sa checklist, le soumet ; il apparaît alors dans la file de
  vérification back-office **sans intervention admin**.
- Un client recherche par service, position et disponibilité ; seuls des
  prestataires `approved`, actifs et réellement disponibles apparaissent ; le
  tri par distance est correct.
- Un client crée une mission ; le prestataire la reçoit (push + in-app),
  l'accepte ou la refuse ; `start` et `complete` fonctionnent ; toute
  transition interdite est refusée avec le **même** message que côté admin.
- Une mission non acceptée **expire automatiquement**.
- Une reprogrammation n'est appliquée qu'après acceptation de l'autre partie.
- Après `completed`, le client dépose un avis unique dans la fenêtre ; la note
  moyenne du prestataire est recalculée ; un avis masqué la recalcule aussi.
- Notifications listables/marquables/comptées ; jeton push enregistré,
  désenregistré, invalidé automatiquement si refusé.
- `POST /missions` avec la même `Idempotency-Key` ne crée jamais deux missions.
- Aucune route du lot n'expose de donnée interne (documents d'autrui, notes
  admin, commentaires `internalOnly`, coordonnées d'un prestataire).
- `sort` réellement appliqué sur toutes les listes du lot ; Swagger couvre
  100 % des routes ; chaque règle des §8–11 a au moins un test API.

**Infrastructure (Lot 7)**

- Le schéma est géré par migrations versionnées committées ; un environnement
  neuf se reconstruit par `migrate deploy`.
- Le format de hash contient ses paramètres de coût ; les durcir n'invalide pas
  les comptes.
- La file tourne sur Redis/BullMQ ; les jobs planifiés s'exécutent et sont
  tracés ; un redémarrage ne perd aucune notification.
- L'OTP part par un SMS réel ; le push part par FCM/APNs ; les échecs sont
  gérés et journalisés.
- `audit_logs.ip` est renseigné sur les actions sensibles.

## 18. Roadmap et séquencement

| Étape | Contenu | Débloque |
|---|---|---|
| **6.1** | `/me`, adresses + **migrations versionnées** (§15.1) et **format hash** (§15.2) | écrans profil ; base saine |
| **6.2** | Profil prestataire libre-service + documents + portfolio + zones | inscription prestataire de bout en bout |
| **6.3** | `providers/search` + fiche publique + favoris (+ `sort` appliqué §15.4) | écran d'accueil client |
| **6.4** | `POST /missions` + cycle prestataire + annulations + idempotence | **la boucle de valeur complète** |
| **7.1** | Redis/BullMQ (§15.3) + jobs planifiés (§14) | robustesse du planning |
| **6.5** | Reprogrammation à deux parties | souplesse |
| **6.6** | Avis, signalements, recalcul du score | boucle de confiance |
| **7.2** | Push FCM/APNs (§16.1) + SMS réel (§16.2) + notifications `me` | engagement mobile |
| **7.3** | `audit_logs.ip` (§15.5) ; WebSocket chat (§16.6) et PostGIS (§15.6) en option | finitions |

**Jalon clé :** à l'issue de **6.4 + 7.1**, l'équipe mobile peut développer et
tester le parcours principal (recherche → réservation → exécution) contre un
backend réel et robuste. Les étapes suivantes se livrent **en parallèle** du
développement mobile, sans le bloquer — et sans jamais dupliquer de logique
métier côté frontend, conformément au principe directeur du CDC.

---

## Conclusion

Le socle backend et le back-office sont solides et ne sont pas à refaire. Il
reste deux chantiers nets et bornés : **ouvrir la surface mobile** (Lot 6,
~55 routes qui réutilisent la logique existante) et **durcir l'infrastructure**
(Lot 7, migrations, file persistante, SMS et push réels, hash versionné). Une
fois ces deux lots livrés — le jalon 6.4 + 7.1 étant le point de bascule — le
développement des applications mobiles client et prestataire peut démarrer sur
une base complète, sécurisée et durable.

---

## Documents liés

- [Cahier des charges v1.2](Cahier_des_charges_PRESTGO_Backoffice_Backend_API_v1.2.md)
- [Vue d'ensemble de l'API](API-Overview.md)
