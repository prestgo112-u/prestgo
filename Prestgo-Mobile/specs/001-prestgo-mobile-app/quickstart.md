# Quickstart — Mise en route et validation

**Feature**: Application mobile PRESTGO (client + prestataire)
**Date**: 2026-07-30

Ce guide sert à **lancer** l'application et à **prouver** que chaque récit
utilisateur fonctionne de bout en bout. Il ne contient pas de code
d'implémentation : celui-ci relève de `tasks.md` et de la phase de réalisation.

---

## 1. Prérequis

| Élément | Version / valeur | Vérification |
|---|---|---|
| Flutter | 3.38.4 stable (Dart 3.10.3) | `flutter --version` |
| Android | SDK API 26 et plus, un émulateur ou un appareil | `flutter devices` |
| iOS *(optionnel sur Windows)* | Xcode, iOS 14 et plus | `flutter doctor` |
| Service PRESTGO | démarré et accessible, base de démonstration alimentée | `curl http://localhost:3000/api/v1/settings/public` |

### Démarrer le service

Le service vit dans un dépôt séparé (`prestgo-main`, monorepo pnpm). Sa base d'API
est `http://<hôte>:3000/api/v1` — le préfixe `api/v1` est posé globalement par
`app.setGlobalPrefix`, et le port par `API_PORT` (3000 par défaut).

```bash
cd <racine de prestgo-main>/apps/api
corepack pnpm db:migrate     # schéma
corepack pnpm db:seed        # comptes et données de démonstration
corepack pnpm dev            # écoute sur :3000
```

### Comptes de démonstration

Tous créés par `apps/api/prisma/seed.ts`, tous au statut `active`, **tous** avec le
mot de passe `prestgo123!`.

| Usage | Email | Particularité |
|---|---|---|
| Client | `client.demo@prestgo.test` | Awa Client ; une adresse par défaut, une mission de démonstration |
| Prestataire **réservable** | `provider.ready@prestgo.test` | `approved` + `available` ; c'est le seul sur lequel une réservation aboutit |
| Prestataire **en vérification** | `kofi.plombier@prestgo.test` | `pending_review`, 2 justificatifs déposés |
| Prestataire en vérification (2e) | `ama.electricite@prestgo.test` | `pending_review`, 1 justificatif |
| Super admin (back-office) | `admin@prestgo.test` | toutes les permissions — nécessaire pour **approuver** un dossier (US4, scénarios 4.7 à 4.9) |

Le seed est ré-exécutable : il complète ce qui manque sans rien dupliquer.

### Données posées par le seed

À connaître pour ne pas chercher : ces valeurs évitent de tâtonner sur les parcours
de réservation et de suivi.

| Élément | Valeur |
|---|---|
| Catalogue | catégorie « Plomberie » → type « Réparation de fuite » |
| Zone active | « Cocody » (Abidjan), 5.35 / −3.98, rayon 5 km |
| Adresse du client | « Domicile », Cocody, 5.35 / −3.98, **par défaut** |
| Formule de `provider.ready` | « Intervention express », **5 000 XOF**, 45 min |
| Agenda de `provider.ready` | **tous les jours 08:00–18:00** — aucun test ne devrait buter sur « pas de créneau » |
| Agenda de Kofi | lundi 09:00–12:00 seulement |
| Mission de démonstration | `confirmed`, 2026-08-03T14:00:00Z, client `client.demo` ↔ Kofi ; porte un fil de 2 messages, un avis `reported` et un litige `open` |
| Les six réglages publics | 60 min, 6 h, 120 min, 24 h, 7 j, 14 j — **identiques** aux valeurs de repli de `PublicSettings.fallback` |

⚠️ Les identifiants de ressources (prestataire, formule, zone) **changent à chaque
réinitialisation de la base** : les traiter comme des exemples de forme, jamais comme
des constantes de test. Les **emails**, eux, sont stables : c'est par eux qu'un test
retrouve une ressource.

### Deux pièges du jeu de démonstration

1. **La ligne « justificatifs » de Kofi et d'Ama reste rouge**, malgré leurs
   documents déposés. Le réglage `provider.required_document_types` vaut
   `["id_card"]`, alors que le seed dépose des documents de type `identity` et
   `insurance` ; or la checklist exige que **chaque** type requis soit présent. Le
   comportement de l'application est donc correct — c'est la donnée qui est
   incomplète. Pour tester une checklist complète (US4), déposer un justificatif de
   type `id_card`, ou ajuster le réglage au back-office.

2. **La mission de démonstration porte déjà un avis** de `client.demo`, et son
   statut est `confirmed`, pas `completed` : elle ne convient pas au dépôt d'avis
   (US9, scénarios 9.1 et 9.3). Créer une mission neuve sur `provider.ready` et la
   faire progresser jusqu'à `completed`.

---

## 2. Configuration d'environnement

Trois environnements portés par un fichier de définitions, injecté au lancement :

| Environnement | Base d'API | Particularités |
|---|---|---|
| `dev` (émulateur Android) | `http://10.0.2.2:3000/api/v1` | HTTP en clair autorisé, journaux réseau actifs, rapport d'incident désactivé |
| `dev` (simulateur iOS) | `http://localhost:3000/api/v1` | idem |
| `staging` | `https://<hôte-staging>/api/v1` | HTTPS strict |
| `prod` | `https://<hôte-prod>/api/v1` | HTTPS strict, journaux réseau désactivés |

⚠️ La base **contient déjà** `/api/v1` : aucun chemin d'appel ne le répète.

```bash
# Installation des dépendances et génération de code
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Lancement en développement
flutter run --dart-define-from-file=env/dev.json
```

---

## 3. Commandes de vérification

```bash
# Analyse statique (inclut les règles d'import inter-modules — porte G5)
flutter analyze

# Tests unitaires, de contrat et de widgets
flutter test

# Un seul niveau
flutter test test/contract
flutter test test/unit

# Parcours de bout en bout (appareil ou émulateur requis, service démarré)
flutter test integration_test --dart-define-from-file=env/dev.json
```

**Attendu avant toute revue** : `flutter analyze` sans avertissement,
`flutter test` au vert, et les tests de contrat rejouant les captures JSON réelles du
cahier des charges (`test/fixtures/`).

---

## 4. Scénarios de validation par récit utilisateur

Chaque scénario est **exécutable manuellement** et **automatisable** dans
`integration_test/flows/`. La colonne « Preuve » indique ce qui doit être constaté.

### US1 — Compte et session

| # | Étapes | Preuve |
|---|---|---|
| 1.1 | Inscription avec un email neuf + mot de passe conforme | Compte créé ; l'écran de code s'ouvre et un code part **sans action supplémentaire** |
| 1.2 | Saisir un code erroné 5 fois | Message unique « Code incorrect ou expiré » ; saisie désactivée après la 5e tentative |
| 1.3 | Renvoyer un code, puis saisir le bon | Compte activé, connexion automatique, arrivée sur l'espace client |
| 1.4 | Tenter la connexion **avant** vérification | Message générique + deux issues proposées (vérifier / support) |
| 1.5 | Fermer puis rouvrir l'application | Session restaurée, aucun écran de connexion |
| 1.6 | Attendre l'expiration du jeton d'accès (15 min) puis agir | Action réussie sans écran de connexion ; **un seul** appel de renouvellement dans les journaux, malgré des requêtes concurrentes |
| 1.7 | Connexion par téléphone (compte sans email) | Jetons émis sans mot de passe |
| 1.8 | Mot de passe oublié → collage du jeton → nouveau mot de passe | Toutes les sessions fermées, retour à la connexion |
| 1.9 | Déconnexion réseau coupé | Purge locale effectuée, retour à la connexion malgré l'échec des appels |
| 1.10 | Désactivation avec une mission confirmée | Refus avec le **message serveur tel quel** (nombre inclus) + raccourci vers les missions |

### US2 — Recherche et réservation *(chemin critique)*

| # | Étapes | Preuve |
|---|---|---|
| 2.1 | Ouvrir l'accueil **sans compte** | Résultats et fiches consultables, avatars affichés |
| 2.2 | Tri « distance » sans autoriser la position | Option indisponible avec explication (aucun appel refusé côté service) |
| 2.3 | Choisir une date sans heure | Envoi bloqué localement : les deux sont liés dans un même sélecteur |
| 2.4 | Appuyer sur « Réserver » sans compte | Passage par la connexion **puis retour sur la même fiche** |
| 2.5 | Cocher des options | Prix total et durée totale recalculés à l'écran, identiques au montant figé retourné après réservation |
| 2.6 | Choisir un horaire trop proche | Refus local, avec le délai **réellement en vigueur** (lu au démarrage) |
| 2.7 | Choisir un début dont la durée déborde du créneau | Créneau non proposable |
| 2.8 | Réserver avec une adresse hors zone | Message du service + proposition de changer d'adresse + zones couvertes affichées |
| 2.9 | Confirmer, couper le réseau pendant l'appel, laisser réessayer | **Une seule** mission créée ; le second appel renvoie « déjà enregistrée » |
| 2.10 | Modifier une option puis reconfirmer | Nouvelle clé d'idempotence émise (visible dans les journaux réseau) |

### US3 — Suivi client

| # | Étapes | Preuve |
|---|---|---|
| 3.1 | Ouvrir l'onglet « Terminées » | **Un seul** appel avec deux statuts ; total cohérent |
| 3.2 | Annuler une mission proche de l'horaire | Avertissement de tardiveté **avant** l'envoi, puis message du service affiché tel quel |
| 3.3 | Proposer un report, puis en proposer un second | Seconde action indisponible tant que la première est en attente |
| 3.4 | Ouvrir sa propre demande de report | Aucun bouton Accepter / Refuser |
| 3.5 | Accepter un report du prestataire sur un créneau devenu indisponible | Proposition de contre-proposition |

### US4 — Onboarding prestataire

| # | Étapes | Preuve |
|---|---|---|
| 4.1 | Créer un profil public sans présentation | Ligne « profil » rouge, libellé mentionnant nom public **et** présentation |
| 4.2 | Déclarer un service sans formule | Ligne « prestations » toujours rouge |
| 4.3 | Relancer la création de profil sur un compte qui en a déjà un | Traité comme un succès : arrivée sur le hub, pas d'erreur affichée |
| 4.4 | Vider entièrement la liste des zones | Confirmation explicite demandée |
| 4.5 | Saisir deux créneaux qui se chevauchent | Erreur signalée **avant** l'envoi |
| 4.6 | Déposer un justificatif de 12 Mo | Refus local avant tout appel réseau |
| 4.7 | Soumettre un dossier incomplet | Exactement les lignes désignées par le service passent en rouge |
| 4.8 | Modifier le nom public pendant la vérification | Champs en lecture seule ; l'interrupteur de disponibilité reste actif |
| 4.9 | Déposer un justificatif en « corrections demandées » | Dossier reparti en vérification, bouton « Re-soumettre » retiré |

### US5 — Journée du prestataire

| # | Étapes | Preuve |
|---|---|---|
| 5.1 | Ouvrir le tableau de bord, un bloc en erreur | Les autres blocs restent affichés |
| 5.2 | Ouvrir une demande non acceptée | « Accepter » et « Refuser » seuls — jamais « Annuler » |
| 5.3 | Tenter de démarrer trop tôt | Bouton indisponible + heure d'activation affichée |
| 5.4 | Refuser sans motif | Envoi bloqué |
| 5.5 | Accepter, couper le réseau juste après | Aucun rejeu automatique ; l'état réel est rechargé |
| 5.6 | Basculer sur « Occupé » | Explication affichée : toujours réservable |

### US6 — Messagerie

| # | Étapes | Preuve |
|---|---|---|
| 6.1 | Ouvrir un fil de plus de 20 messages | Les messages **récents** sont visibles d'emblée ; l'historique se charge en remontant |
| 6.2 | Quitter la conversation | Compteur du fil à zéro, pastille globale décrémentée |
| 6.3 | Envoyer un message réseau coupé | Bulle en échec + « Renvoyer » manuel, aucun doublon |
| 6.4 | Ouvrir un fil clôturé | Saisie masquée avec explication |

### US7 — Notifications

| # | Étapes | Preuve |
|---|---|---|
| 7.1 | Refuser l'autorisation | Tous les parcours restent disponibles |
| 7.2 | Injecter une charge utile `chat` (application au premier plan, en arrière-plan, tuée) | La bonne conversation s'ouvre dans les trois cas |
| 7.3 | Injecter un type inconnu | Ouverture du centre de notifications, aucun plantage |
| 7.4 | Se connecter avec un second compte sur le même appareil | Appareil réaffecté ; aucune notification de l'ancien compte |
| 7.5 | Se déconnecter | Désenregistrement effectué **avant** la fermeture de session |

### US8 — Offre du prestataire

| # | Étapes | Preuve |
|---|---|---|
| 8.1 | Modifier un prix | Mention que les missions déjà réservées gardent leur montant |
| 8.2 | Désactiver la dernière formule active | Avertissement de disparition des résultats de recherche |
| 8.3 | Ajouter une 21e réalisation | Action indisponible avec motif |
| 8.4 | Publier une photo de profil | Avertissement de visibilité publique |
| 8.5 | Ouvrir un justificatif validé | Re-dépôt indisponible |

### US9 — Avis

| # | Étapes | Preuve |
|---|---|---|
| 9.1 | Mission terminée, côté client | « Laisser un avis » avec temps restant |
| 9.2 | Même mission, côté prestataire | Aucune action de notation |
| 9.3 | Déposer un avis puis rouvrir le détail | Action retirée, avis consultable |
| 9.4 | Signaler deux fois le même avis | Mention « déjà signalé » |

### US10 — Réseau dégradé

| # | Étapes | Preuve |
|---|---|---|
| 10.1 | Charger les écrans clés, couper le réseau | Bannière permanente + date des données affichée |
| 10.2 | Tenter une écriture hors ligne | Action indisponible avec explication ; **rien** n'est mis en file |
| 10.3 | Rétablir le réseau | Rafraîchissement automatique de l'écran courant |
| 10.4 | Rouvrir un justificatif hors ligne | Contenu **non** restitué depuis le stockage local |

---

## 5. Vérifications transverses (à passer avant toute livraison)

| Contrôle | Attendu | Référence |
|---|---|---|
| Aucune lecture de `data` brut hors du socle | recherche de `['data']` limitée à `lib/core/api/` | porte G2 |
| Aucun test de code HTTP hors du socle | seuls les prédicats d'exception sont utilisés | porte G2 |
| Aucun seuil métier figé | les six réglages viennent du service, les constantes sont des replis | porte G3 |
| Aucun import croisé client ↔ prestataire | `flutter analyze` sans avertissement | porte G5 |
| Aucun jeton ni contenu sensible sur disque | inspection du stockage de l'appareil après usage | porte G6 |
| Changement de compte | aucune donnée du compte précédent visible | SC-012 |
| Identifiant de corrélation | présent sur 100 % des incidents remontés | SC-010 |

---

## 6. Dépannage courant

| Symptôme | Cause probable |
|---|---|
| Toutes les requêtes en échec réseau sur émulateur Android | base d'API en `localhost` au lieu de `10.0.2.2` |
| 404 sur toutes les routes | `/api/v1` ajouté deux fois (il est déjà dans la base) |
| Déconnexion au bout de 15 minutes | le nouveau jeton de renouvellement n'a pas remplacé l'ancien |
| Boucle de renouvellement puis 429 | l'appel de renouvellement passe par l'intercepteur d'authentification |
| Réservations en double | clé d'idempotence générée dans une méthode de construction de widget |
| Agenda décalé d'une heure | conversion de fuseau appliquée aux heures `HH:MM` |
| Créneau refusé côté service alors qu'il semble valide | date d'intervention envoyée en heure locale au lieu d'UTC |
| Corps vide sur un envoi de fichier | envoi passé par le rejeu automatique |
| Aucun prestataire dans les résultats de recherche | seul `provider.ready@prestgo.test` est `approved` : Kofi et Ama sont en `pending_review` et n'apparaissent pas |
| Ligne « justificatifs » rouge malgré des documents déposés | le type requis est `id_card`, le seed dépose `identity` et `insurance` (cf. §1) |
| « Laisser un avis » absent sur la mission de démonstration | elle est `confirmed`, pas `completed`, et porte déjà un avis (cf. §1) |
