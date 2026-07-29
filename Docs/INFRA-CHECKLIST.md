# Checklist de mise en service — Redis/BullMQ, SMS, Push

**Public :** équipe ops / infrastructure.
**Nature de ce document :** procédure de configuration. **Aucune commande ici
n'a été exécutée**, aucun secret n'a été renseigné ni inventé — c'est à l'équipe
qui a accès aux comptes fournisseurs et à l'environnement de production de
suivre ces étapes.

Deux briques ont leur **code déjà écrit, testé et branché**. Constaté lors d'un
audit du 29 juillet 2026 : la file d'attente persistante (Redis/BullMQ) était
inactive ; **elle a depuis été activée dans l'environnement de développement
local** (§1.1 mis à jour le même jour). Les transports réels de notification
(SMS, push) restent inactifs, faute de comptes fournisseurs — §2 inchangé.

---

## 1. Redis + BullMQ

### 1.1 État actuel — MIS À JOUR le 29 juillet 2026

Redis était déjà installé sur la machine de développement
(`C:\Redis`, port Windows officieux, service Windows nommé `redis`) mais
`QUEUE_DRIVER` restait forcé à `memory`. Activé en basculant `.env` sur
`QUEUE_DRIVER=bullmq` (§1.3 ci-dessous) — vérifié fonctionnel (§1.4).

**Point de vigilance découvert à l'activation :** la version installée est
**Redis 5.0.14.1**. BullMQ (via `ioredis`) émet un avertissement au démarrage :
```
It is highly recommended to use a minimum Redis version of 6.2.0
             Current: 5.0.14.1
```
Ce n'est pas bloquant pour l'usage actuel (notifications, jobs planifiés — pas
de fonctionnalité BullMQ avancée type "sandboxed processors" ou certaines
commandes de streaming) : la connexion s'établit, les tâches sont traitées.
Mais avant une mise en production, il est recommandé de monter vers Redis
6.2+ pour rester dans le périmètre officiellement supporté par BullMQ.

*Ce qui suit décrit l'état où Redis n'est PAS encore configuré — pertinent
pour tout autre environnement (production, préproduction) où cette activation
n'a pas encore été faite.*

- Sans Redis actif : `apps/api/.env` contient `QUEUE_DRIVER=memory` (forcé
  explicitement), ou aucun processus Redis n'écoute sur `localhost:6379`.
- **Conséquence concrète :** les notifications et les 5 jobs planifiés du §14
  (`expireMissions`, `autoCloseMissions`, `missionReminders`, `reviewReminders`,
  `cleanupTokens` — voir `apps/api/src/modules/jobs/scheduled-jobs.service.ts:16-22`)
  tournent sur de simples `setInterval` en mémoire de processus
  (`apps/api/src/common/queues/job-queue.ts:121-132`), et non sur un vrai worker
  BullMQ persistant.

### 1.2 Le risque précis

Un redémarrage de l'API (déploiement, crash, `pm2 restart`, arrêt du
conteneur…) **efface silencieusement** :
- toute notification restée en file d'attente non encore acheminée ;
- la planification des 5 jobs — ils ne repartent qu'au prochain démarrage
  d'`onModuleInit()`, et rien ne rattrape ce qui aurait dû se produire pendant
  l'arrêt.

Concrètement : une mission `pending_provider` qui aurait dû expirer pendant une
fenêtre de redémarrage de l'API ne le fera **jamais** tant que le job
`expireMissions` ne repasse pas — elle reste bloquée pour le client et le
prestataire jusqu'au prochain passage du minuteur, lui-même remis à zéro à
chaque redémarrage.

De plus, le motif cron n'est qu'**approximé** en mode mémoire
(`apps/api/src/common/queues/job-queue.ts:159`, fonction `intervalFromCron`) :
seule la forme `*/N * * * *` (toutes les N minutes) est reconnue précisément,
tout le reste retombe sur un intervalle d'une heure. C'est sans danger (le pire
cas est un job qui tourne plus souvent que prévu et ne trouve rien à faire),
mais ce n'est pas un vrai ordonnancement cron.

### 1.3 Comment activer

1. **Installer et lancer Redis**, accessible depuis le serveur qui exécute
   l'API (Redis managé, conteneur, ou instance dédiée — au choix de l'équipe
   ops).
2. Dans `apps/api/.env` (jamais dans `.env.example`, jamais commité) :
   ```
   REDIS_URL="redis://<hôte>:<port>"
   QUEUE_DRIVER=bullmq
   ```
   Sans `QUEUE_DRIVER` explicite, `resolveQueueDriver()`
   (`apps/api/src/common/queues/queue.factory.ts:26-30`) bascule déjà sur
   `bullmq` dès qu'une `REDIS_URL` est définie — le fixer explicitement rend
   l'intention lisible dans la configuration et évite toute ambiguïté.
3. Redémarrer l'API.

### 1.4 Comment vérifier que le passage a bien eu lieu

- **Dans les logs au démarrage**, chercher la ligne émise par
  `ScheduledJobsService.onModuleInit()`
  (`apps/api/src/modules/jobs/scheduled-jobs.service.ts:89`) :
  ```
  5 jobs planifiés (driver « bullmq »)
  ```
  Si Redis est injoignable, `createQueue()` l'attrape et journalise
  explicitement la bascule de secours
  (`apps/api/src/common/queues/queue.factory.ts:43-47`) :
  ```
  File « scheduled-jobs » : bascule en mémoire, Redis indisponible (...)
  ```
  Cette ligne dans les logs de production doit alerter : Redis est configuré
  mais pas joignable.
- **Déclenchement manuel d'un job**, pour confirmer que le circuit entier
  fonctionne sans attendre le cron :
  ```
  POST /api/v1/admin/jobs/expireMissions/run
  Authorization: Bearer <jeton avec la permission admin.settings.update>
  ```
  Réponse `200` avec un objet `result` (ex. `{ candidates: 0, expired: 0 }`) —
  voir `apps/api/src/modules/jobs/admin-jobs.controller.ts`.
- **Redémarrer l'API volontairement** après avoir mis une notification en
  file, et vérifier qu'elle est bien acheminée après le redémarrage (avec
  BullMQ) plutôt que perdue (comme en mode mémoire).
- **Test applicatif** existant à rejouer si besoin de non-régression :
  `apps/api/tests/integration/scheduled-jobs.integration.spec.ts` — ces tests
  tournent en mode `inline` (traitement immédiat, sans file), ils ne
  démontrent PAS le comportement BullMQ ; ils vérifient l'effet métier des
  jobs, pas la persistance de la file.

---

## 2. SMS (OTP) et Push (notifications)

### 2.1 État actuel

Le code des transports réels existe et fait de vrais appels HTTP (`fetch`) vers
les fournisseurs :

| Canal | Fournisseur(s) | Fichier |
|---|---|---|
| SMS | Termii | `apps/api/src/modules/notifications/sms.transport.ts:22-52` (`TermiiSmsProvider`) |
| SMS | Africa's Talking | `apps/api/src/modules/notifications/sms.transport.ts:55-99` (`AfricasTalkingSmsProvider`) |
| Push | Firebase Cloud Messaging | `apps/api/src/modules/notifications/push.transport.ts:51-149` (`FcmPushProvider`) |

Mais dans l'environnement actuel, **aucune des variables ci-dessous n'est
renseignée** dans `apps/api/.env`. Résultat :

- `buildSmsProvider()` (`apps/api/src/modules/notifications/transports.ts:119-146`)
  renvoie `null` dès que `SMS_PROVIDER` n'est pas reconnu ou que les clés
  associées manquent (retours explicites lignes 126, 135, 145) ;
- `buildPushProvider()` (`apps/api/src/modules/notifications/transports.ts:149-156`)
  renvoie `null` si `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL` ou `FCM_PRIVATE_KEY`
  manque (ligne 155) ;
- dans les deux cas, `buildTransports()` retombe alors sur `FileTransport`
  (`apps/api/src/modules/notifications/transports.ts:97-106`), qui écrit le
  message dans `storage/outbox/{sms,push}.log` au lieu de l'envoyer réellement.

**Ce n'est pas un simulacre silencieux** : chaque bascule sur le fichier est
journalisée explicitement au démarrage (`transports.ts:93,103` — 
`"Canal SMS : aucun fournisseur configuré, repli sur la boîte d'envoi fichier"`
et son équivalent pour le push), et le message écrit dans le journal est
horodaté et consultable. Mais concrètement : **aucun SMS ni push ne part
réellement vers un téléphone tant que ces variables ne sont pas renseignées.**

### 2.2 Variables à renseigner

Dans `apps/api/.env` (jamais dans `.env.example`) :

**SMS — choisir UN agrégateur :**
```
SMS_PROVIDER=termii
TERMII_API_KEY="<clé fournie par Termii>"
TERMII_SENDER_ID="PRESTGO"
```
ou
```
SMS_PROVIDER=africastalking
AT_API_KEY="<clé fournie par Africa's Talking>"
AT_USERNAME="<nom d'utilisateur du compte>"
AT_SENDER_ID="PRESTGO"
```

**Push — compte de service Firebase :**
```
FCM_PROJECT_ID="<project_id du fichier JSON du compte de service>"
FCM_CLIENT_EMAIL="<client_email du même fichier>"
FCM_PRIVATE_KEY="<private_key du même fichier, avec ses \n littéraux>"
```
Ces trois valeurs se trouvent dans le fichier JSON de compte de service
téléchargé depuis la console Firebase (Paramètres du projet → Comptes de
service → Générer une nouvelle clé privée). Aucune de ces valeurs ne doit
être commitée ni partagée hors d'un gestionnaire de secrets.

La liste complète des variables, avec leurs valeurs par défaut et exemples, est
documentée dans `apps/api/.env.example`.

### 2.3 Comment tester un vrai envoi

1. **SMS** : déclencher `POST /api/v1/auth/otp/send` avec un numéro de
   téléphone réel et joignable :
   ```
   POST /api/v1/auth/otp/send
   { "target": "+225XXXXXXXXX", "purpose": "phone_verification" }
   ```
   Si `SMS_PROVIDER` est correctement configuré, le SMS doit arriver sur le
   téléphone en quelques secondes. En cas d'échec, l'erreur du fournisseur est
   journalisée (`apps/api/src/modules/notifications/sms.transport.ts:108-114`)
   et le message part quand même dans le journal fichier de secours — vérifier
   `storage/outbox/sms.log` pour confirmer que la tentative a bien eu lieu et
   lire le motif de l'échec.

2. **Push** : enregistrer un vrai jeton d'appareil (obtenu côté application
   mobile via le SDK Firebase), puis déclencher une notification qui en
   dépend — par exemple accepter une mission (`POST /missions/:id/accept`),
   qui notifie l'autre partie via `NotificationEventsService`. Vérifier la
   réception sur l'appareil. En cas de jeton invalide, il est automatiquement
   désactivé côté serveur (`push.transport.ts` — `InvalidPushTokenError`,
   géré par le répartiteur) : ce n'est pas un signe d'échec de configuration,
   c'est le comportement attendu pour un jeton mort.

3. **Confirmation en base** : la table `Notification` porte un champ `status`
   (`queued` / `sent` / `failed`). Une fois `bullmq` actif (§1), interroger les
   notifications récentes du canal concerné pour confirmer qu'elles passent
   bien à `sent` et non `failed`.

---

## 3. Résumé pour la revue

| Brique | Code | Configuration active | Testé contre un vrai fournisseur |
|---|---|---|---|
| Redis / BullMQ | ✅ écrit et testé (mode `inline`) | ❌ `QUEUE_DRIVER=memory` actuellement | ❌ |
| SMS (Termii / Africa's Talking) | ✅ écrit | ❌ `SMS_PROVIDER` absent | ❌ |
| Push (FCM) | ✅ écrit | ❌ `FCM_*` absentes | ❌ |

Ces trois activations relèvent de la configuration d'exploitation (secrets,
comptes fournisseurs, infrastructure Redis) — **hors du périmètre d'une
intervention sur le code**.
