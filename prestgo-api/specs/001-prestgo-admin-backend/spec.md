# Feature Specification: PRESTGO Back-office Admin and Backend Services

**Feature Branch**: `001-prestgo-admin-backend`

**Created**: 2026-06-16

**Status**: Draft

**Input**: User description: "C:\PrestGo\Docs\Cahier_des_charges_PRESTGO_Backoffice_Backend_API_v1.2.md"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Administrer la plateforme en securite (Priority: P1)

Un administrateur interne PRESTGO se connecte au back-office, consulte le tableau de bord operationnel et accede uniquement aux modules autorises par son role.

**Why this priority**: Sans acces admin securise et controle par role, aucune operation interne ne peut etre realisee de facon fiable.

**Independent Test**: Creer plusieurs profils internes avec des droits differents, se connecter avec chacun, puis verifier que les menus, donnees et actions sensibles correspondent strictement aux permissions attendues.

**Acceptance Scenarios**:

1. **Given** un utilisateur interne actif avec un role admin, **When** il se connecte, **Then** il voit le tableau de bord et les modules autorises pour son role.
2. **Given** un utilisateur lecture seule, **When** il consulte une fiche mission ou prestataire, **Then** il peut voir les informations autorisees mais ne peut pas effectuer d'action sensible.
3. **Given** un utilisateur sans permission sur les parametres sensibles, **When** il tente de modifier un parametre, **Then** l'action est refusee et aucune modification n'est appliquee.

---

### User Story 2 - Valider les prestataires (Priority: P1)

Un agent de validation traite les dossiers prestataires en attente, consulte les informations et documents soumis, puis valide, rejette ou demande une correction avec un motif clair.

**Why this priority**: La qualite et la confiance de la plateforme dependent directement de la validation controlee des prestataires avant leur visibilite publique.

**Independent Test**: Soumettre un dossier prestataire complet et un dossier incomplet, puis verifier que l'agent peut prendre une decision motivee et que le statut final determine la visibilite du prestataire.

**Acceptance Scenarios**:

1. **Given** un prestataire ayant soumis un profil complet, **When** un agent valide le dossier, **Then** le prestataire devient eligible selon sa zone, sa disponibilite et son statut.
2. **Given** un document non conforme, **When** l'agent le rejette, **Then** un motif obligatoire est enregistre et le prestataire est informe de la correction attendue.
3. **Given** une action de validation, rejet ou suspension, **When** elle est confirmee, **Then** l'action est historisee avec l'agent, la date, la ressource et le motif si applicable.

---

### User Story 3 - Superviser missions, litiges, avis et messages (Priority: P1)

Une equipe support supervise les missions, traite les litiges, modere les avis signales et consulte les conversations liees aux missions pour maintenir la qualite du service.

**Why this priority**: Les operations quotidiennes de PRESTGO reposent sur la capacite a intervenir rapidement sur les missions et incidents.

**Independent Test**: Creer une mission, ouvrir un litige, signaler un avis et verifier que chaque objet peut etre consulte, filtre, assigne, commente et cloture selon les regles.

**Acceptance Scenarios**:

1. **Given** une mission existante, **When** un admin modifie son statut, reprogramme ou annule la mission, **Then** le changement respecte les transitions autorisees et conserve l'historique complet.
2. **Given** un litige ouvert, **When** un agent ajoute une preuve, affecte le ticket et saisit une decision motivee, **Then** le ticket suit le workflow jusqu'a resolution puis cloture.
3. **Given** un avis signale, **When** un moderateur decide de le conserver, masquer ou supprimer, **Then** la decision est motivee et journalisee.

---

### User Story 4 - Gerer le catalogue, les zones et les disponibilites (Priority: P2)

Un administrateur operationnel gere les categories, sous-services, packs, options, villes, zones couvertes et disponibilites afin de structurer l'offre PRESTGO.

**Why this priority**: Le catalogue et les zones conditionnent la recherche de prestataires, l'organisation des prestations et la couverture operationnelle.

**Independent Test**: Creer une categorie active, une zone active et un pack prestataire, puis verifier qu'ils sont consultables, modifiables, desactivables et coherents avec les profils prestataires.

**Acceptance Scenarios**:

1. **Given** une categorie inactive, **When** un admin l'active et definit son ordre d'affichage, **Then** elle devient disponible pour les usages autorises.
2. **Given** une zone desactivee, **When** un admin la consulte, **Then** elle reste visible en administration mais n'est pas consideree comme couverte.

---

### User Story 5 - Auditer, parametrer, notifier et exporter (Priority: P2)

Un super admin ou un admin autorise consulte les journaux d'audit, gere les parametres fonctionnels, pilote les notifications systeme et demande des exports operationnels.

**Why this priority**: La tracabilite, la configuration et les exports permettent de piloter la plateforme et de repondre aux besoins de controle interne.

**Independent Test**: Effectuer des actions sensibles, modifier un parametre autorise, envoyer une notification et demander un export, puis verifier la tracabilite et les resultats obtenus.

**Acceptance Scenarios**:

1. **Given** une action sensible realisee, **When** un super admin consulte l'audit, **Then** il voit qui a agi, quand, sur quelle ressource et quelles valeurs ont change.
2. **Given** une demande d'export operationnel, **When** elle est lancee avec des filtres, **Then** son statut est consultable et le fichier final n'est accessible qu'aux utilisateurs autorises.

### Edge Cases

- Un utilisateur authentifie tente une action hors permission: l'action est refusee, l'evenement est tracable et aucune donnee sensible n'est exposee.
- Un dossier prestataire est incomplet: il reste non visible dans les recherches et indique les corrections attendues.
- Un admin tente de changer une mission vers un statut incoherent: la transition est refusee avec un message comprehensible.
- Un litige est cloture sans decision motivee: la cloture est refusee.
- Un fichier sensible est demande par un utilisateur non autorise: l'acces est bloque.
- Une liste contient un grand volume de donnees: elle reste paginee, filtrable et lisible.
- Une suppression logique ou desactivation concerne une entite deja utilisee: l'historique reste conserve et les relations existantes restent consultables.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Le systeme MUST permettre aux utilisateurs internes de se connecter, se deconnecter, renouveler leur session et recuperer leur acces selon un processus securise.
- **FR-002**: Le systeme MUST gerer des roles internes incluant au minimum super admin, admin, agent support, agent validation, moderateur et lecture seule.
- **FR-003**: Le systeme MUST appliquer les permissions sur chaque module, chaque action sensible et chaque acces aux fichiers sensibles.
- **FR-004**: Le back-office MUST fournir un tableau de bord avec indicateurs, alertes et listes rapides sur l'activite operationnelle.
- **FR-005**: Le systeme MUST permettre la recherche, le filtrage, la consultation et la gestion des comptes utilisateurs, clients et prestataires.
- **FR-006**: Le systeme MUST permettre a un agent autorise de valider, rejeter, suspendre, reactiver ou demander correction sur un prestataire avec motif lorsque requis.
- **FR-007**: Le systeme MUST gerer les documents de verification avec statut, motif de refus, date de revue et agent responsable.
- **FR-008**: Le systeme MUST gerer le catalogue de services, incluant categories, sous-categories, services prestataires, packs et options.
- **FR-009**: Le systeme MUST gerer les villes, communes, zones couvertes, rayons d'intervention, disponibilites hebdomadaires et indisponibilites exceptionnelles.
- **FR-010**: Le systeme MUST permettre la consultation et la supervision des missions avec historique, statuts, reprogrammation, annulation motivee et notes internes.
- **FR-011**: Le systeme MUST imposer des transitions de statut coherentes pour les utilisateurs, prestataires, missions, litiges et avis.
- **FR-012**: Le systeme MUST permettre la consultation des conversations liees aux missions, des pieces jointes et des signalements selon les permissions.
- **FR-013**: Le systeme MUST permettre la moderation des avis avec decision motivee et conservation de l'historique.
- **FR-014**: Le systeme MUST permettre l'ouverture, l'affectation, le traitement, la decision motivee, la resolution et la cloture des litiges.
- **FR-015**: Le systeme MUST gerer des notifications systeme, leurs modeles, leur historique et leur statut d'envoi.
- **FR-016**: Le systeme MUST gerer les fichiers et leurs metadonnees avec controle d'acces strict selon sensibilite, proprietaire et entite associee.
- **FR-017**: Le systeme MUST permettre la consultation et la modification controlee des parametres fonctionnels par les roles autorises.
- **FR-018**: Le systeme MUST journaliser les actions sensibles avec acteur, action, entite, identifiant de ressource, valeurs avant/apres lorsque pertinent, adresse d'origine et date.
- **FR-019**: Le systeme MUST permettre des exports operationnels filtres pour les comptes, prestataires, missions, litiges, avis et autres donnees autorisees.
- **FR-020**: Le systeme MUST exposer des contrats d'echange versionnes, documentes, securises et reutilisables par les futures interfaces publiques et prestataires.
- **FR-021**: Toutes les listes administratives MUST supporter pagination, tri et filtres controles.
- **FR-022**: Toutes les saisies MUST etre validees et retourner des erreurs comprehensibles sans reveler d'information sensible.
- **FR-023**: Le systeme MUST conserver les historiques metier necessaires pour missions, statuts, validations, litiges, moderation et actions sensibles.
- **FR-024**: Le perimetre V1 MUST exclure les integrations financieres, abonnements premium, boutique, assurance, live video et recommandations intelligentes.

### Key Entities *(include if feature involves data)*

- **Utilisateur**: Compte commun portant identite, contacts, statut, verification et roles associes.
- **Role et permission**: Droits internes permettant de controler l'acces aux modules et actions.
- **Profil admin**: Informations internes d'un utilisateur membre de l'equipe PRESTGO.
- **Profil client**: Informations client, adresses, favoris, historique et notes support.
- **Profil prestataire**: Identite publique, categorie, zones, disponibilite, statut de validation, score et historique.
- **Document prestataire**: Piece de verification avec statut, fichier associe, motif de refus et revue par agent.
- **Catalogue**: Categories, sous-services, services prestataires, packs et options de prestation.
- **Zone et adresse**: Ville, commune, coordonnees, rayon, zone d'intervention et adresse utilisateur.
- **Disponibilite**: Plages hebdomadaires et indisponibilites exceptionnelles d'un prestataire.
- **Mission**: Demande ou reservation de prestation avec client, prestataire, service, lieu, date, statut et instructions.
- **Historique de mission**: Changements de statut, reprogrammations, annulations et motifs.
- **Conversation et message**: Echanges lies a une mission, pieces jointes et etat de lecture.
- **Avis et signalement**: Note, commentaire, statut de moderation et motif de signalement.
- **Litige**: Ticket lie a une mission, parties impliquees, statut, preuves, messages, decision et agent assigne.
- **Notification**: Message systeme, modele, canal, destinataire, statut et date d'envoi.
- **Fichier**: Metadonnees de documents et pieces jointes avec visibilite et controle d'acces.
- **Parametre fonctionnel**: Valeur configurable, type, description et derniere modification.
- **Audit log**: Trace des actions sensibles et changements importants.
- **Export operationnel**: Demande d'extraction, filtres, statut et fichier produit.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% des actions sensibles realisees dans le back-office generent une entree d'audit consultable par un super admin.
- **SC-002**: 100% des modules admin refusent les actions non autorisees selon le role et les permissions de l'utilisateur connecte.
- **SC-003**: Un agent de validation peut traiter un dossier prestataire complet en moins de 5 minutes, decision et motif inclus lorsque requis.
- **SC-004**: Un agent support peut retrouver une mission, son historique et ses informations associees en moins de 2 minutes avec les filtres prevus.
- **SC-005**: 95% des listes administratives courantes affichent les resultats filtres en moins de 2 secondes pour un volume operationnel normal.
- **SC-006**: 100% des rejets de document, suspensions, annulations, decisions de litige et moderations d'avis imposent un motif avant confirmation.
- **SC-007**: 100% des fichiers marques sensibles sont inaccessibles aux utilisateurs sans permission explicite.
- **SC-008**: Les equipes internes peuvent realiser les parcours critiques admin, validation prestataire, supervision mission, traitement litige et moderation avis sans intervention technique.

## Assumptions

- Le cahier des charges Markdown version 1.2 du 13 juin 2026 est la source de reference pour cette specification initiale.
- La V1 cible le backend centralise et le back-office interne; les interfaces publiques client et prestataire sont hors perimetre de cette specification.
- Les integrations financieres et modules avances mentionnes comme exclus restent hors perimetre de la V1.
- Les futurs frontends consommeront les memes regles metier et les memes donnees que le back-office, afin d'eviter la duplication de logique.
- Les roles listes dans le document sont suffisants pour demarrer; des permissions fines pourront completer chaque role sans changer le perimetre metier.
- Les donnees sensibles, documents d'identite et pieces jointes doivent etre traitees selon des pratiques de confidentialite strictes et avec acces limite aux utilisateurs autorises.
