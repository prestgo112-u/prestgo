# Guide de test utilisateur — PRESTGO Mobile

**Version** : 1.0 — 2026-08-01
**Périmètre** : test manuel de bout en bout de toutes les fonctionnalités et de tous les écrans de l'application mobile PRESTGO (surfaces client **et** prestataire).
**Références** : `specs/001-prestgo-mobile-app/spec.md`, `quickstart.md`, `contracts/navigation-routes.md`, `contracts/settings-and-limits.md`.

---

## 1. Mode d'emploi du guide

- Les tests sont regroupés par **module** (sections 5 à 18). Chaque cas porte un identifiant (ex. `AUTH-03`) à reporter dans vos fiches d'anomalie.
- Exécutez les modules **dans l'ordre** : chaque module s'appuie sur les données créées par les précédents (le compte créé en AUTH sert à la réservation, la réservation sert au suivi de mission, etc.).
- La colonne **Résultat** est à remplir : ✅ conforme, ❌ anomalie (ouvrir une fiche, section 20), ⏭ non testable (préciser pourquoi).
- Deux appareils (ou un appareil + un émulateur) sont recommandés pour les tests croisés client ↔ prestataire (missions, messagerie, notifications).

---

## 2. Préparation de l'environnement

### 2.1 Prérequis

| Élément | Valeur | Vérification |
|---|---|---|
| Flutter | 3.38.4 stable (Dart 3.10.3) | `flutter --version` |
| Android | SDK API 26+, émulateur ou appareil | `flutter devices` |
| iOS (optionnel) | Xcode, iOS 14+ | `flutter doctor` |
| Service PRESTGO | démarré, base de démonstration alimentée | `curl http://localhost:3000/api/v1/settings/public` |

### 2.2 Démarrer le service (dépôt `prestgo-main`)

```bash
cd <racine de prestgo-main>/apps/api
corepack pnpm db:migrate     # schéma
corepack pnpm db:seed        # comptes et données de démonstration
corepack pnpm dev            # écoute sur :3000
```

### 2.3 Lancer l'application

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run --dart-define-from-file=env/dev.json
```

⚠️ Sur **émulateur Android**, la base d'API doit être `http://10.0.2.2:3000/api/v1` (pas `localhost`). La base contient déjà `/api/v1` : si toutes les routes répondent 404, le préfixe est probablement doublé.

### 2.4 Outils utiles pendant les tests

- **Back-office / compte admin** : nécessaire pour approuver un dossier prestataire (module 10) et modérer un avis (module 15).
- **Boîte mail de test** : les codes de vérification et jetons de réinitialisation arrivent par email (en dev, consulter la sortie du service ou l'outil de capture d'emails du back-end).
- **Mode avion** de l'appareil : sert aux tests réseau (modules 8 et 17).

---

## 3. Comptes de test

### 3.1 Comptes fournis par le seed (mot de passe : `prestgo123!`)

| Rôle | Email | Particularités |
|---|---|---|
| Client | `client.demo@prestgo.test` | Awa Client ; 1 adresse par défaut (Cocody), 1 mission de démonstration |
| Prestataire **réservable** | `provider.ready@prestgo.test` | `approved` + `available` — **le seul** sur lequel une réservation aboutit |
| Prestataire en vérification | `kofi.plombier@prestgo.test` | `pending_review`, 2 justificatifs déposés |
| Prestataire en vérification (2ᵉ) | `ama.electricite@prestgo.test` | `pending_review`, 1 justificatif |
| Super admin (back-office) | `admin@prestgo.test` | approuve les dossiers, modère les avis |

### 3.2 Comptes à créer pendant les tests

| Usage | Données suggérées |
|---|---|
| Nouveau client (module 5) | Email `testeur.client@prestgo.test` — mot de passe `Test1234!` — prénom `Aya`, nom `Kouassi` |
| Compte téléphone seul (AUTH-08) | Téléphone `+225 07 08 09 10 11`, sans email ni mot de passe |
| Futur prestataire (module 10) | Email `testeur.presta@prestgo.test` — mot de passe `Test1234!` — prénom `Yao`, nom `Koné` |
| Second compte, même appareil (NOTIF-05) | Email `testeur.client2@prestgo.test` — mot de passe `Test1234!` |

### 3.3 Données de démonstration à connaître

| Élément | Valeur |
|---|---|
| Catalogue | catégorie « Plomberie » → type « Réparation de fuite » |
| Zone active | « Cocody » (Abidjan) — centre 5.35 / −3.98, rayon 5 km |
| Adresse du client demo | « Domicile », Cocody, 5.35 / −3.98, **par défaut** |
| Formule de `provider.ready` | « Intervention express », **5 000 XOF**, 45 min |
| Agenda de `provider.ready` | tous les jours **08:00–18:00** |
| Agenda de Kofi | lundi 09:00–12:00 uniquement |
| Mission de démonstration | `confirmed`, 2026-08-03 14:00 UTC, `client.demo` ↔ Kofi ; porte un fil de 2 messages, un avis signalé et un litige ouvert |
| Réglages publics | délai mini de réservation **60 min**, préavis d'annulation **6 h**, fenêtre de démarrage **120 min**, expiration d'une demande **24 h**, clôture auto **7 j**, fenêtre d'avis **14 j** |

⚠️ **Deux pièges du jeu de démonstration** :
1. La ligne « justificatifs » de Kofi et d'Ama **reste rouge** : le type requis est `id_card`, le seed dépose `identity` et `insurance`. C'est la donnée qui est incomplète, pas un bug. Pour une checklist verte, déposer un justificatif de type `id_card`.
2. La mission de démonstration ne convient **pas** au test de dépôt d'avis : elle est `confirmed` (pas `completed`) et porte déjà un avis. Créer une mission neuve sur `provider.ready` et la mener jusqu'à `completed` (modules 7 et 11).

### 3.4 Jeu de données de saisie

| Donnée | Valeur valide | Valeurs invalides (à tester) |
|---|---|---|
| Mot de passe | `Test1234!` | `abc1` (trop court), `motdepasse` (aucun chiffre), `12345678` (aucune lettre) |
| Téléphone | `+225 07 08 09 10 11` | `1234` (trop court), `abcdefgh` (lettres) |
| Code de vérification | le code reçu (6 chiffres) | `000000` (faux), `12345` (5 chiffres — envoi impossible) |
| Adresse **en zone** | « Domicile Cocody » — Cocody, position 5.3500 / −3.9800 | — |
| Adresse **hors zone** | « Bureau Yopougon » — Yopougon, position 5.3360 / −4.0890 (~12 km du centre de la zone) | — |
| Instructions de réservation | « Portail bleu, sonner 2 fois. Le compteur d'eau est dans la cour. » | texte de **501** caractères (plafond : 500) |
| Motif (refus / annulation) | « Empêchement personnel » | « ok » (moins de 3 caractères) |
| Note d'avis | 5 — commentaire « Travail soigné, prestataire ponctuel. Je recommande. » | commentaire de **1001** caractères (plafond : 1000) |
| Message | « Bonjour, l'accès se fait par l'arrière du bâtiment. » | message vide ; texte de **4001** caractères (plafond : 4000) |
| Fichiers | photo JPEG < 10 Mo ; document PDF < 10 Mo | fichier de **12 Mo** (plafond : 10 Mo) ; archive `.zip` (type non accepté) |
| Nom public prestataire | « Yao Dépannage Plomberie » | « Y » (moins de 2 caractères) |
| Présentation (bio) | « Plombier depuis 8 ans à Abidjan, spécialisé dans la détection et la réparation de fuites. » | texte de **2001** caractères (plafond : 2000) |
| Service | titre « Réparation de fuite d'eau », type « Réparation de fuite » | titre « ab » (moins de 3 caractères) |
| Formule | « Diagnostic complet » — 10 000 XOF — 90 min | durée 3 min (minimum : 5) |
| Option | « Détartrage chauffe-eau » — +2 000 XOF — +15 min | — |
| Créneau hebdomadaire | lundi 09:00 → 12:00 | lundi 15:00 → 14:00 (fin avant début) ; lundi 09:00–12:00 **et** lundi 11:00–14:00 (chevauchement) |
| Absence | du 2026-08-10 au 2026-08-12, motif « Congés » | du 2026-08-12 au 2026-08-10 (fin avant début) |

**Dates de réservation** (le jour J est la date d'exécution du test) :
- Créneau **valide** : J+2 à 10:00 (dans l'agenda 08:00–18:00, au-delà du délai de 60 min).
- Créneau **trop proche** : aujourd'hui à J+30 minutes (sous le délai de 60 min → refus local).
- Créneau **débordant** : J+2 à 17:30 avec une prestation de 45 min (17:30 + 45 min > 18:00 → non proposable).
- Mission pour test d'**annulation tardive** : aujourd'hui à J+2 heures (sous le préavis de 6 h).

---

## 4. Inventaire des écrans à couvrir

Cochez chaque écran une fois vu **avec ses trois états** quand ils existent : chargement, contenu, erreur/vide.

### Écrans publics
- [ ] `/` Accueil / recherche (sans compte)
- [ ] `/search` Résultats et filtres
- [ ] `/providers/:id` Fiche prestataire publique
- [ ] `/providers/:id/reviews` Tous les avis (paginé)
- [ ] `/login` Connexion (email ou téléphone)
- [ ] `/login/phone` Connexion par code
- [ ] `/register` Inscription (canal → identité → mot de passe)
- [ ] `/verify` Saisie du code à 6 chiffres
- [ ] `/forgot-password` Demande de réinitialisation
- [ ] `/reset-password` Saisie / collage du jeton + nouveau mot de passe

### Espace client
- [ ] `/home` Accueil connecté
- [ ] `/booking/new` Brouillon de réservation (formule, options)
- [ ] `/booking/schedule` Choix de la date et de l'heure
- [ ] `/booking/summary` Récapitulatif et confirmation
- [ ] `/missions` Mes missions (onglets à venir / en cours / terminées / annulées)
- [ ] `/missions/:id` Détail de mission
- [ ] `/missions/:id?tab=reschedule` Détail — onglet Reports
- [ ] `/missions/:id?tab=review` Détail — dépôt d'avis
- [ ] `/missions/:id/history` Frise chronologique
- [ ] `/missions/:id/dispute` Ouverture de litige
- [ ] `/favorites` Mes favoris
- [ ] `/reviews` Mes avis

### Commun aux deux rôles
- [ ] `/threads` Messagerie (liste des conversations)
- [ ] `/threads/:id` Conversation
- [ ] `/notifications` Centre de notifications
- [ ] `/profile` Mon profil
- [ ] `/profile/edit` Édition du profil
- [ ] `/profile/password` Changer mon mot de passe
- [ ] `/profile/addresses` Carnet d'adresses
- [ ] `/profile/addresses/new` et `/profile/addresses/:id` Adresse + sélecteur de position
- [ ] `/profile/devices` Appareils connectés
- [ ] `/profile/deactivate` Désactivation du compte

### Onboarding prestataire
- [ ] `/provider/onboarding` Présentation du parcours
- [ ] `/provider/onboarding/profile` Création du profil public
- [ ] `/provider/onboarding/checklist` Hub de complétude (5 lignes)
- [ ] `/provider/onboarding/status` Suivi du dossier

### Espace prestataire
- [ ] `/provider` Tableau de bord
- [ ] `/provider/missions` Planning et demandes
- [ ] `/provider/profile` Profil prestataire et disponibilité
- [ ] `/provider/services` Mes prestations (formules et options)
- [ ] `/provider/zones` Zones d'intervention
- [ ] `/provider/availabilities` Agenda hebdomadaire
- [ ] `/provider/unavailabilities` Absences exceptionnelles
- [ ] `/provider/documents` Justificatifs
- [ ] `/provider/portfolio` Réalisations

---

## 5. Module AUTH — Inscription, connexion, session

**Écrans** : `/register`, `/verify`, `/login`, `/login/phone`, `/forgot-password`, `/reset-password`.

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| AUTH-01 | Inscription avec un email neuf et un mot de passe conforme | `testeur.client@prestgo.test` / `Test1234!` / Aya Kouassi | Compte créé non activé ; arrivée sur l'écran de code ; un code part **sans action supplémentaire** ; compte à rebours affiché | |
| AUTH-02 | Sur `/register`, essayer les mots de passe invalides | `abc1`, `motdepasse`, `12345678` | Erreur signalée **avant l'envoi**, sous le champ concerné | |
| AUTH-03 | Saisir un code faux 5 fois | `000000` | Message unique « Code incorrect ou expiré » à chaque échec ; champ vidé ; après le 5ᵉ échec la saisie est **désactivée**, seul « Renvoyer un code » reste actif | |
| AUTH-04 | Renvoyer un code, puis saisir le bon | code reçu | Compte activé, connexion automatique, arrivée sur l'espace client | |
| AUTH-05 | Demander deux renvois de code en moins d'une minute | — | Le second renvoi est indisponible (au plus un renvoi par minute) | |
| AUTH-06 | Se déconnecter, tenter la connexion avec un mot de passe erroné | `testeur.client@prestgo.test` / `Faux9999!` | Message unique « Email ou mot de passe incorrect », sans indiquer si l'adresse existe | |
| AUTH-07 | Créer un compte, puis tenter la connexion **avant** vérification | second email neuf | Message générique + deux issues : relancer la vérification, contacter le support | |
| AUTH-08 | Inscription puis connexion par **téléphone seul** via `/login/phone` | `+225 07 08 09 10 11` | Code envoyé au téléphone ; saisie correcte → session de plein droit, sans mot de passe | |
| AUTH-09 | Fermer complètement l'application, la rouvrir | — | Session restaurée, aucun écran de connexion, arrivée directe sur l'espace habituel | |
| AUTH-10 | Laisser l'application inactive plus de 15 min, puis déclencher une action | — | L'action aboutit sans écran de connexion (renouvellement silencieux) | |
| AUTH-11 | `/forgot-password` avec un email existant puis avec un email inconnu | `testeur.client@prestgo.test`, puis `inconnu@prestgo.test` | **Le même message neutre** dans les deux cas | |
| AUTH-12 | Coller le jeton reçu sur `/reset-password`, choisir un nouveau mot de passe | jeton reçu par email / `Test5678!` | Succès ; toutes les sessions fermées ; retour à la connexion ; l'ancien mot de passe ne fonctionne plus | |
| AUTH-13 | Se déconnecter en **mode avion** | — | La déconnexion aboutit quand même : purge locale, retour à `/login` | |

---

## 6. Module PROF — Profil, adresses, favoris

**Écrans** : `/profile`, `/profile/edit`, `/profile/password`, `/profile/addresses`, `/profile/addresses/new`, `/profile/devices`, `/profile/deactivate`.
**Précondition** : connecté avec `testeur.client@prestgo.test`.

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| PROF-01 | Ouvrir `/profile` | — | Identité, contacts (avec mention « non vérifié » le cas échéant), ancienneté du compte | |
| PROF-02 | Modifier prénom/nom dans `/profile/edit` | `Aya-Marie` / `Kouassi` | Enregistré et visible immédiatement au retour sur `/profile` | |
| PROF-03 | Modifier l'email du compte | `testeur.client+new@prestgo.test` | Le contact repasse « non vérifié » ; un code part automatiquement ; l'application **enchaîne** sur `/verify` ciblant l'email | |
| PROF-04 | Changer le mot de passe depuis `/profile/password` | actuel `Test5678!` → nouveau `Test9012!` | La session **courante survit** ; le nombre de sessions fermées renvoyé par le service est affiché tel quel | |
| PROF-05 | Créer une adresse avec le sélecteur de position | « Domicile Cocody », Cocody, 5.3500 / −3.9800, **par défaut** | Position obligatoire (impossible de valider sans) ; adresse créée et marquée par défaut | |
| PROF-06 | Créer une seconde adresse | « Bureau Yopougon », Yopougon, 5.3360 / −4.0890 | Créée, non par défaut ; le carnet en liste deux | |
| PROF-07 | Créer des adresses jusqu'au plafond de 10 | libellés « Adresse 3 » … « Adresse 10 » | À 10 adresses, le bouton d'ajout devient **indisponible avec le motif affiché** — jamais un échec après saisie | |
| PROF-08 | Supprimer une adresse non utilisée, puis tenter d'en supprimer une utilisée par une mission passée (compte `client.demo`) | — | La première disparaît du carnet ; la seconde est retirée du carnet **sans** effacer l'historique, ou le motif renvoyé est affiché | |
| PROF-09 | Ajouter `provider.ready` aux favoris depuis sa fiche, puis le retirer | — | Ajout et retrait **immédiats** à l'écran ; `/favorites` reflète l'état | |
| PROF-10 | Rendre le prestataire favori indisponible (via son compte), puis rouvrir `/favorites` | — | Le favori reste listé mais **grisé, non réservable** | |
| PROF-11 | Ouvrir `/profile/devices` | — | L'appareil courant est listé, reconnaissable (nom, modèle) | |
| PROF-12 | Ouvrir `/profile/deactivate` avec le compte `client.demo` (qui a une mission confirmée) | mot de passe `prestgo123!` | Double confirmation + mot de passe exigés ; vocabulaire « Désactiver » (jamais « Supprimer ») ; refus avec le **message du service tel quel** (nombre inclus) + raccourci vers les missions | |

---

## 7. Module RECH — Recherche et fiche prestataire (sans compte puis connecté)

**Écrans** : `/`, `/search`, `/providers/:id`, `/providers/:id/reviews`.
**Précondition** : commencer **déconnecté**.

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| RECH-01 | Ouvrir l'accueil sans compte, lancer une recherche | catégorie « Plomberie » | Résultats consultables sans connexion, photos de profil affichées | |
| RECH-02 | Ouvrir la fiche de `provider.ready` | — | Fiche complète en **un seul chargement** : présentation, prestations + formules + options, agenda et absences à venir, zones, réalisations, répartition des notes, derniers avis | |
| RECH-03 | Vérifier l'affichage d'un prestataire sans avis | — | Badge « Nouveau » plutôt qu'une note à 0 | |
| RECH-04 | Trier par distance **sans** avoir autorisé la position | — | Option indisponible avec explication — aucun appel réseau refusé | |
| RECH-05 | Autoriser la position, filtrer par rayon | rayon 10 km (défaut), puis 1 km, puis 50 km | Le rayon est borné 1–50 km ; les distances s'affichent sur les résultats | |
| RECH-06 | Filtrer par créneau : choisir une date sans heure | J+2, sans heure | Blocage local : date et heure sont **indissociables** dans le sélecteur | |
| RECH-07 | Filtrer par note minimale et mot-clé | note ≥ 4, mot-clé « fuite » | Résultats cohérents ; `provider.ready` apparaît | |
| RECH-08 | Chercher avec des filtres qui ne donnent rien | mot-clé « xyzxyz » | État vide avec actions utiles : élargir le rayon (jusqu'au max) ou retirer les filtres | |
| RECH-09 | Faire défiler une liste de résultats longue | — | Pagination en défilement continu, sans doublon ni saut | |
| RECH-10 | Ouvrir `/providers/:id/reviews` | fiche de `provider.ready` | Liste complète des avis, paginée, chargée à part de la fiche | |
| RECH-11 | Vérifier que Kofi et Ama n'apparaissent **pas** dans les résultats | — | Seuls les prestataires `approved` sont listés (`provider.ready` uniquement avec le seed) | |
| RECH-12 | Appuyer sur « Réserver » **sans être connecté** | — | Passage par `/login`, puis **retour automatique sur la même fiche** | |

---

## 8. Module RESA — Réservation

**Écrans** : `/booking/new`, `/booking/schedule`, `/booking/summary`.
**Précondition** : connecté avec `testeur.client@prestgo.test`, adresses PROF-05 et PROF-06 créées. Réserver chez `provider.ready` (formule « Intervention express », 5 000 XOF, 45 min).

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| RESA-01 | Lancer une réservation avec un compte au **carnet d'adresses vide** (compte neuf) | — | Invitation à créer d'abord une adresse géolocalisée | |
| RESA-02 | Choisir la formule, cocher puis décocher des options | options du catalogue | **Prix total et durée totale recalculés immédiatement** à chaque coche, en XOF sans décimale | |
| RESA-03 | Ouvrir le sélecteur de date/heure | — | Seuls les créneaux de l'agenda (08:00–18:00), hors absences, où la durée totale **tient entièrement**, sont proposables | |
| RESA-04 | Tenter un horaire trop proche | aujourd'hui + 30 min | Refus **local** avant envoi, avec le délai réellement en vigueur (60 min) affiché | |
| RESA-05 | Tenter un début en fin de créneau | J+2 à 17:30 (durée 45 min) | Créneau non proposable (17:30 + 45 min dépasse 18:00) | |
| RESA-06 | Saisir des instructions | texte valide, puis texte de 501 caractères | Le texte valide passe ; au-delà de 500 caractères la saisie est bloquée/refusée avant envoi | |
| RESA-07 | Choisir l'adresse **hors zone** et confirmer | « Bureau Yopougon » | Refus avec le message du service, proposition de changer d'adresse, zones couvertes affichées ; le **reste du brouillon est conservé** | |
| RESA-08 | Reprendre avec l'adresse en zone et confirmer | « Domicile Cocody », J+2 10:00 | Réservation créée ; récapitulatif conforme (formule, options, montant, durée, adresse) ; mission visible dans « Mes missions » → À venir | |
| RESA-09 | Confirmer une réservation puis couper le réseau **pendant** l'appel, laisser réessayer | mode avion au moment de la confirmation | **Une seule** mission créée — jamais de doublon (clé d'idempotence) | |
| RESA-10 | Recomposer un brouillon, modifier une option, reconfirmer | — | Nouvelle réservation distincte ; aucun conflit avec la précédente | |
| RESA-11 | Sur deux appareils, viser le même créneau ; confirmer sur l'un, puis sur l'autre | même créneau J+2 | Sur le second : « Ce créneau vient d'être pris », le sélecteur se rouvre en conservant le reste du brouillon | |
| RESA-12 | Depuis le compte prestataire, tenter de réserver **sa propre** prestation | `provider.ready` | Bloqué côté application avant l'envoi | |

---

## 9. Module MISS — Suivi des missions côté client

**Écrans** : `/missions` (4 onglets), `/missions/:id`, `?tab=reschedule`, `/missions/:id/history`.
**Précondition** : missions créées en RESA-08/RESA-10 ; compte `client.demo` pour les états riches.

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| MISS-01 | Parcourir les 4 onglets | — | À venir / En cours / Terminées / Annulées ; « Terminées » regroupe terminées **et** clôturées en un seul chargement, total correct, plus récent en premier | |
| MISS-02 | Ouvrir le détail d'une mission | mission RESA-08 | État, horaire, formule + options, **montant figé**, adresse, instructions, lien conversation, frise des évènements ; **aucune coordonnée personnelle** du prestataire (mise en relation via messagerie uniquement) | |
| MISS-03 | Ouvrir `/missions/:id/history` | — | Frise chronologique des changements d'état | |
| MISS-04 | Annuler une mission **loin** de l'horaire | mission RESA-10, motif « Empêchement personnel » | Motif exigé (≥ 3 caractères) ; message du service affiché tel quel ; listes, détail et compteurs rafraîchis | |
| MISS-05 | Créer une mission à J+2 h puis l'annuler | préavis en vigueur : 6 h | Avertissement **avant l'envoi** que l'annulation sera enregistrée comme tardive, avec possibilité de renoncer | |
| MISS-06 | Tenter une annulation avec un motif trop court | « ok » | Envoi bloqué localement | |
| MISS-07 | Proposer un report | mission à venir, nouvelle date J+3 10:00, motif | Demande créée, visible dans l'onglet Reports du détail | |
| MISS-08 | Proposer un **second** report sur la même mission | — | Action indisponible tant que la première demande est en attente, avec explication | |
| MISS-09 | Ouvrir sa **propre** demande de report | — | Aucun bouton « Accepter » / « Refuser » sur sa propre demande | |
| MISS-10 | Depuis le compte prestataire, proposer un report ; côté client, l'accepter | — | Mission déplacée à la nouvelle date ; si le créneau n'est plus disponible, l'application propose une **contre-proposition** | |
| MISS-11 | Depuis le compte prestataire, proposer un report ; côté client, le refuser | motif « Indisponible à cette date » | Motif exigé ; la mission garde sa date d'origine | |

---

## 10. Module ONB — Devenir prestataire (onboarding)

**Écrans** : `/provider/onboarding`, `/provider/onboarding/profile`, `/provider/onboarding/checklist`, `/provider/onboarding/status`.
**Précondition** : compte `testeur.presta@prestgo.test` créé et activé (module 5), **sans** profil prestataire.

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| ONB-01 | Ouvrir « Devenir prestataire » et créer le profil public **sans présentation** | nom public « Yao Dépannage Plomberie » | Arrivée sur le hub de complétude à **5 lignes** (profil, prestations, zones, disponibilités, justificatifs) ; ligne « profil » **rouge**, libellé exigeant explicitement nom public **et** présentation | |
| ONB-02 | Compléter la présentation | bio du §3.4, années d'expérience 8 | Ligne « profil » passe au vert | |
| ONB-03 | Relancer la création de profil (retour arrière puis re-validation) | — | Traité comme un succès : retour au hub, **aucun doublon**, aucune erreur affichée | |
| ONB-04 | Déclarer un service **sans formule** | « Réparation de fuite d'eau », type « Réparation de fuite » | Ligne « prestations » reste rouge : une **formule active** est exigée | |
| ONB-05 | Ajouter une formule au service | « Diagnostic complet », 10 000 XOF, 90 min | Ligne « prestations » au vert | |
| ONB-06 | Cocher des zones d'intervention | « Cocody » | Ligne « zones » au vert ; liste à cocher remplacée en bloc | |
| ONB-07 | Vider entièrement la liste des zones | — | **Confirmation explicite** demandée, mentionnant la disparition des résultats de recherche ; re-cocher « Cocody » ensuite | |
| ONB-08 | Saisir l'agenda : créneaux qui se chevauchent | lundi 09:00–12:00 + lundi 11:00–14:00 | Erreur signalée **avant l'envoi** | |
| ONB-09 | Saisir un créneau dont la fin précède le début | lundi 15:00 → 14:00 | Erreur signalée avant l'envoi | |
| ONB-10 | Saisir un agenda valide | lundi à samedi 08:00–17:00 | Ligne « disponibilités » au vert ; dimanche affiché comme **premier jour** de la grille | |
| ONB-11 | Déposer un justificatif de 12 Mo | fichier 12 Mo | Refus **local** avant tout appel réseau (plafond 10 Mo) | |
| ONB-12 | Déposer un justificatif d'un type non accepté | archive `.zip` | Refus local (types acceptés : JPEG, PNG, WebP, PDF, texte, CSV) | |
| ONB-13 | Déposer le justificatif requis | PDF ou JPEG < 10 Mo pour le type exigé (`id_card`) | Ligne « justificatifs » au vert ; état « en examen » visible avec la version | |
| ONB-14 | Soumettre le dossier (5 lignes vertes) | — | Passage en vérification ; `/provider/onboarding/status` affiche la **date de soumission** | |
| ONB-15 | Pendant la vérification, tenter de modifier le nom public | — | Champs d'identité en **lecture seule** ; seul l'interrupteur de disponibilité reste actionnable | |
| ONB-16 | Au back-office (admin), demander des corrections ; côté app, déposer un nouveau justificatif | compte `admin@prestgo.test` | L'application signale que le dossier est **reparti en vérification** et ne propose plus « Re-soumettre » | |
| ONB-17 | Au back-office, **approuver** le dossier ; rouvrir l'application | — | Atterrissage sur l'espace prestataire complet (`/provider`) | |
| ONB-18 | Vérifier la reprise de parcours : se déconnecter/reconnecter en cours d'onboarding | avant ONB-14 | Retour direct sur le hub de complétude, état conservé, aucun doublon créé | |

---

## 11. Module PRES — Journée du prestataire (tableau de bord et missions)

**Écrans** : `/provider`, `/provider/missions`.
**Précondition** : compte prestataire approuvé (`provider.ready@prestgo.test` ou `testeur.presta` après ONB-17). Créer une demande depuis le compte client (`testeur.client`) au préalable.

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| PRES-01 | Ouvrir le tableau de bord | — | Blocs indépendants : demandes en attente, missions du jour, compteurs non lus, interrupteur de disponibilité ; l'échec d'un bloc n'empêche pas les autres | |
| PRES-02 | Consulter la liste des demandes en attente | demande créée côté client | **Temps restant avant expiration** automatique affiché (24 h) | |
| PRES-03 | Ouvrir le détail d'une demande non acceptée | — | Seuls « Accepter » et « Refuser » — jamais « Annuler » | |
| PRES-04 | Refuser une demande **sans motif** puis avec un motif court | vide, puis « ok » | Envoi bloqué : motif d'au moins 3 caractères exigé | |
| PRES-05 | Accepter une demande | — | Mission confirmée ; compteurs et listes rafraîchis ; le client la voit passer « À venir » confirmée | |
| PRES-06 | Sur la mission acceptée, tenter de démarrer **trop tôt** | mission à plus de 120 min | « Démarrer » **indisponible**, avec l'heure à partir de laquelle il sera actionnable | |
| PRES-07 | Démarrer dans la fenêtre autorisée, puis terminer | mission à moins de 120 min du début | Transitions démarrée → terminée ; états reflétés côté client ; frise mise à jour | |
| PRES-08 | Annuler une mission acceptée | motif « Panne de véhicule » | Motif exigé ; mission annulée des deux côtés | |
| PRES-09 | Accepter une demande et couper le réseau **juste après** l'envoi | mode avion | **Aucun rejeu automatique** : au retour du réseau, l'application rafraîchit l'état réel et laisse décider | |
| PRES-10 | Vérifier l'ordre de la liste des missions | plusieurs missions | Ordre **chronologique croissant** (ce qui arrive d'abord en premier) | |
| PRES-11 | Basculer l'interrupteur sur « Occupé » puis « Indisponible » | — | Différence explicitée : « Occupé » = toujours réservable ; « Indisponible » = retiré de la recherche, plus aucune réservation ; vérifier côté client que la recherche reflète « Indisponible » | |
| PRES-12 | Laisser une demande sans réponse au-delà du délai (ou ajuster au back-office) | 24 h | La demande passe **expirée** sans action ; aucune action proposée sur cet état terminal | |
| PRES-13 | Basculer de l'espace prestataire vers l'espace client et revenir | entrée de menu | Bascule **sans reconnexion** ; jamais les deux espaces affichés en même temps | |

---

## 12. Module OFFRE — Gérer son offre dans la durée

**Écrans** : `/provider/profile`, `/provider/services`, `/provider/zones`, `/provider/availabilities`, `/provider/unavailabilities`, `/provider/documents`, `/provider/portfolio`.
**Précondition** : prestataire approuvé.

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| OFFRE-01 | Modifier le prix d'une formule | « Diagnostic complet » : 10 000 → 12 000 XOF | Mention explicite que **les missions déjà réservées conservent leur montant** | |
| OFFRE-02 | Ajouter une option à une formule | « Détartrage chauffe-eau », +2 000 XOF, +15 min | Option visible sur la fiche publique et dans le parcours de réservation | |
| OFFRE-03 | Retirer une formule | — | Vocabulaire « **Désactiver** » (jamais « Supprimer ») | |
| OFFRE-04 | Désactiver la **dernière** formule active | — | Avertissement : disparition des résultats de recherche ; vérifier côté client que le prestataire n'apparaît plus ; réactiver ensuite | |
| OFFRE-05 | Publier une photo de profil | JPEG < 10 Mo | Avertissement : la photo devient **visible par tous les visiteurs** | |
| OFFRE-06 | Ajouter des réalisations au portfolio | images JPEG/PNG, titres « Chantier Cocody 1 » … | Images uniquement (un PDF est refusé) ; réordonnancement possible ; l'ordre est reflété sur la fiche publique | |
| OFFRE-07 | Remplir le portfolio jusqu'à 20, puis tenter la 21ᵉ | — | Action d'ajout **indisponible avec le motif** affiché | |
| OFFRE-08 | Ajouter une absence | 2026-08-10 → 2026-08-12, « Congés » | Créée ; les créneaux correspondants disparaissent du sélecteur de réservation côté client | |
| OFFRE-09 | Saisir une absence dont la fin précède le début | 2026-08-12 → 2026-08-10 | Erreur signalée avant l'envoi | |
| OFFRE-10 | Modifier l'agenda hebdomadaire | ajouter dimanche 09:00–12:00 | Grille 7 jours, **dimanche en premier** ; heures affichées telles que saisies (aucun décalage de fuseau) | |
| OFFRE-11 | Ouvrir un justificatif **validé** | après validation au back-office | Re-dépôt **indisponible** | |
| OFFRE-12 | Ouvrir un justificatif **refusé** | refuser une version au back-office | Motif de refus affiché + nouveau dépôt proposé ; historique des versions consultable | |
| OFFRE-13 | Modifier les zones (ajout/retrait) | cocher une 2ᵉ zone si disponible | Remplacement en bloc, plafond 15, pas de doublon | |

---

## 13. Module MSG — Messagerie

**Écrans** : `/threads`, `/threads/:id`.
**Précondition** : une mission active entre `testeur.client` et le prestataire (deux appareils recommandés).

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| MSG-01 | Ouvrir l'onglet Messagerie | — | Chaque fil : interlocuteur, dernier message, nombre de non-lus ; la pastille de l'onglet reflète le **total global** | |
| MSG-02 | Ouvrir la conversation depuis le **détail de la mission** et depuis l'onglet | — | Les deux chemins mènent au même fil | |
| MSG-03 | Envoyer un message texte | « Bonjour, l'accès se fait par l'arrière du bâtiment. » | Affichage optimiste immédiat, puis état envoyé ; reçu sur l'autre appareil | |
| MSG-04 | Envoyer un message avec pièces jointes | 1 photo JPEG + 1 PDF | Pièces envoyées **avant** le message ; visibles des deux côtés | |
| MSG-05 | Tenter 4 pièces jointes | 4 fichiers | Bloqué : 3 pièces jointes au maximum, motif affiché | |
| MSG-06 | Tenter un message vide, puis un message de 4001 caractères | — | Les deux sont bloqués avant envoi (bornes 1–4000) | |
| MSG-07 | Envoyer un message en **mode avion** | — | Bulle en état « échec » avec action « **Renvoyer** » manuelle ; aucun rejeu automatique ; au renvoi (réseau rétabli), **aucun doublon** | |
| MSG-08 | Recevoir des messages puis ouvrir le fil et le quitter | envoyer 3 messages depuis l'autre rôle | À l'ouverture, messages marqués lus ; au retour, compteur du fil à zéro et pastille globale décrémentée | |
| MSG-09 | Ouvrir un fil de plus de 20 messages | fil de la mission de démonstration ou en générer | Les messages **les plus récents** d'abord ; l'historique se charge en remontant, sans saut de position | |
| MSG-10 | Ouvrir une conversation **clôturée** | fil d'une mission clôturée | Champ de saisie **masqué**, avec explication | |
| MSG-11 | Recevoir un message pendant que la conversation est **ouverte** au premier plan | — | Le fil se rafraîchit à réception de la notification | |
| MSG-12 | Vérifier l'absence de coordonnées | tout le fil | Aucun email ni téléphone de l'autre partie n'apparaît nulle part | |

---

## 14. Module NOTIF — Notifications et appareils

**Écrans** : `/notifications`, `/profile/devices`.
**Précondition** : deux comptes, notifications push acceptées sur l'appareil principal.

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| NOTIF-01 | À la première connexion, **refuser** l'autorisation de notification | — | Tous les parcours restent disponibles ; le centre de notifications intégré continue d'être alimenté ; un rappel existe dans les réglages | |
| NOTIF-02 | Provoquer un évènement depuis l'autre rôle (acceptation de mission, message) | — | Notification visible dans le centre ; pastille incrémentée | |
| NOTIF-03 | Appuyer sur une notification de **message**, application au premier plan | — | La conversation concernée s'ouvre directement | |
| NOTIF-04 | Même test, application en **arrière-plan**, puis **tuée** | — | Même routage direct dans les trois cas | |
| NOTIF-05 | Marquer une notification comme lue, puis « Tout marquer comme lu » | — | Marquage unitaire et global ; pastille remise à zéro ; **aucune suppression** possible | |
| NOTIF-06 | Filtrer le centre sur les non-lues, faire défiler | — | Filtre opérationnel, liste paginée | |
| NOTIF-07 | Se connecter avec un **second compte** sur le même appareil | `testeur.client2@prestgo.test` | Appareil ré-enregistré pour le nouveau compte ; l'ancien compte ne reçoit **plus** de notification sur cet appareil | |
| NOTIF-08 | Se déconnecter | — | Désenregistrement de l'appareil effectué **avant** la fermeture de session | |
| NOTIF-09 | Notification de décision sur le dossier prestataire (approbation ONB-17) | — | Notification reçue ; l'appui mène à l'écran concerné | |

---

## 15. Module AVIS — Noter, être noté, signaler

**Écrans** : `/missions/:id?tab=review`, `/reviews`, `/providers/:id/reviews`.
**Précondition** : une mission **terminée** entre `testeur.client` et le prestataire (issue de PRES-07). ⚠️ Ne pas utiliser la mission de démonstration (voir §3.3).

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| AVIS-01 | Côté client, ouvrir le détail de la mission terminée | — | « Laisser un avis » proposé, avec le **temps restant** (fenêtre de 14 j) | |
| AVIS-02 | Côté **prestataire**, ouvrir la même mission | — | **Aucune** action de notation proposée | |
| AVIS-03 | Déposer l'avis | note 5, « Travail soigné, prestataire ponctuel. Je recommande. » | Avis créé ; visible sur la fiche publique et dans `/reviews` | |
| AVIS-04 | Rouvrir le détail de la mission | — | Le bouton de dépôt a **disparu** ; l'avis est consultable | |
| AVIS-05 | Tenter un commentaire de 1001 caractères | — | Bloqué avant envoi (plafond 1000) | |
| AVIS-06 | Consulter `/reviews` (Mes avis) | — | Avis listés avec leur état de modération | |
| AVIS-07 | Au back-office, retirer l'avis (modération) ; rouvrir « Mes avis » | compte admin | Le contenu retiré est remplacé par une **mention explicite** | |
| AVIS-08 | Depuis un autre compte, signaler un avis d'un tiers | motif « Contenu inapproprié » | Signalement accepté ; l'action est **absente sur ses propres avis** | |
| AVIS-09 | Signaler une seconde fois le même avis | — | Mention « déjà signalé » | |

---

## 16. Module LIT — Litiges

**Écran** : `/missions/:id/dispute`.
**Précondition** : une mission dont l'utilisateur est partie (le compte `client.demo` porte déjà un litige ouvert sur la mission de démonstration).

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| LIT-01 | Ouvrir un litige sur une mission | motif « Prestation non conforme à la description » | Litige créé, état visible | |
| LIT-02 | Suivre le litige existant du compte `client.demo` | — | État consultable ; les **échanges internes de modération ne sont pas exposés** | |
| LIT-03 | Vérifier qu'aucune action de clôture « sauvage » n'existe | mission terminée | Aucune action hors du parcours de litige prévu sur les états terminaux | |

---

## 17. Module HL — Réseau dégradé et hors ligne

**Précondition** : application utilisée en ligne au préalable (écrans chargés au moins une fois).

| # | Étapes | Données | Résultat attendu | Résultat |
|---|---|---|---|---|
| HL-01 | Charger accueil, missions, détail d'une mission, une conversation, puis passer en **mode avion** | — | **Bannière permanente** de mode hors ligne + **date des données** affichée sur les écrans consultés | |
| HL-02 | Naviguer hors ligne dans les données déjà chargées | profil, missions, fil de discussion | Consultation possible depuis le cache, avec horodatage | |
| HL-03 | Tenter des écritures hors ligne | réserver, envoyer un message, annuler | Actions **indisponibles avec explication** ; **rien** n'est mis en file pour un rejeu ultérieur | |
| HL-04 | Rouvrir un **justificatif** hors ligne | `/provider/documents` | Contenu **non restitué** depuis le stockage local (fichier sensible) | |
| HL-05 | Rétablir le réseau sur un écran | — | Rafraîchissement **automatique** des données de l'écran courant | |
| HL-06 | Couper le réseau pendant une lecture (chargement de liste) | — | Au plus 2 tentatives silencieuses, puis état d'erreur avec action « Réessayer » | |

---

## 18. Module LIM — Plafonds, limites et robustesse

Tests transverses des limites (l'action doit devenir **indisponible avec motif**, jamais échouer après saisie).

| # | Limite | Comment tester | Résultat attendu | Résultat |
|---|---|---|---|---|
| LIM-01 | 10 adresses | PROF-07 | Ajout indisponible au plafond | |
| LIM-02 | 15 zones | cocher 15 zones (si le catalogue le permet) | 16ᵉ impossible | |
| LIM-03 | 20 réalisations | OFFRE-07 | 21ᵉ indisponible | |
| LIM-04 | 50 créneaux hebdomadaires | générer 50 créneaux | 51ᵉ indisponible | |
| LIM-05 | 10 options par réservation | cocher 10 options (en créer assez via OFFRE-02) | 11ᵉ impossible, pas de doublon d'option | |
| LIM-06 | 3 pièces jointes par message | MSG-05 | 4ᵉ refusée | |
| LIM-07 | Fichier de 10 Mo max, types filtrés | ONB-11, ONB-12 | Refus local avant appel réseau | |
| LIM-08 | Débit : 10 connexions/minute | enchaîner > 10 tentatives de connexion | Message d'attente + bouton **temporairement désactivé** — jamais de rejeu automatique | |
| LIM-09 | Débit : 5 envois de code/minute | spammer « Renvoyer un code » | Même comportement | |
| LIM-10 | Montants | tous les écrans avec prix | Toujours en **XOF**, format `fr_CI`, sans décimale, via le même formatage partout | |
| LIM-11 | Messages métier | provoquer des refus (annulation tardive, hors zone, désactivation refusée) | Message du service affiché **tel quel** (nombres inclus) ; jamais de code technique visible | |
| LIM-12 | Erreurs de champ | soumettre des formulaires invalides | L'erreur est rattachée **au champ concerné** quand l'information existe, bannière de formulaire sinon | |
| LIM-13 | Fuseau horaire | comparer un créneau saisi (ex. 08:00) avec son affichage côté client | Aucune conversion : « 08:00 » reste « 08:00 » partout | |

---

## 19. Vérifications transverses finales

À passer une fois tous les modules exécutés :

| Contrôle | Attendu | Résultat |
|---|---|---|
| Changement de compte (SC-012) | Après déconnexion + connexion avec un autre compte, **aucune donnée** du compte précédent n'est visible sur aucun écran (missions, fils, notifications, adresses, favoris) | |
| Session 7 jours (SC-007) | En ouvrant l'application chaque jour, jamais de ressaisie d'identifiants ; aucun écran de connexion au milieu d'une session valide | |
| États d'écran (FR-095) | Chaque liste/détail possède un état de chargement, un état d'erreur avec « Réessayer » et un état vide avec action utile | |
| Langue et formats (FR-101) | Interface entièrement en français ; dates, heures et montants au format ivoirien | |
| Stockage sécurisé | Aucun jeton ni justificatif lisible dans le stockage de l'appareil après usage | |
| Double surface | Jamais les deux espaces (client/prestataire) affichés simultanément | |
| Notifications propres | Aucune notification de confirmation attendue pour ses **propres** actions | |

---

## 20. Fiche d'anomalie (modèle)

```
ID du cas de test : (ex. RESA-09)
Écran / route     : (ex. /booking/summary)
Compte utilisé    : (ex. testeur.client@prestgo.test)
Appareil / OS     : (ex. Pixel 7 émulateur, Android 14)
Environnement     : dev / staging

Étapes de reproduction :
1. …
2. …

Résultat observé  : …
Résultat attendu  : …
Gravité           : bloquant / majeur / mineur / cosmétique
Pièces jointes    : captures d'écran, identifiant de corrélation de l'erreur (journaux)
```

> 💡 Chaque erreur remontée par le service porte un **identifiant de corrélation** : le relever dans les journaux réseau et le joindre systématiquement à la fiche.
