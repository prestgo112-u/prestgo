# Feature Specification: Application mobile PRESTGO (client + prestataire)

**Feature Branch**: `001-prestgo-mobile-app`

**Created**: 2026-07-30

**Status**: Draft

**Input**: User description: "@docs/PRESTGO-Mobile-Flutter-Cahier-des-charges.md"

## User Scenarios & Testing *(mandatory)*

L'application mobile PRESTGO met en relation des particuliers (clients) et des
professionnels de services à domicile (prestataires) en Côte d'Ivoire. Une seule
application porte les deux surfaces : un même compte peut être client, prestataire,
ou les deux. Les parcours ci-dessous sont ordonnés par valeur métier ; chacun est
livrable et démontrable indépendamment des suivants, à condition que le parcours
d'authentification (US1) soit en place.

### User Story 1 - Créer un compte et accéder à l'application (Priority: P1)

Un visiteur crée un compte avec son email et/ou son numéro de téléphone, active ce
compte par un code de vérification à 6 chiffres, puis se connecte. À chaque
ouverture ultérieure, il retrouve sa session sans ressaisir ses identifiants, et il
est amené automatiquement sur l'espace correspondant à sa situation (client,
onboarding prestataire en cours, dossier en attente, espace prestataire complet).
Il peut réinitialiser son mot de passe, se déconnecter, et désactiver son compte.

**Why this priority**: Aucune écriture (réservation, gestion d'offre, messagerie)
n'est possible sans compte actif. C'est le socle dont dépendent tous les autres
parcours.

**Independent Test**: Créer un compte neuf, l'activer, se connecter, fermer et
rouvrir l'application (session restaurée), se déconnecter, réinitialiser le mot de
passe et se reconnecter — sans toucher aux autres modules.

**Acceptance Scenarios**:

1. **Given** un visiteur sur l'écran d'inscription, **When** il saisit un email
   valide et un mot de passe conforme (8 à 128 caractères, au moins une lettre et un
   chiffre), **Then** son compte est créé à l'état non activé et il arrive sur
   l'écran de saisie du code de vérification, où un code lui est envoyé sans action
   supplémentaire de sa part.
2. **Given** un visiteur inscrit avec un numéro de téléphone seul, **When** il
   demande un code de connexion puis le saisit correctement, **Then** il est connecté
   sans mot de passe.
3. **Given** un code de vérification saisi correctement, **When** le compte était en
   attente d'activation, **Then** le compte devient actif et l'utilisateur est
   connecté et amené sur son espace d'atterrissage.
4. **Given** un code faux, expiré ou déjà utilisé, **When** l'utilisateur valide,
   **Then** un message unique « Code incorrect ou expiré » s'affiche, le champ est
   vidé et l'action « Renvoyer un code » est proposée.
5. **Given** 5 tentatives infructueuses sur le même code, **When** l'utilisateur
   réessaie, **Then** la saisie est désactivée et seul « Renvoyer un code » reste
   possible.
6. **Given** un utilisateur qui tente de se connecter avec un mot de passe erroné,
   **When** il valide, **Then** un message unique « Email ou mot de passe incorrect »
   s'affiche, sans jamais indiquer si l'adresse existe.
7. **Given** un utilisateur dont la session a expiré pendant l'utilisation, **When**
   il déclenche une action, **Then** la session est renouvelée silencieusement et
   l'action aboutit sans qu'il ait à se reconnecter ; si le renouvellement échoue, il
   est ramené à l'écran de connexion avec ses données locales purgées.
8. **Given** un utilisateur ayant demandé une réinitialisation de mot de passe,
   **When** il colle le jeton reçu par email et choisit un nouveau mot de passe,
   **Then** toutes ses sessions sont fermées et il doit se reconnecter.
9. **Given** un utilisateur ayant des missions confirmées ou en cours, **When** il
   demande la désactivation de son compte, **Then** l'opération est refusée avec le
   motif chiffré fourni par le service et un raccourci vers ses missions en cours.

---

### User Story 2 - Trouver un prestataire et réserver une prestation (Priority: P1)

Un visiteur, même non connecté, cherche un prestataire par catégorie, position,
créneau, note minimale ou mot-clé, consulte sa fiche complète (prestations, tarifs,
agenda, zones, avis, réalisations), puis réserve : formule, options, date/heure,
adresse d'intervention, instructions, récapitulatif chiffré, confirmation.

**Why this priority**: C'est la boucle de valeur de la plateforme (chercher →
réserver). C'est aussi l'écriture la plus sensible : elle doit être protégée contre
les doubles réservations.

**Independent Test**: Depuis un compte client disposant d'une adresse géolocalisée,
chercher un prestataire approuvé, ouvrir sa fiche, réserver un créneau valide et
retrouver la réservation dans « Mes missions ».

**Acceptance Scenarios**:

1. **Given** un visiteur non connecté, **When** il ouvre l'accueil, **Then** la
   recherche et les fiches prestataires sont consultables sans compte, photos
   comprises.
2. **Given** un visiteur non connecté sur une fiche prestataire, **When** il appuie
   sur « Réserver », **Then** il est amené à se connecter puis ramené sur la fiche
   d'origine.
3. **Given** un client qui compose une réservation, **When** il coche des options,
   **Then** le prix total et la durée totale se recalculent immédiatement à l'écran.
4. **Given** l'agenda hebdomadaire et les absences du prestataire, **When** le client
   ouvre le sélecteur de date et d'heure, **Then** seuls les créneaux où
   l'intervention tient entièrement (début + durée totale) sont proposables.
5. **Given** un délai minimum de réservation en vigueur, **When** le client choisit
   un horaire trop proche, **Then** l'horaire est refusé côté application avant
   l'envoi, avec le délai réellement en vigueur affiché.
6. **Given** une adresse hors de la zone d'intervention du prestataire, **When** la
   réservation est refusée pour ce motif, **Then** l'application propose de choisir
   une autre adresse et affiche les zones effectivement couvertes.
7. **Given** un client dont le carnet d'adresses est vide, **When** il lance une
   réservation, **Then** il est d'abord invité à créer une adresse géolocalisée.
8. **Given** une confirmation de réservation interrompue par une coupure réseau,
   **When** l'application réessaie, **Then** aucune réservation en double n'est créée
   et le client voit une seule mission.
9. **Given** un créneau pris par quelqu'un d'autre entre l'affichage et la
   confirmation, **When** le client confirme, **Then** un message « Ce créneau vient
   d'être pris » s'affiche et le sélecteur se rouvre en conservant le reste du
   brouillon.

---

### User Story 3 - Suivre et gérer mes réservations (client) (Priority: P2)

Un client consulte ses missions classées par onglets (à venir, en cours, terminées,
annulées), ouvre le détail (prestataire, formule, adresse, instructions, montant,
frise des évènements), annule avec motif, propose un report de date, et répond aux
reports proposés par le prestataire.

**Why this priority**: Sans suivi, la réservation n'a pas de service après-vente ;
c'est le deuxième motif d'ouverture de l'application côté client.

**Independent Test**: Sur un compte client ayant au moins une mission, parcourir les
onglets, ouvrir un détail, annuler une mission, proposer un report et le voir passer
en attente de réponse.

**Acceptance Scenarios**:

1. **Given** un client avec des missions dans plusieurs états, **When** il ouvre
   l'onglet « Terminées », **Then** les missions terminées et clôturées sont listées
   ensemble, en un seul chargement, avec le compte total correct.
2. **Given** une mission annulable, **When** le client demande l'annulation à moins
   du délai de préavis en vigueur, **Then** il est averti **avant** l'envoi que
   l'annulation sera enregistrée comme tardive, et peut renoncer.
3. **Given** une annulation acceptée, **When** la réponse revient, **Then** le
   message renvoyé par le service est affiché tel quel et les listes de missions,
   le détail et le compteur de notifications sont rafraîchis.
4. **Given** une demande de report déjà en attente sur une mission, **When** le
   client ouvre le détail, **Then** l'action « Proposer un report » est indisponible
   et l'attente est expliquée.
5. **Given** une demande de report créée par le client lui-même, **When** il ouvre le
   détail, **Then** aucun bouton « Accepter » / « Refuser » n'est proposé sur sa
   propre demande.
6. **Given** un report proposé par le prestataire, **When** le client l'accepte,
   **Then** la mission est déplacée à la nouvelle date ; si le créneau n'est plus
   disponible, l'application propose de faire une contre-proposition.

---

### User Story 4 - Devenir prestataire et faire valider son dossier (Priority: P2)

Un utilisateur actif ouvre le parcours « Devenir prestataire » : il crée son profil
public, déclare au moins un service avec une formule tarifaire, choisit ses zones
d'intervention, renseigne son agenda hebdomadaire, dépose ses justificatifs, puis
soumet son dossier. Il suit ensuite l'état de la vérification et corrige ce qui lui
est demandé.

**Why this priority**: Sans prestataires validés, l'offre est vide et US2 n'a rien à
proposer. Le parcours est long : il doit être repris là où il s'est arrêté.

**Independent Test**: Depuis un compte actif sans profil prestataire, dérouler les
cinq étapes jusqu'à la soumission, puis vérifier l'écran de suivi et le parcours de
correction après une demande de modification.

**Acceptance Scenarios**:

1. **Given** un utilisateur actif sans profil prestataire, **When** il crée son
   profil public, **Then** il arrive sur un tableau de complétude à cinq lignes dont
   l'état vient du service, chaque ligne rouge ouvrant l'étape correspondante.
2. **Given** un profil créé sans présentation, **When** l'utilisateur consulte le
   tableau, **Then** la ligne « profil » est rouge et son libellé mentionne
   explicitement que le nom public **et** la présentation sont requis.
3. **Given** un service déclaré sans formule tarifaire, **When** l'utilisateur
   consulte le tableau, **Then** la ligne « prestations » reste rouge et indique
   qu'une formule active est nécessaire.
4. **Given** une liste de zones non vide, **When** l'utilisateur la vide entièrement,
   **Then** une confirmation explicite est demandée, en précisant qu'il disparaîtra
   des résultats de recherche.
5. **Given** un agenda hebdomadaire en cours de saisie, **When** l'utilisateur crée
   deux créneaux qui se chevauchent le même jour ou dont la fin précède le début,
   **Then** l'erreur est signalée avant l'envoi.
6. **Given** les cinq lignes au vert et un dossier soumissible, **When**
   l'utilisateur soumet, **Then** le dossier passe en vérification et l'écran de
   suivi affiche la date de soumission.
7. **Given** un dossier en cours de vérification, **When** l'utilisateur ouvre son
   profil prestataire, **Then** les champs d'identité sont en lecture seule et seul
   l'interrupteur de disponibilité reste actionnable.
8. **Given** un dossier en « corrections demandées », **When** l'utilisateur dépose
   un nouveau justificatif, **Then** l'application signale que le dossier est reparti
   en vérification et ne propose plus « Re-soumettre ».
9. **Given** un dossier refusé dont la re-soumission est bloquée, **When**
   l'utilisateur ouvre l'écran de suivi, **Then** aucun bouton de re-soumission n'est
   affiché et un contact support est proposé.

---

### User Story 5 - Piloter ma journée de prestataire (Priority: P2)

Un prestataire approuvé ouvre son tableau de bord : demandes en attente de réponse,
missions du jour, messages et notifications non lus, interrupteur de disponibilité.
Il accepte ou refuse une demande, démarre une mission à l'heure, la termine, ou
l'annule avec motif.

**Why this priority**: C'est l'écran le plus souvent ouvert par un prestataire et le
maillon qui fait avancer les missions réservées en US2.

**Independent Test**: Sur un compte prestataire approuvé disposant d'une demande en
attente, accepter la demande, démarrer puis terminer la mission, et constater les
changements d'état et les compteurs.

**Acceptance Scenarios**:

1. **Given** un prestataire approuvé, **When** il ouvre son tableau de bord,
   **Then** les demandes en attente, les missions du jour et les compteurs non lus
   s'affichent, chaque bloc pouvant échouer sans empêcher les autres de s'afficher.
2. **Given** une demande non encore acceptée, **When** le prestataire ouvre le
   détail, **Then** seuls « Accepter » et « Refuser » sont proposés — jamais
   « Annuler ».
3. **Given** une mission acceptée, **When** l'heure prévue est encore éloignée de
   plus que la fenêtre de démarrage en vigueur, **Then** « Démarrer » est
   indisponible et l'heure à partir de laquelle il sera actionnable est affichée.
4. **Given** un refus de mission, **When** le prestataire valide sans motif,
   **Then** l'envoi est bloqué et le motif est exigé (au moins 3 caractères).
5. **Given** une demande en attente non traitée, **When** le prestataire consulte la
   liste, **Then** le temps restant avant expiration automatique est affiché.
6. **Given** une transition de mission dont la réponse n'est pas parvenue,
   **When** le réseau revient, **Then** l'application ne rejoue jamais l'action
   automatiquement : elle rafraîchit l'état réel et laisse le prestataire décider.
7. **Given** l'interrupteur de disponibilité, **When** le prestataire le manipule,
   **Then** la différence entre « Occupé » (toujours réservable) et « Indisponible »
   (plus aucune réservation possible) est explicitée à l'écran.

---

### User Story 6 - Échanger par messagerie sur une mission (Priority: P3)

Client et prestataire échangent dans un fil rattaché à une mission, avec pièces
jointes, sans jamais voir les coordonnées personnelles de l'autre partie.

**Why this priority**: Indispensable à la bonne exécution des missions (accès,
horaire, précisions), mais une mission peut se dérouler sans échange.

**Independent Test**: Sur une mission existante, ouvrir la conversation depuis
l'onglet Messagerie et depuis le détail de la mission, envoyer un message avec pièce
jointe, vérifier la remise à zéro du compteur non lus.

**Acceptance Scenarios**:

1. **Given** un utilisateur avec des conversations, **When** il ouvre l'onglet
   Messagerie, **Then** chaque fil affiche l'interlocuteur, le dernier message et son
   nombre de non-lus, et la pastille de l'onglet reflète le total global.
2. **Given** une conversation longue, **When** l'utilisateur l'ouvre, **Then** les
   messages les plus récents sont affichés en premier écran et l'historique se charge
   en remontant.
3. **Given** une conversation ouverte, **When** l'utilisateur la quitte, **Then** ses
   messages ont été marqués lus et le compteur du fil est à zéro.
4. **Given** un envoi de message échoué, **When** l'erreur survient, **Then** la
   bulle reste visible en état « échec » avec une action « Renvoyer » manuelle, sans
   rejeu automatique.
5. **Given** une conversation clôturée, **When** l'utilisateur l'ouvre, **Then** le
   champ de saisie est masqué avec l'explication.
6. **Given** un message reçu pendant que l'application est au premier plan,
   **When** la notification arrive, **Then** la conversation affichée se rafraîchit.

---

### User Story 7 - Être averti au bon moment (Priority: P3)

L'utilisateur reçoit des notifications (dans l'application et, s'il l'accepte, en
push) pour les évènements de mission, les messages, les demandes de report, les avis
et les décisions sur son dossier prestataire ; un appui ouvre directement l'écran
concerné.

**Why this priority**: Améliore fortement la réactivité (acceptation d'une mission,
réponse à un message), mais l'application reste utilisable sans push.

**Independent Test**: Provoquer un évènement de mission depuis l'autre rôle, vérifier
l'apparition dans le centre de notifications, le compteur, le marquage lu et le
routage au tap.

**Acceptance Scenarios**:

1. **Given** un utilisateur qui refuse l'autorisation de notification, **When** il
   utilise l'application, **Then** tous les parcours restent disponibles et le centre
   de notifications intégré reste alimenté.
2. **Given** une notification de conversation, **When** l'utilisateur appuie dessus,
   **Then** la conversation concernée s'ouvre directement — que l'application ait été
   au premier plan, en arrière-plan ou fermée.
3. **Given** des notifications non lues, **When** l'utilisateur ouvre le centre,
   **Then** le compteur est à jour et « Tout marquer comme lu » remet la pastille à
   zéro.
4. **Given** une connexion sur un appareil déjà utilisé par un autre compte,
   **When** la connexion réussit, **Then** l'appareil est ré-enregistré pour le
   nouveau compte et l'ancien propriétaire ne reçoit plus ses notifications.
5. **Given** une déconnexion, **When** l'utilisateur la déclenche, **Then**
   l'appareil est désenregistré avant la fermeture de session, et la déconnexion
   aboutit même si le réseau est coupé.

---

### User Story 8 - Gérer mon offre de prestataire dans la durée (Priority: P3)

Un prestataire approuvé fait évoluer son profil public, ses prestations, ses
formules et options, ses zones, son agenda, ses absences, son portfolio et ses
justificatifs.

**Why this priority**: Nécessaire à la vie du compte après validation, mais la
première version du dossier est déjà constituée en US4.

**Independent Test**: Modifier un prix, désactiver une formule, ajouter une absence,
ajouter puis retirer une réalisation, et constater les effets sur la fiche publique.

**Acceptance Scenarios**:

1. **Given** un prestataire modifiant un prix, **When** il enregistre, **Then**
   l'application indique que les missions déjà réservées conservent leur montant.
2. **Given** un service ou une formule que le prestataire veut retirer, **When** il
   ouvre l'action, **Then** le vocabulaire employé est « Désactiver » et l'effet
   (disparition des résultats de recherche si plus aucune formule active) est
   annoncé.
3. **Given** un portfolio à 20 réalisations, **When** le prestataire tente d'en
   ajouter une, **Then** l'action est indisponible avec le motif affiché.
4. **Given** une photo de profil ou une réalisation, **When** le prestataire la
   publie, **Then** il est prévenu qu'elle devient visible par tous les visiteurs.
5. **Given** un justificatif déjà validé, **When** le prestataire ouvre la ligne,
   **Then** l'action de re-dépôt est indisponible ; un justificatif refusé affiche
   son motif et propose un nouveau dépôt.

---

### User Story 9 - Noter, être noté, signaler (Priority: P3)

Après une mission terminée, le client note le prestataire et laisse un commentaire,
dans une fenêtre de temps limitée. Chacun peut signaler un avis abusif.

**Why this priority**: Alimente la confiance et le classement des résultats, mais
n'est pas nécessaire à la réalisation d'une mission.

**Independent Test**: Sur une mission terminée, déposer un avis, vérifier qu'il
apparaît sur la fiche publique et dans « Mes avis », et que le bouton de dépôt
disparaît ensuite.

**Acceptance Scenarios**:

1. **Given** une mission terminée dont le client n'a pas encore donné d'avis,
   **When** il ouvre le détail, **Then** « Laisser un avis » est proposé avec le
   temps restant pour le faire.
2. **Given** un prestataire sur une mission terminée, **When** il ouvre le détail,
   **Then** aucune action de notation ne lui est proposée.
3. **Given** un avis déjà déposé sur la mission, **When** le client rouvre le détail,
   **Then** l'action de dépôt n'est plus proposée et son avis est consultable.
4. **Given** un avis retiré par la modération, **When** le client consulte « Mes
   avis », **Then** la mention correspondante est affichée à la place du contenu.
5. **Given** un avis d'un tiers, **When** l'utilisateur le signale une seconde fois,
   **Then** l'application indique qu'il est déjà signalé.

---

### User Story 10 - Rester utilisable en réseau dégradé (Priority: P4)

En zone blanche ou avec une connexion instable, l'utilisateur consulte les données
déjà chargées (profil, agenda du jour, détail d'une mission, fil de discussion) avec
l'âge de ces données affiché, et comprend immédiatement pourquoi les actions
d'écriture sont indisponibles.

**Why this priority**: Confort déterminant sur le terrain, mais l'application reste
fonctionnelle sans, dès lors que le réseau est présent.

**Independent Test**: Charger les écrans clés, couper le réseau, vérifier la
consultation, la bannière, l'horodatage et l'indisponibilité des écritures, puis
rétablir le réseau et constater la reprise.

**Acceptance Scenarios**:

1. **Given** une application déjà utilisée en ligne, **When** le réseau est coupé,
   **Then** une bannière permanente indique le mode hors ligne et la date des données
   affichées.
2. **Given** le mode hors ligne, **When** l'utilisateur tente une action d'écriture,
   **Then** l'action est indisponible avec une explication — elle n'est jamais
   acceptée pour être rejouée plus tard.
3. **Given** un retour du réseau, **When** l'utilisateur revient sur un écran,
   **Then** les données sont rafraîchies automatiquement.
4. **Given** des justificatifs consultés hors ligne, **When** l'utilisateur y revient
   sans réseau, **Then** leur contenu n'est pas restitué depuis le stockage local.

---

### Edge Cases

- **Compte à double casquette** : un utilisateur possédant un profil client et un
  profil prestataire bascule d'un espace à l'autre sans se reconnecter, et
  l'application n'ouvre jamais les deux surfaces simultanément sur le même écran.
- **Compte non activé qui tente de se connecter** : le service ne distingue pas
  « jamais activé » de « suspendu » ; l'application propose les deux issues
  (relancer la vérification, contacter le support).
- **Réservation de sa propre prestation** : bloquée côté application avant l'envoi.
- **Prestataire devenu indisponible ou suspendu entre la recherche et la
  réservation** : message explicite et retour à la recherche ; un favori dans ce cas
  reste listé, grisé, non réservable.
- **Adresse utilisée par des missions passées** : sa suppression la retire du carnet
  sans effacer l'historique ; l'application affiche le motif renvoyé.
- **Plafonds atteints** : 10 adresses, 15 zones, 20 réalisations, 50 créneaux
  hebdomadaires, 10 options par réservation, 3 pièces jointes par message — l'action
  d'ajout est indisponible avec le motif, jamais un échec après saisie.
- **Fichier trop lourd ou de type non accepté** : filtré avant l'envoi (10 Mo max ;
  images JPEG/PNG/WebP, PDF, texte, CSV) ; les photos de profil, réalisations et
  images ne sont acceptées qu'en format image.
- **Trop de tentatives** : les écrans concernés désactivent temporairement le bouton
  au lieu de réessayer automatiquement.
- **Horaires et fuseaux** : les créneaux hebdomadaires sont saisis et affichés tels
  quels, sans conversion vers le fuseau de l'appareil ; les dates d'intervention sont
  transmises en temps universel.
- **Changement d'email ou de téléphone** : le contact redevient non vérifié et un
  code est envoyé automatiquement ; l'application enchaîne sur l'écran de
  vérification.
- **Changement de mot de passe depuis le compte** : la session courante survit ; une
  réinitialisation par jeton, elle, ferme toutes les sessions.
- **Expiration d'une demande non traitée** : la demande passe en expirée sans action
  du prestataire ; l'application ne propose pas d'action sur un état terminal.
- **États terminaux** : aucune action n'est proposée pour clôturer une mission ou
  ouvrir un état de litige autrement que par le parcours de litige prévu.
- **Message d'erreur métier contenant un nombre** (missions bloquantes, sessions
  fermées, délais) : affiché tel quel, jamais reconstruit côté application.
- **Erreurs de créneau côté prestataire** : les libellés désignant « le prestataire »
  sont reformulés à la deuxième personne quand c'est le prestataire lui-même qui agit.

## Requirements *(mandatory)*

### Functional Requirements

#### Authentification, session et compte

- **FR-001** : L'application MUST permettre la création d'un compte avec un email,
  un numéro de téléphone, ou les deux — au moins un des deux étant obligatoire — un
  mot de passe de 8 à 128 caractères contenant au moins une lettre et un chiffre, et
  des nom/prénom facultatifs limités à 80 caractères.
- **FR-002** : L'application MUST déclencher l'envoi du code de vérification dès
  l'arrivée sur l'écran de saisie, afficher un compte à rebours fondé sur la durée de
  validité communiquée par le service, et proposer un renvoi limité (au plus un
  renvoi par minute).
- **FR-003** : L'application MUST accepter un code de vérification de 6 chiffres
  exactement, désactiver la saisie après 5 échecs sur le même code, et n'afficher
  qu'un message unique pour un code faux, expiré ou déjà consommé.
- **FR-004** : L'application MUST distinguer, à la vérification, l'activation d'un
  compte (enchaînement automatique vers la connexion) d'une simple vérification de
  contact (retour à l'écran d'origine avec confirmation), en se fondant sur
  l'information structurée renvoyée et non sur le texte du message.
- **FR-005** : L'application MUST proposer une connexion par email + mot de passe et
  une connexion sans mot de passe par code envoyé au téléphone, cette dernière
  produisant une session de plein droit.
- **FR-006** : L'application MUST afficher un message unique et non discriminant en
  cas d'échec d'identification, et proposer deux issues (relancer la vérification,
  contacter le support) lorsque le compte n'est pas actif.
- **FR-007** : L'application MUST conserver les jetons de session dans le stockage
  sécurisé du système d'exploitation, jamais en clair.
- **FR-008** : L'application MUST renouveler la session de façon transparente : un
  seul renouvellement en cours à la fois, mise en attente des requêtes concurrentes,
  rejeu unique de la requête d'origine, remplacement systématique du jeton de
  renouvellement, et retour à l'écran de connexion avec purge locale en cas d'échec.
- **FR-009** : L'application MUST exclure du rejeu automatique les envois de fichiers
  et proposer à la place une reprise explicite de l'action.
- **FR-010** : L'application MUST proposer une réinitialisation de mot de passe en
  deux temps (demande, puis saisie manuelle ou collage du jeton reçu par email),
  afficher toujours le même message neutre à la demande, et ramener l'utilisateur à
  la connexion après succès.
- **FR-011** : L'application MUST exécuter la déconnexion dans l'ordre suivant :
  désenregistrement de l'appareil, fermeture de session, purge du stockage sécurisé
  et de tous les caches, retour à l'écran de connexion — les deux premières étapes
  étant au mieux tentées et jamais bloquantes.
- **FR-012** : L'application MUST proposer une désactivation de compte en double
  confirmation, avec saisie du mot de passe, un vocabulaire explicite
  (« Désactiver », pas « Supprimer ») et la mention que missions passées et avis sont
  conservés.
- **FR-013** : L'application MUST déterminer l'écran d'atterrissage après connexion
  et à chaque démarrage à partir de l'état du compte : espace client si aucun profil
  prestataire ; reprise de l'onboarding, écran d'attente, écran de correction, écran
  d'information ou espace prestataire complet selon l'état du dossier.
- **FR-014** : L'application MUST permettre à un compte disposant d'un profil
  prestataire de basculer explicitement vers l'espace client et inversement, sans
  reconnexion.
- **FR-015** : L'application MUST conditionner l'accès à l'espace client au seul
  caractère actif du compte, et non à la présence d'un profil client.

#### Profil, adresses, favoris

- **FR-016** : L'application MUST afficher le profil (identité, contacts avec mention
  « non vérifié » le cas échéant, ancienneté) et permettre sa modification.
- **FR-017** : L'application MUST enchaîner automatiquement sur l'écran de
  vérification lorsqu'une modification de l'email ou du téléphone déclenche l'envoi
  d'un code, en ciblant le bon canal.
- **FR-018** : L'application MUST permettre le changement de mot de passe depuis le
  compte, en conservant la session courante et en affichant le nombre de sessions
  fermées tel qu'il est renvoyé.
- **FR-019** : L'application MUST gérer un carnet d'adresses limité à 10 entrées,
  chaque adresse comportant obligatoirement une position géographique saisie via un
  sélecteur de position (position courante et ajustement sur carte), un libellé et
  une ville.
- **FR-020** : L'application MUST permettre de définir une adresse par défaut, la
  présélectionner à la réservation, et rendre indisponible l'ajout au-delà du plafond
  en affichant le motif.
- **FR-021** : L'application MUST gérer une liste de favoris, avec ajout et retrait
  immédiats à l'écran, et griser sans les masquer les prestataires devenus non
  réservables.

#### Recherche et fiche prestataire

- **FR-022** : L'application MUST rendre la recherche et les fiches prestataires
  consultables sans compte, y compris les photos de profil et les réalisations.
- **FR-023** : L'application MUST proposer les filtres suivants : catégorie, type de
  service, position et rayon (1 à 50 km, 10 km par défaut), zone, créneau (date et
  heure indissociables), note minimale, mot-clé, et un tri parmi distance, note et
  récence.
- **FR-024** : L'application MUST empêcher en amont les combinaisons de filtres
  refusées : tri par distance sans position, date sans heure ou heure sans date.
- **FR-025** : L'application MUST paginer les résultats en défilement continu et
  proposer, sur un résultat vide, d'élargir le rayon (jusqu'au maximum) ou de retirer
  les filtres.
- **FR-026** : L'application MUST afficher « Nouveau » plutôt qu'une note nulle pour
  un prestataire sans avis, masquer la distance quand aucune position n'a été fournie
  et masquer le prix d'appel quand il est absent.
- **FR-027** : L'application MUST composer la fiche prestataire en un seul
  chargement : présentation, prestations et formules avec options, agenda et absences
  à venir, zones couvertes, réalisations, répartition des notes et derniers avis, la
  liste complète des avis étant paginée à part.
- **FR-028** : L'application MUST rediriger un visiteur non connecté vers
  l'authentification lorsqu'il déclenche une action nécessitant un compte, puis le
  ramener à l'écran d'origine.

#### Réservation

- **FR-029** : L'application MUST composer une réservation à partir d'une formule,
  d'options (10 au maximum, sans doublon), d'une date et d'une heure, d'une adresse
  du carnet et d'instructions facultatives de 500 caractères au plus.
- **FR-030** : L'application MUST recalculer et afficher en continu le prix total et
  la durée totale (formule + options) avant confirmation.
- **FR-031** : L'application MUST restreindre le sélecteur de date et d'heure à
  l'agenda hebdomadaire du prestataire, hors absences annoncées, et n'autoriser qu'un
  début permettant à la durée totale de tenir entièrement dans le créneau.
- **FR-032** : L'application MUST appliquer le délai minimum de réservation en
  vigueur lu auprès du service, avec une valeur de repli si cette lecture échoue.
- **FR-033** : L'application MUST protéger la confirmation contre les doubles
  soumissions au moyen d'une clé d'unicité générée une fois par brouillon de
  réservation, réutilisée pour toute nouvelle tentative sur le même contenu, et
  renouvelée dès que le contenu change.
- **FR-034** : L'application MUST traiter une réponse indiquant que la réservation
  était déjà enregistrée comme un succès, et traiter une réponse indiquant un
  traitement en cours par une attente puis une vérification de la liste des missions
  — jamais par un message d'erreur immédiat.
- **FR-035** : L'application MUST ramener l'utilisateur à l'étape fautive (créneau,
  adresse, options) en conservant le reste du brouillon lorsque la réservation est
  refusée pour un motif corrigeable.
- **FR-036** : L'application MUST afficher tous les montants dans une devise unique
  (franc CFA) via un formateur centralisé.

#### Missions, transitions et reports

- **FR-037** : L'application MUST présenter les missions du client en onglets
  couvrant à venir, en cours, terminées et annulées, chacun obtenu en un seul
  chargement, l'historique le plus récent en premier.
- **FR-038** : L'application MUST présenter les missions du prestataire dans l'ordre
  chronologique croissant (ce qui arrive d'abord) et sans re-tri local.
- **FR-039** : L'application MUST afficher le détail d'une mission (état, horaire,
  formule, options, montant figé, adresse, instructions, contrepartie, conversation
  liée, annulation éventuelle avec caractère tardif, avis existants) et la frise des
  évènements.
- **FR-040** : L'application MUST n'afficher aucune coordonnée personnelle de l'autre
  partie et orienter systématiquement la mise en relation vers la messagerie.
- **FR-041** : L'application MUST proposer, côté prestataire, uniquement les actions
  compatibles avec l'état courant : accepter et refuser avant acceptation, démarrer
  et annuler après acceptation, terminer pendant l'exécution, aucune action sur les
  états terminaux.
- **FR-042** : L'application MUST rendre le démarrage indisponible tant que la
  fenêtre de démarrage en vigueur n'est pas ouverte, en affichant l'heure à partir de
  laquelle il le sera.
- **FR-043** : L'application MUST afficher le temps restant avant expiration
  automatique d'une demande non traitée.
- **FR-044** : L'application MUST exiger un motif d'au moins 3 caractères pour un
  refus, une annulation et un refus de report.
- **FR-045** : L'application MUST avertir avant l'envoi qu'une annulation sera
  enregistrée comme tardive, sur la base du délai de préavis en vigueur, puis
  afficher le message renvoyé par le service.
- **FR-046** : L'application MUST ne jamais rejouer automatiquement une transition de
  mission : en cas de réponse non reçue, elle rafraîchit l'état réel et laisse
  l'utilisateur décider.
- **FR-047** : L'application MUST n'autoriser qu'une demande de report en attente à
  la fois par mission, et masquer les actions de réponse sur ses propres demandes.
- **FR-048** : L'application MUST proposer une contre-proposition lorsqu'un report
  accepté échoue faute de disponibilité au moment de la réponse.
- **FR-049** : L'application MUST reformuler à la deuxième personne, côté
  prestataire, les messages de disponibilité qui désignent « le prestataire ».
- **FR-050** : L'application MUST rafraîchir, après chaque écriture aboutie, les
  listes, détails et compteurs qui en dépendent.

#### Onboarding et espace prestataire

- **FR-051** : L'application MUST présenter le dossier prestataire comme un tableau
  de complétude à cinq lignes (profil, prestations, zones, disponibilités,
  justificatifs) alimenté par le service, chaque ligne non satisfaite ouvrant
  directement l'étape correspondante, dans un ordre libre.
- **FR-052** : L'application MUST reprendre un parcours d'onboarding interrompu sans
  créer de doublon lorsque le profil prestataire existe déjà.
- **FR-053** : L'application MUST libeller la ligne « profil » de façon à exiger
  explicitement le nom public **et** la présentation, et la ligne « prestations » de
  façon à exiger un service **avec** une formule tarifaire active.
- **FR-054** : L'application MUST gérer les zones d'intervention comme une liste à
  cocher remplacée en bloc, limitée à 15 zones sans doublon, avec confirmation
  explicite si l'utilisateur vide une liste non vide.
- **FR-055** : L'application MUST gérer l'agenda hebdomadaire comme une grille de 7
  jours (dimanche = premier jour) et 50 créneaux au maximum, en heures et minutes sur
  24 heures, affichées et transmises sans conversion de fuseau, en vérifiant avant
  envoi que chaque fin suit son début et qu'aucun créneau ne chevauche un autre le
  même jour.
- **FR-056** : L'application MUST gérer les absences exceptionnelles (période et
  motif facultatif), en vérifiant avant envoi que la fin suit le début et qu'aucun
  chevauchement n'existe.
- **FR-057** : L'application MUST construire l'écran des justificatifs à partir de la
  liste des types exigés renvoyée par le service, jamais à partir d'une liste codée
  en dur, et afficher pour chaque type son état, son motif de refus éventuel et son
  historique de versions.
- **FR-058** : L'application MUST découper le dépôt d'un justificatif en deux temps
  (envoi du fichier puis rattachement), filtrer taille et type avant envoi, et
  interdire le re-dépôt sur un justificatif déjà validé.
- **FR-059** : L'application MUST rafraîchir l'état du dossier après chaque dépôt de
  justificatif, signaler le retour automatique en vérification le cas échéant, et ne
  plus proposer de re-soumission dans ce cas.
- **FR-060** : L'application MUST piloter la disponibilité du bouton de soumission
  sur l'indicateur fourni par le service, et non sur son propre calcul de complétude.
- **FR-061** : L'application MUST marquer en rouge exactement les lignes désignées
  par le service lorsqu'une soumission est refusée pour dossier incomplet.
- **FR-062** : L'application MUST rendre les champs d'identité du profil prestataire
  non modifiables pendant la vérification, tout en laissant l'interrupteur de
  disponibilité actionnable.
- **FR-063** : L'application MUST masquer définitivement la re-soumission et orienter
  vers le support lorsque celle-ci est bloquée.
- **FR-064** : L'application MUST rafraîchir l'état du dossier au retour au premier
  plan, sur geste de rafraîchissement et à la réception d'une notification de
  décision, aucun flux temps réel n'étant disponible.
- **FR-065** : L'application MUST composer le tableau de bord prestataire à partir de
  blocs indépendants (demandes en attente, missions du jour, non-lus), l'échec d'un
  bloc n'empêchant pas l'affichage des autres.
- **FR-066** : L'application MUST expliciter la différence entre « Occupé » (toujours
  réservable) et « Indisponible » (retiré de la recherche et non réservable).
- **FR-067** : L'application MUST employer le vocabulaire « Désactiver » pour les
  prestations, formules et options, annoncer que la désactivation de toutes les
  formules retire le prestataire des résultats, et indiquer qu'un changement de prix
  ne modifie pas les missions déjà réservées.
- **FR-068** : L'application MUST gérer un portfolio de 20 réalisations au maximum,
  en images uniquement, avec réordonnancement élément par élément et retour à l'ordre
  du service en cas d'échec partiel.
- **FR-069** : L'application MUST prévenir l'utilisateur qu'une photo de profil ou
  une réalisation publiée devient visible par tous les visiteurs.

#### Avis

- **FR-070** : L'application MUST ne proposer le dépôt d'un avis qu'au client, sur
  une mission terminée ou clôturée, sans avis déjà déposé par lui, et à l'intérieur
  de la fenêtre de dépôt en vigueur, en affichant le temps restant.
- **FR-071** : L'application MUST accepter une note entière de 1 à 5 et un
  commentaire d'au plus 1000 caractères, et traiter un refus pour avis déjà déposé
  comme un succès en affichant l'avis existant.
- **FR-072** : L'application MUST lister les avis déposés par l'utilisateur avec leur
  état de modération, en remplaçant le contenu retiré par une mention explicite.
- **FR-073** : L'application MUST permettre de signaler l'avis d'un tiers avec un
  motif, masquer cette action sur ses propres avis et signaler un doublon de
  signalement.

#### Messagerie

- **FR-074** : L'application MUST proposer une liste des conversations avec
  interlocuteur, dernier message, nombre de non-lus par fil et pastille globale.
- **FR-075** : L'application MUST charger une conversation par pages et présenter en
  premier écran les messages les plus récents, l'historique se chargeant à la demande.
- **FR-076** : L'application MUST permettre l'envoi de messages de 1 à 4000
  caractères avec au plus 3 pièces jointes distinctes, envoyées au préalable.
- **FR-077** : L'application MUST afficher un message en cours d'envoi de façon
  optimiste, puis en état d'échec avec une action de renvoi manuel — sans rejeu
  automatique.
- **FR-078** : L'application MUST masquer la saisie sur une conversation clôturée.
- **FR-079** : L'application MUST marquer la conversation comme lue à son ouverture
  et mettre à jour les compteurs.
- **FR-080** : L'application MUST rafraîchir une conversation à l'ouverture, sur
  geste de rafraîchissement, au retour au premier plan et à la réception d'une
  notification de message, sans dépendre d'un flux temps réel ni d'une interrogation
  périodique.

#### Notifications et appareils

- **FR-081** : L'application MUST proposer un centre de notifications paginé,
  filtrable sur les non-lues, avec marquage unitaire et global, sans suppression.
- **FR-082** : L'application MUST afficher une pastille de non-lus rafraîchie au
  démarrage, au retour au premier plan et à la réception d'une notification.
- **FR-083** : L'application MUST router l'appui sur une notification — interne ou
  poussée — vers l'écran concerné (mission, conversation, demande de report, avis) à
  partir de la même information de charge utile, et vers le centre de notifications à
  défaut.
- **FR-084** : L'application MUST gérer le cycle de vie de l'appareil : demande
  d'autorisation et enregistrement après chaque connexion, ré-enregistrement au
  démarrage sur session restaurée, remplacement lors d'un changement de jeton
  d'appareil, désenregistrement avant déconnexion.
- **FR-085** : L'application MUST rester entièrement fonctionnelle si l'autorisation
  de notification est refusée, et proposer un rappel dans les réglages.
- **FR-086** : L'application MUST ne pas attendre de notification de confirmation
  pour ses propres actions.

#### Comportements transverses

- **FR-087** : L'application MUST traiter les réponses du service selon une enveloppe
  unique (succès, message, données, erreurs, méta-données) et exposer une seule
  représentation d'erreur à ses écrans.
- **FR-088** : L'application MUST afficher les messages métier renvoyés par le
  service tels quels — y compris ceux contenant un nombre calculé — sauf pour les
  messages techniques non destinés à l'utilisateur final et pour les libellés
  reformulés côté prestataire (FR-049), qui MUST être remplacés par un texte
  compréhensible.
- **FR-089** : L'application MUST associer chaque message d'erreur de champ au champ
  désigné quand cette information est fournie, et se rabattre sur une bannière de
  formulaire sinon.
- **FR-090** : L'application MUST reproduire côté client les règles de saisie
  documentées (longueurs, formats, plafonds) afin de signaler l'erreur avant l'envoi.
- **FR-091** : L'application MUST journaliser l'identifiant de corrélation présent sur
  chaque erreur dans son outil de rapport d'incident.
- **FR-092** : L'application MUST traiter les dépassements de débit par un message
  d'attente et une désactivation temporaire de l'action, jamais par un rejeu
  automatique.
- **FR-093** : L'application MUST ne rejouer automatiquement que les lectures (au
  plus 2 tentatives, sur erreur réseau ou indisponibilité temporaire) et les
  écritures sans effet cumulatif ; toute autre écriture MUST faire l'objet d'une
  reprise explicite par l'utilisateur.
- **FR-094** : L'application MUST lire au démarrage les seuils métier publics (délai
  minimum de réservation, préavis d'annulation, fenêtre de démarrage, expiration
  d'une demande, clôture automatique, fenêtre de dépôt d'avis) et n'utiliser ses
  valeurs de repli qu'en cas d'échec de cette lecture.
- **FR-095** : L'application MUST proposer des états explicites de chargement,
  d'erreur avec action de reprise, et de liste vide avec action utile, sur chaque
  écran de liste ou de détail.
- **FR-096** : L'application MUST conserver en lecture les données consultées
  (profil, catalogue, carnet d'adresses, première page des missions, détail d'une
  mission, fils de discussion) et afficher leur date de mise à jour.
- **FR-097** : L'application MUST afficher une bannière permanente en mode hors ligne
  et rendre toute action d'écriture indisponible, sans jamais différer une action pour
  la rejouer plus tard.
- **FR-098** : L'application MUST ne conserver localement aucun contenu de fichier
  sensible (justificatifs), les contenus publics (photos de profil, réalisations)
  restant conservables.
- **FR-099** : L'application MUST rafraîchir les données de l'écran courant au retour
  du réseau.
- **FR-100** : L'application MUST permettre d'ouvrir un litige sur une mission dont
  l'utilisateur est partie, et d'en suivre l'état, sans exposer les échanges internes
  de modération.
- **FR-101** : L'application MUST présenter son interface en français, adaptée au
  contexte ivoirien (formats de date, d'heure et de montant).
- **FR-102** : L'application MUST s'identifier auprès du service par un libellé
  d'application lisible (nom, version, modèle d'appareil) afin que les sessions
  soient reconnaissables.

### Key Entities

- **Utilisateur** : identité (prénom, nom), contacts (email, téléphone) avec leur
  état de vérification, état du compte, existence et état du profil prestataire.
- **Adresse** : libellé, ville, commune, précisions, position géographique
  obligatoire, caractère « par défaut ». Rattachée à un utilisateur, limitée à 10.
- **Profil prestataire** : nom public, présentation, années d'expérience, photo,
  état de validation, état de disponibilité, note et nombre d'avis, complétude du
  dossier, motif de refus éventuel, blocage éventuel de re-soumission.
- **Catégorie et type de service** : catalogue public à deux niveaux servant aux
  filtres de recherche et à la déclaration d'une prestation.
- **Prestation (service du prestataire)** : rattachée à un type de service, titre,
  description, activation.
- **Formule** : rattachée à une prestation ; titre, description, prix, durée,
  activation. Porte les **options** (titre, prix, durée additionnelle).
- **Zone d'intervention** : zone géographique (nom, ville, centre, rayon) ; un
  prestataire en couvre au plus 15.
- **Créneau hebdomadaire** : jour de la semaine (dimanche = premier), heure de début,
  heure de fin. Au plus 50 par prestataire.
- **Absence** : période d'indisponibilité exceptionnelle avec motif facultatif.
- **Justificatif** : type exigé, fichier associé, état (en examen, validé, refusé),
  numéro de version, motif de refus.
- **Réalisation (portfolio)** : image, titre, description, ordre d'affichage ; au
  plus 20.
- **Mission** : client, prestataire, formule et options retenues, montant figé,
  durée, horaire, adresse, instructions, état courant, historique des changements
  d'état, annulation éventuelle (motif, caractère tardif).
- **Demande de report** : ancienne et nouvelle date, motif, auteur, état (demandée,
  acceptée, refusée, appliquée), décideur.
- **Avis** : note de 1 à 5, commentaire, auteur, mission concernée, état de
  modération.
- **Conversation** : rattachée à une mission, interlocuteur, état (ouverte ou
  clôturée), messages (texte, pièces jointes, auteur, date, lecture).
- **Notification** : type, titre, corps, charge utile de routage, date de lecture.
- **Appareil** : plateforme, jeton d'envoi, activité ; rattaché au compte connecté.
- **Fichier** : nom d'origine, type, taille, visibilité (publique, restreinte,
  sensible).
- **Litige** : mission concernée, motif, état, échanges visibles par les parties.
- **Réglages publics** : seuils métier lisibles par l'application (délais et
  fenêtres) pilotant les messages et les restrictions d'interface.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001** : 90 % des nouveaux utilisateurs créent leur compte, l'activent et
  arrivent sur leur écran d'accueil en moins de 3 minutes, sans aide extérieure.
- **SC-002** : 90 % des réservations menées depuis une fiche prestataire aboutissent
  en moins de 2 minutes à partir de l'appui sur « Réserver ».
- **SC-003** : Zéro réservation en double constatée sur une campagne de 100
  confirmations soumises à des coupures réseau provoquées.
- **SC-004** : 80 % des prestataires qui démarrent le parcours d'inscription
  soumettent leur dossier au cours de la même session, en moins de 15 minutes d'usage
  actif.
- **SC-005** : Le premier écran de résultats de recherche s'affiche en moins de
  2 secondes sur une connexion mobile de qualité moyenne, et un état de chargement
  explicite est visible dès la première seconde.
- **SC-006** : 100 % des refus métier rencontrés dans les parcours principaux
  affichent un message compréhensible **et** une action corrective menant à l'écran
  concerné ; aucun code technique n'est présenté à l'utilisateur.
- **SC-007** : Un utilisateur qui ouvre l'application au moins une fois par semaine
  n'a jamais à ressaisir ses identifiants pendant 7 jours, et aucun écran de
  connexion n'apparaît au milieu d'une session valide.
- **SC-008** : Hors ligne, les écrans de consultation clés (accueil des missions,
  détail d'une mission, conversation) restent affichables avec la date de leurs
  données, et 100 % des actions d'écriture sont refusées à l'entrée plutôt que mises
  en attente.
- **SC-009** : 99 % des appuis sur une notification ouvrent directement l'écran
  attendu, application au premier plan, en arrière-plan ou fermée.
- **SC-010** : Le taux de sessions sans plantage atteint au moins 99,5 %, et 100 %
  des incidents remontés portent l'identifiant de corrélation de l'appel fautif.
- **SC-011** : Un prestataire répond à une demande en attente en 3 interactions au
  plus depuis l'ouverture de l'application.
- **SC-012** : Aucune donnée d'un compte précédent n'est visible après une
  déconnexion suivie d'une connexion avec un autre compte (vérifié sur l'ensemble des
  écrans de liste et de détail).
- **SC-013** : 95 % des saisies invalides (formats, longueurs, plafonds) sont
  signalées avant l'envoi plutôt qu'après un aller-retour réseau.

## Assumptions

- **Service existant, contrat figé** : l'application consomme le service PRESTGO déjà
  en production, dont le contrat, les règles métier, les messages et les limites sont
  décrits et vérifiés dans [docs/PRESTGO-Mobile-Flutter-Cahier-des-charges.md](../../docs/PRESTGO-Mobile-Flutter-Cahier-des-charges.md).
  Aucune évolution de ce service n'est demandée par cette spécification.
- **Périmètre V1 = les deux surfaces** : la version 1 livre la surface client **et**
  la surface prestataire dans une application unique, conformément à l'ordre de
  développement recommandé au §9 du cahier des charges. Une livraison client seule
  serait un sous-ensemble valide mais n'est pas le périmètre retenu.
- **Plateformes** : téléphones Android et iOS. La plateforme « web » reconnue par le
  service d'envoi de notifications n'est pas ciblée en V1.
- **Langue et localisation** : interface en français, formats de date, d'heure et de
  montants adaptés à la Côte d'Ivoire. Les messages métier du service sont déjà
  rédigés en français à destination de l'utilisateur final.
- **Devise unique** : tous les montants sont exprimés en franc CFA (XOF) ; le service
  ne transporte pas d'information de devise, c'est une décision produit assumée.
- **Fuseau horaire** : les horaires d'agenda sont manipulés sans conversion de fuseau
  (le pays est aligné sur le temps universel) ; les dates d'intervention sont
  échangées en temps universel.
- **Réinitialisation de mot de passe par saisie manuelle** : le jeton est reçu en
  clair par email, sans lien profond ; un écran de saisie/collage est donc prévu. Si
  un domaine et une configuration de liens applicatifs sont arrêtés plus tard, un
  parcours par lien pourra s'ajouter, l'écran manuel restant le repli.
- **Pas de temps réel** : ni messagerie instantanée poussée en continu, ni suivi en
  direct de l'état d'un dossier ; les rafraîchissements sont déclenchés par
  l'ouverture d'écran, le geste de rafraîchissement, le retour au premier plan et les
  notifications reçues.
- **Hors ligne en lecture seule** : aucune file d'attente d'actions différées en V1,
  décision justifiée par le caractère fortement contextuel des écritures (créneaux,
  états de mission).
- **Tableau de bord prestataire composé** : aucun écran agrégé n'existe côté service ;
  le tableau de bord est constitué de plusieurs chargements indépendants.
- **Litiges** : le parcours V1 se limite à l'ouverture et au suivi d'un litige ; la
  richesse de l'écran sera ajustée au moment du développement, la structure des
  données étant désormais contractualisée mais non observée en conditions réelles.
- **Suppressions limitées** : ni prestation, ni formule, ni option, ni justificatif,
  ni avis, ni notification ne peuvent être supprimés ; l'interface emploie un
  vocabulaire de désactivation ou de nouvelle version.
- **Notifications facultatives** : le canal poussé est un complément ; le centre de
  notifications intégré reste le canal de référence.
- **Comptes historiques** : certains comptes antérieurs ne portent pas d'indicateur
  de profil client ; l'accès à l'espace client se fonde uniquement sur le caractère
  actif du compte.
- **Qualité réseau** : les utilisateurs disposent d'une connexion mobile
  intermittente ; les écrans doivent rester compréhensibles en réseau dégradé.
