# Lot 5 — Fiabilité

**Date :** 19 juillet 2026
**Périmètre :** `apps/api`
**Origine :** audit de conformité au cahier des charges v1.2 (§10 Exigences non fonctionnelles)
**Prérequis :** Lots [0](Lot0-Securite-socle.md) · [1](Lot1-Fonctionnel-bloquant.md) · [2](Lot2-Ecrans-manquants.md) · [3](Lot3-API-complete.md) · [4](Lot4-Modele-de-donnees.md)

---

## 1. Pourquoi ce lot

Trois constats de l'audit restaient ouverts :

- **Les tests ne testaient rien.** 13 fichiers, 88 `it()`, **aucun n'appelait
  l'API**. Ils comparaient des littéraux déclarés deux lignes plus haut, et
  seraient passés au vert même si `src/` avait été supprimé.
- **Les notifications n'étaient jamais envoyées.** `send()` créait une ligne au
  statut `queued` et s'arrêtait là. Le statut ne changeait jamais, mais
  l'interface affichait la notification comme envoyée.
- **Redis et BullMQ étaient installés mais jamais importés.** Aucune file, aucun
  traitement asynchrone.

---

## 2. Des tests qui testent vraiment

### 2.1 Le harnais

`tests/helpers/test-app.ts` démarre **la vraie application NestJS** et
l'interroge en HTTP via supertest. Toute la chaîne est traversée : middleware de
corrélation, limiteur de débit, garde JWT, garde de permissions, pipe de
validation, filtre d'exception.

La configuration reproduit exactement `main.ts`. Si les deux divergeaient, les
tests vérifieraient une application différente de celle qui tourne réellement.

Une base **dédiée** (`prestgo_test`, déduite automatiquement de `DATABASE_URL`)
est préparée avant la première suite. La base de développement n'est jamais
touchée.

### 2.2 Deux obstacles rencontrés

**esbuild ne sait pas produire `emitDecoratorMetadata`.** C'est la métadonnée qui
permet à NestJS de deviner les types du constructeur pour l'injection de
dépendances. Sans elle, tout échoue sur `Cannot read properties of undefined`.
Le compilateur des tests est donc passé sur **SWC** (`unplugin-swc`), qui la
gère. C'est la configuration recommandée pour NestJS + Vitest.

**Les variables d'environnement de `globalSetup` n'atteignent pas les workers.**
Vitest isole les tests dans des threads séparés. Sans un `setupFiles` rejouant
la configuration dans chaque worker, l'application testée se serait connectée à
la base de développement.

### 2.3 Un choix assumé : pas de `--force-reset`

La solution évidente pour rendre les tests reproductibles était de vider la base
à chaque exécution. Elle a été écartée : **c'est une opération destructrice, et
elle n'a pas sa place dans une commande lancée aussi souvent que `pnpm test`**.
Un jour, une variable d'environnement mal placée la pointerait vers la mauvaise
base.

À la place, chaque test qui crée un compte utilise un identifiant unique dérivé
de l'horodatage (`uniqueEmail`, `uniquePhone`). Les tests ne dépendent donc pas
de l'état laissé par l'exécution précédente, et rien n'est jamais détruit.

### 2.4 Ce qui est couvert — 91 tests

| Suite | Tests | Contenu |
|---|---|---|
| `auth` | 16 | connexion, inscription, activation OTP, mot de passe oublié, jetons |
| `access-control` | 15 | permissions du back-office, appartenance aux missions, commentaire interne |
| `files` | 12 | envoi, verrouillage, contrôle d'accès, exports CSV |
| `validation` | 15 | corps de requête, paramètres d'URL, format des réponses |
| `public-api` | 9 | vitrine publique, filtrage « actif », recherche géographique |
| `notifications` | 7 | acheminement réel, échecs, modèles |
| `unit` (csv, geo, dto) | 17 | fonctions pures |

### 2.5 Preuve qu'ils détectent une régression

Un test qui passe ne prouve rien s'il ne peut pas échouer. Le contrôle
d'appartenance a donc été volontairement neutralisé (`if (false && …)`) :

```
× REFUSE un tiers connecté                              → expected 200 to be 403
× REFUSE à un tiers d'écrire dans la conversation       → expected 201 to be 403
× REFUSE à un tiers de lire la conversation             → expected 200 to be 403
× REFUSE à un tiers d'ouvrir un litige sur la mission…  → expected 201 to be 403
```

Quatre échecs immédiats, puis retour à 91/91 après restauration. **Les anciens
tests n'auraient rien vu.**

---

## 3. Notifications réellement acheminées

### 3.1 Une file d'attente qui fonctionne

Redis n'est pas disponible sur cet environnement (`127.0.0.1:6379` ne répond
pas). Plutôt que d'imposer son installation, une file **en mémoire** avec
nouvelles tentatives a été écrite (`common/queues/job-queue.ts`).

Elle est honnête sur ses limites : les traitements sont réels, mais la file vit
dans le processus. Un redémarrage perdrait ce qui restait à traiter — d'où la
reprise automatique décrite plus bas. C'est acceptable pour des notifications,
pas pour un paiement.

Le jour où Redis sera là, `QUEUE_DRIVER=bullmq` basculera sur une file
persistante sans changer le code appelant.

### 3.2 Des transports enfichables

| Canal | Transport actuel |
|---|---|
| `in_app` | l'enregistrement en base EST la livraison |
| `email` | journal fichier (`storage/outbox/email.log`) |
| `sms` | journal fichier (`storage/outbox/sms.log`) |

Le transport fichier n'est **pas un simulacre** : le message est réellement
produit, horodaté et conservé. On peut vérifier ce qui aurait été envoyé et à
qui. Cela évite surtout de faire croire qu'un envoi a eu lieu alors que rien ne
partait — ce qui était exactement le problème avant ce lot.

Brancher un vrai SMTP consistera à remplacer une ligne dans `buildTransports()`.

### 3.3 Le statut reflète enfin la réalité

`queued` → `sent` (avec `sentAt`) ou `failed` avec le motif. Vérifié sur ta base,
en conditions réelles :

```
POST /admin/notifications/send  → status: "queued"
   … 8 secondes plus tard …
GET  /admin/notifications       → status: "sent", sentAt: "2026-07-19T14:23:36Z"

storage/outbox/email.log :
{"at":"2026-07-19T14:23:36.106Z","channel":"email","to":"admin@prestgo.test",
 "title":"Test Lot 5","body":"Verification finale."}
```

Un cas d'échec est également géré : une notification SMS vers un compte sans
téléphone passe en `failed` au lieu de rester bloquée.

---

## 4. Entretien automatique

`MaintenanceService` tourne toutes les heures et couvre deux besoins jusqu'ici
sans réponse :

1. **Purge des secrets expirés.** Les jetons de réinitialisation et les codes OTP
   s'accumulaient sans que rien ne les supprime. Même hachés, garder
   indéfiniment des secrets périmés n'a aucun intérêt.
2. **Reprise des notifications en attente.** La file vivant en mémoire, un
   redémarrage laisserait sinon des notifications en `queued` pour toujours.

La tâche est désactivée en test (`QUEUE_DRIVER=inline`) : une tâche de fond
rendrait les résultats dépendants du moment où le minuteur se déclenche.

---

## 5. Deux correctifs au passage

**Limites de débit configurables.** Elles étaient écrites en dur. Les tests
s'auto-bloquaient (10 connexions/minute). Elles se pilotent désormais par
variables d'environnement, avec les valeurs de production par défaut.

**`pnpm start` était cassé.** Le script pointait vers `dist/main.js` alors que le
build produit `dist/src/main.js` (le dossier `tests/` étant inclus dans le
`tsconfig`). Signalé au Lot 0, corrigé ici — et vérifié : `pnpm start` démarre
les 96 routes et répond en HTTP 200.

---

## 6. Vérifications effectuées

`typecheck` API ✅ · `build` API ✅ · `typecheck` front ✅ · `build` front ✅
· `pnpm start` ✅ · **91 tests passent** ✅

| # | Scénario | Résultat |
|---|---|---|
| 1 | Suite complète | ✅ 9 fichiers, 91 tests |
| 2 | Neutralisation du contrôle d'accès | ✅ **4 tests virent au rouge** |
| 3 | Restauration | ✅ 91/91 |
| 4 | Notification asynchrone sur la base de dev | ✅ `queued` → `sent` en 8 s |
| 5 | Boîte d'envoi sur disque | ✅ message horodaté avec destinataire |
| 6 | Notification sans destinataire valide | ✅ `failed` |
| 7 | `pnpm start` | ✅ 96 routes, HTTP 200 |

---

## 7. À faire de ton côté

Rien. Les tests créent et gèrent leur propre base (`prestgo_test`).

Pour lancer les tests :

```bash
corepack pnpm --filter @prestgo/api test        # tout
corepack pnpm --filter @prestgo/api test:unit   # uniquement les tests unitaires (rapide, sans base)
corepack pnpm --filter @prestgo/api test:watch  # en continu pendant le développement
```

---

## 8. Ce qui reste ouvert

- **Redis / BullMQ** : le code est prêt à basculer, mais l'extension n'est pas
  installée. La file en mémoire ne survit pas à un redémarrage.
- **Envoi réel email / SMS** : aucun fournisseur n'est configuré. Les messages
  partent dans un journal fichier.
- **`sort`** : validé mais toujours pas appliqué (tris figés sur `createdAt desc`).
- **IP dans l'audit** : le champ existe, aucun appelant ne le renseigne.
- **Hashage** : scrypt sans paramètres de coût explicites, et le format stocké ne
  les contient pas — impossible de durcir plus tard sans invalider les mots de
  passe existants.
- **Migrations versionnées** : toujours `db push`, sans historique. **À reprendre
  avant toute mise en production.**
- **Tests du front** : aucun. Seule l'API est couverte.
- **Interfaces** des nouveautés du Lot 4 (preuves de litige, commentaire interne,
  indisponibilités) : l'API est prête, les écrans restent à faire.
