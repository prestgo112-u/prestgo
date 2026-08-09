# Lots 6 et 7 — Surface mobile et infrastructure de production

**Date :** 29 juillet 2026
**Périmètre :** `apps/api`
**Origine :** [PRESTGO — Finalisation du backend avant le développement mobile](PRESTGO-Finalisation-Backend-Avant-Mobile.md) v1.0
**Prérequis :** Lots [0](Lot0-Securite-socle.md) · [1](Lot1-Fonctionnel-bloquant.md) · [2](Lot2-Ecrans-manquants.md) · [3](Lot3-API-complete.md) · [4](Lot4-Modele-de-donnees.md) · [5](Lot5-Fiabilite.md)

---

## 1. Pourquoi ces lots

Le diagnostic du cahier de finalisation tenait en une phrase : le socle et le
back-office sont solides, mais **les routes que les applications mobiles
consomment n'existent pas**. On ne pouvait ni réserver une prestation, ni
trouver un prestataire autrement qu'en connaissant déjà son identifiant, ni
déposer un avis. Un prestataire ne pouvait pas construire son propre dossier :
c'était un agent qui joignait ses justificatifs à sa place, à rebours du
processus voulu par le CDC §6.1.

Deux chantiers, donc :

- **Lot 6** — ouvrir la surface mobile en RÉUTILISANT la logique métier
  existante (machine à états, contrôle d'appartenance, audit) ;
- **Lot 7** — durcir l'infrastructure : migrations versionnées, file
  persistante, SMS et push réels, format de hash pérenne.

**Résultat :** 96 → **155 opérations** documentées dans Swagger, 91 → **163
tests** au vert.

---

## 2. Ce qui a été livré

### Partie I — Surface mobile (Lot 6)

| § | Domaine | Routes |
|---|---|---|
| 3 | Profil commun | `GET/PATCH/DELETE /me`, `POST /me/password` |
| 4 | Adresses et favoris | `/me/addresses` (+ `/default`), `/me/favorites/:providerId` |
| 5 | Profil prestataire libre-service | `POST/GET/PATCH /providers/me`, `/services`, `POST /providers/me/submit` |
| 6 | Documents, portfolio, zones | `/providers/me/documents`, `/providers/me/portfolio`, `PUT /providers/me/zones` |
| 7 | Recherche | `GET /providers/search`, `GET /providers/:id/public` |
| 8 | Missions côté client | `POST /missions`, `GET /me/missions`, `/cancel` |
| 9 | Missions côté prestataire | `GET /providers/me/missions`, `/accept`, `/refuse`, `/start`, `/complete` |
| 10 | Reprogrammation à deux parties | `/reschedule`, `/reschedule/:rid/accept`, `/reject` |
| 11 | Avis et signalements | `POST /missions/:id/review`, `GET /me/reviews`, `POST /reviews/:id/report` |
| 12 | Notifications, appareils, conversations | `/me/notifications`, `/me/devices`, `/me/threads`, `PATCH /messages/threads/:id/read` |

S'y ajoutent les **options de formule** (`/providers/me/service-packs/:id/options`) :
le §8 permet au client de choisir des `optionIds` à la réservation, mais aucune
route ne permettait de les créer — la fonctionnalité aurait été inatteignable.

### Partie II — Infrastructure (Lot 7)

| § | Point | État |
|---|---|---|
| 15.1 | Migrations Prisma versionnées | ✅ `db push` remplacé, historique committé |
| 15.2 | Format du hash de mot de passe | ✅ `scrypt$N$r$p$sel$empreinte`, ré-encodage automatique |
| 15.3 | File persistante Redis + BullMQ | ✅ driver sélectionnable, interface inchangée |
| 15.4 | `sort` réellement appliqué | ✅ liste blanche par ressource |
| 15.5 | `audit_logs.ip` renseigné | ✅ via contexte de requête |
| 15.6 | PostGIS | ⏸️ dette assumée, non bloquante |
| 16.1 | Push FCM / APNs | ✅ transport réel derrière une interface |
| 16.2 | SMS réel pour l'OTP | ✅ Termii et Africa's Talking, avec repli |
| 16.4 | Cycle de vie autonome | ✅ 5 jobs planifiés (§14) |
| 16.6 | WebSocket chat | ⏸️ optionnel, non livré |

---

## 3. Le principe qui gouverne tout : zéro duplication

Le §14.1 l'exige : `accept`, `refuse`, `start`, `complete` et `cancel` doivent
appeler **le même service de transition** que `PATCH /admin/missions/:id/status`.

C'est ce qui a été fait, et c'est allé plus loin que prévu : la logique de
transition a été EXTRAITE de `MissionsService` vers un
`MissionLifecycleService` dédié, et l'ancienne méthode admin y délègue
désormais.

```
  client mobile ─┐
prestataire mobile ─┤
   back-office ─┼──▶ MissionLifecycleService ──▶ mission-status.machine.ts
   jobs planifiés ─┘        (validation, historique, audit, notifications)
```

Quatre acteurs, un seul chemin. Une transition interdite est refusée avec le
même message des quatre côtés — c'est un critère d'acceptation du §17, et il est
couvert par un test.

L'alternative aurait été de recopier la machine à états côté mobile. Elle aurait
fonctionné le premier jour, puis divergé : un statut atteignable depuis
l'application et pas depuis le back-office, ou l'inverse.

---

## 4. Décisions notables

### 4.1 Les sessions de rafraîchissement deviennent réelles

Le §3 demande que changer son mot de passe « révoque tous les refresh tokens
sauf la session courante ». C'était **impossible** avec l'implémentation
existante : le refresh token était un JWT autoportant, que rien côté serveur ne
pouvait annuler. Concrètement, changer son mot de passe après un vol de
téléphone ne coupait rien — le voleur gardait un accès valable sept jours.

Le jeton est désormais une valeur aléatoire opaque, dont seule l'empreinte est
stockée (table `refresh_sessions`), avec :

- **révocation réelle**, individuelle ou en masse ;
- **rotation** à chaque renouvellement — un jeton intercepté ne sert qu'une fois ;
- **relecture des droits en base** à chaque renouvellement. L'ancienne version
  recopiait les permissions du jeton précédent : un compte suspendu gardait ses
  droits sept jours. Le délai maximal est maintenant celui du jeton d'accès,
  quinze minutes.

Une réinitialisation de mot de passe coupe **toutes** les sessions, sans
exception : contrairement au changement volontaire, l'appareil qui fait la
demande n'est pas nécessairement celui du propriétaire légitime.

### 4.2 La checklist du dossier prestataire est calculée à un seul endroit

Elle sert à l'affichage (`GET /providers/me`) et au refus de soumission
(`POST /providers/me/submit`). Les faire diverger produirait le pire des
défauts : une checklist toute verte et un bouton qui refuse. Le calcul vit donc
dans une fonction pure, testée isolément.

Un point mérite d'être signalé : la case « services » exige un service actif
**avec au moins une formule active**. Un service sans formule n'a ni prix ni
durée — il n'est pas réservable. Valider un tel dossier mènerait à une fiche
publique sans bouton de réservation.

### 4.3 La recherche filtre d'abord, paramètre ensuite

Les filtres du §7 (`validation_status = approved`, compte actif, disponibilité,
couverture de zone) sont posés dans le `where` de base, **avant** tout paramètre
d'appel. Aucun paramètre ne peut les desserrer.

Le tri par distance ramène les candidats en mémoire — la distance ne se calcule
pas en SQL sans PostGIS. Un plafond de 500 candidats borne ce coût ; il est très
au-dessus du nombre de prestataires couvrant un même point à Abidjan au
lancement, et l'atteindre serait précisément le signal qu'il faut activer
PostGIS (§15.6).

Une nuance sur le rayon : une zone est retenue si elle **couvre** la position
demandée (le prestataire se déplace jusque-là) **ou** si son centre tombe dans
le rayon de recherche. L'union des deux évite d'écarter un prestataire dont la
zone est large mais centrée un peu plus loin.

### 4.4 Une annulation tardive est acceptée, pas refusée

Le §8 est explicite et le choix mérite d'être compris : en deçà de
`mission.cancellation_notice_hours`, l'annulation passe quand même, mais elle est
marquée `late: true`.

Bloquer le client l'aurait simplement poussé à **ne pas prévenir** — ce qui est
strictement pire pour le prestataire, qui se serait déplacé pour rien.

### 4.5 Un avis signalé reste visible

Signaler passe l'avis en `reported` sans le masquer. Si un signalement suffisait
à faire disparaître un avis, il deviendrait l'arme parfaite contre la critique
légitime. Seul un modérateur tranche — et sa décision **recalcule la note**,
sans quoi la modération n'aurait aucun effet visible.

### 4.6 Idempotence : la clé est libérée en cas d'échec

`POST /missions` accepte `Idempotency-Key` (§14.6). Le point subtil est le
traitement de l'échec : une réservation refusée pour une raison **corrigeable**
(créneau pris entre-temps, adresse hors zone) libère la clé. Sans cela, le
client ne pourrait pas réessayer après correction avant dix minutes.

### 4.7 Le format de hash porte ses paramètres

`scrypt$N$r$p$sel$empreinte`. Chaque empreinte sait avec quels réglages elle a
été produite, ce qui permet de durcir le coût sans invalider l'existant.

Les empreintes de l'ancien format (`scrypt$sel$empreinte`) restent vérifiables :
leurs paramètres implicites — les valeurs par défaut de Node — sont inscrits
noir sur blanc dans le code. Elles sont **ré-encodées automatiquement** à la
première connexion réussie, sans rien demander à leur propriétaire.

### 4.8 L'IP d'audit passe par un contexte de requête

`audit_logs.ip` existait mais n'était jamais renseigné, faute de chemin entre la
requête HTTP et `AuditService.record()` — appelé depuis 46 endroits, tous dans
des services qui ignorent la requête. Un `AsyncLocalStorage` ouvert par le
middleware de corrélation résout ça sans toucher aux 46 appels.

L'en-tête `X-Forwarded-For` n'est lu que si `TRUST_PROXY=true` : il est
déclaratif, le lire sans proxy permettrait à n'importe qui de falsifier l'IP
journalisée.

---

## 5. Migrations versionnées : comment la bascule a été faite

La base était gérée par `prisma db push`, sans historique. Pire : la table
`_prisma_migrations` contenait deux entrées orphelines, dont les dossiers
n'existaient plus dans le dépôt.

La bascule s'est faite en quatre temps :

1. **Baseline** — l'état réel de la base a été capturé
   (`migrate diff --from-empty --to-schema-datasource`) dans
   `20260729090000_baseline`, puis marqué comme appliqué.
2. **Nettoyage** — les entrées orphelines ont été retirées de la table de suivi.
3. **PostGIS neutralisé** — l'ancienne migration `000001_init_postgis` faisait
   `CREATE EXTENSION postgis`, qui échoue sur toute base où l'extension n'est
   pas installée. Elle est conservée (elle figure dans l'historique de certains
   environnements) mais rendue **sans effet**, avec le raisonnement en
   commentaire.
4. **Lot 6** — les évolutions du §13 forment `20260729093000_lot6_surface_mobile`,
   la première vraie migration versionnée, exactement comme le prévoyait le
   cahier.

Un écart a été découvert au passage : `ClientProfile.avatarFileId` et
`defaultAddressId` portaient une clé étrangère **en base** que le schéma Prisma
ne déclarait pas. La première migration allait donc les SUPPRIMER pour
« aligner » la base. Les relations ont été déclarées dans le schéma plutôt que
de perdre cette intégrité.

Les tests eux-mêmes passent maintenant par `migrate deploy` : la suite de
migrations committée est donc vérifiée à chaque exécution, et non découverte
cassée au déploiement.

---

## 6. Modèle de données — ce qui a été ajouté

| Table nouvelle | Rôle |
|---|---|
| `RefreshSession` | sessions révocables (§3) |
| `IdempotencyRecord` | clés d'idempotence (§14.6) |
| `DeviceToken` | jetons push, réaffectables (§13) |
| `ClientFavorite` | favoris client (§13) |
| `MissionOption` | options retenues, prix figé (§8) |

| Champ ajouté | Table | Rôle |
|---|---|---|
| `quotedAmount` | `Mission` | montant indicatif figé |
| `late` | `MissionCancellation` | annulation tardive |
| `decidedBy` / `decidedAt` / `decisionReason` | `MissionReschedule` | accord de l'autre partie |
| `reviewsCount`, `rejectionReason`, `resubmissionBlocked`, `submittedAt`, `avatarFileId` | `ProviderProfile` | recherche, checklist, décision |
| `version` | `ProviderDocument` | re-soumission sans écraser |
| `readAt`, `data` | `Notification` | non-lus et ouverture ciblée |

Contraintes d'unicité : `(missionId, authorId)` sur `Review`,
`(reviewId, reportedBy)` sur `ReviewReport`. La règle est aussi vérifiée dans le
service, mais **seule la contrainte tient face à deux requêtes simultanées**.

Sept réglages `system_settings` du §13 ont été semés, ainsi que les vingt
modèles de notification du §12.

---

## 7. Configuration

Tout est facultatif : sans configuration, l'API fonctionne en mode
développement, et les canaux SMS et push retombent sur la boîte d'envoi
fichier. Ce n'est pas un simulacre — le message est réellement produit et
horodaté, on peut vérifier ce qui serait parti et à qui.

```bash
# File persistante (§15.3) — bullmq dès que REDIS_URL est définie
REDIS_URL="redis://localhost:6379"
QUEUE_DRIVER=bullmq          # bullmq | memory | inline

# Push FCM/APNs (§16.1)
FCM_PROJECT_ID=… FCM_CLIENT_EMAIL=… FCM_PRIVATE_KEY=…

# SMS réel (§16.2)
SMS_PROVIDER=termii          # ou africastalking
TERMII_API_KEY=… TERMII_SENDER_ID=PRESTGO

# IP réelle derrière un proxy (§15.5)
TRUST_PROXY=true
```

Commandes de base de données :

```bash
corepack pnpm --filter @prestgo/api db:migrate   # créer une migration (développement)
corepack pnpm --filter @prestgo/api db:deploy    # appliquer (préproduction, production)
corepack pnpm --filter @prestgo/api db:status    # état de l'historique
```

---

## 8. Vérification

```bash
corepack pnpm --filter @prestgo/api typecheck
corepack pnpm --filter @prestgo/api test
```

**163 tests, 15 fichiers.** Les suites ajoutées :

| Suite | Ce qu'elle protège |
|---|---|
| `me.integration` | identité résolue depuis le jeton, révocation des sessions, carnet d'adresses |
| `mission-flow.integration` | parcours complet recherche → réservation → exécution → avis, idempotence, transitions interdites |
| `scheduled-jobs.integration` | expiration, clôture automatique, traçage `system` |
| `password.spec` | format du hash, compatibilité de l'ancien format |
| `sorting.spec` | `sort` appliqué et borné par une liste blanche |
| `provider-checklist.spec` | complétude du dossier prestataire |

Un test a mis au jour un vrai défaut pendant l'écriture : le refus de soumission
renvoyait `errors: []` au lieu du détail de la checklist. Le filtre d'exception
ne savait pas transporter une liste `errors` posée par une règle métier — il ne
gérait que celles du `ValidationPipe`. Corrigé.

---

## 9. Ce qui reste ouvert

- **PostGIS** (§15.6) — dette assumée. Le pré-filtre rectangle + haversine donne
  un résultat identique pour la volumétrie d'Abidjan au lancement.
- **WebSocket pour le chat** (§16.6) — optionnel. Le chat fonctionne en REST ;
  un WebSocket s'ajoutera sans changer le contrat des routes messages.
- **Notation croisée** (§11) — `targetId` est en place, mais la V1 limite le
  dépôt au client. Ouvrir la notation du client par le prestataire est une
  décision produit, pas une limite technique.
- **Tests du front** — toujours aucun. Seule l'API est couverte.
- **Comptes fournisseurs** — le code FCM et SMS est écrit et branché, mais aucun
  compte n'est configuré. Les brancher est une opération de configuration, sans
  changement de code.

---

## 10. Jalon

Le cahier de finalisation fixait le point de bascule à **6.4 + 7.1** : à
l'issue de ces deux étapes, l'équipe mobile peut développer le parcours
principal contre un backend réel.

Les deux sont livrées, ainsi que 6.1, 6.2, 6.3, 6.5, 6.6, 7.2 et l'essentiel de
7.3. **Le développement des applications mobiles peut démarrer.**

---

## Documents liés

- [Cahier de finalisation](PRESTGO-Finalisation-Backend-Avant-Mobile.md)
- [Cahier des charges v1.2](Cahier_des_charges_PRESTGO_Backoffice_Backend_API_v1.2.md)
- [Vue d'ensemble de l'API](API-Overview.md)
