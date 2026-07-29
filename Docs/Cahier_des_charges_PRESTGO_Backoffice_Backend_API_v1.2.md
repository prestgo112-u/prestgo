# PRESTGO — Cahier des charges Back-office Admin & Backend API

**Cahier des charges fonctionnel et technique**
Back-office Admin — Interface web de gestion — Backend API

*Document de cadrage pour conception, développement backend et administration web.*
*Projet PRESTGO — Services de prestation à la demande.*

| Champ | Valeur |
|---|---|
| **Document** | Cahier des charges Back-office Admin et Backend API |
| **Version** | 1.2 |
| **Date** | 13 juin 2026 |
| **Statut** | Version orientée backend et interface web de gestion |

---

## Sommaire

1. [Objectif et périmètre du document](#1-objectif-et-périmètre-du-document)
2. [Stack technique retenue](#2-stack-technique-retenue)
3. [Architecture backend et organisation modulaire](#3-architecture-backend-et-organisation-modulaire)
4. [Back-office Admin : interface web de gestion](#4-back-office-admin--interface-web-de-gestion)
5. [Rôles, droits et sécurité applicative](#5-rôles-droits-et-sécurité-applicative)
6. [Workflows de gestion](#6-workflows-de-gestion)
7. [Modèle de données et tables à prévoir](#7-modèle-de-données-et-tables-à-prévoir)
8. [Catalogue des API backend](#8-catalogue-des-api-backend)
9. [Règles métier hors module financier](#9-règles-métier-hors-module-financier)
10. [Exigences non fonctionnelles](#10-exigences-non-fonctionnelles)
11. [Critères d'acceptation](#11-critères-dacceptation)
12. [Roadmap de développement backend et back-office](#12-roadmap-de-développement-backend-et-back-office)

> **Orientation du document**
> Ce document ne traite que du backend, du back-office et de son interface web de gestion. Les interfaces utilisateur finales seront décrites dans un cahier des charges séparé et consommeront les endpoints du backend.

---

## 1. Objectif et périmètre du document

### 1.1 Objectif

Ce cahier des charges a pour objectif de cadrer le développement du backend PRESTGO et du back-office Admin. Il décrit les modules fonctionnels, les écrans d'administration, les tables à prévoir, les droits utilisateurs, les workflows de gestion et les endpoints API nécessaires pour construire une base technique propre et évolutive.

### 1.2 Périmètre inclus

- Backend API centralisé pour gérer les données, les règles métier, les autorisations et les opérations de la plateforme.
- Back-office web d'administration pour les équipes internes : supervision, validation, modération, support et paramétrage.
- Base de données relationnelle avec modèle clair, relations, statuts, historisation et audit.
- Gestion des utilisateurs, rôles, clients, prestataires, catégories, prestations, disponibilités, missions, avis, litiges, notifications et fichiers.
- Catalogue d'API REST versionnées, documentées et sécurisées.

### 1.3 Périmètre exclu de ce document

- Les interfaces finales destinées au grand public et aux prestataires seront traitées dans un cahier des charges séparé.
- Les intégrations financières ne sont pas traitées dans cette version du document.
- Les choix d'infrastructure, de déploiement et d'exploitation technique ne sont pas traités dans ce document.
- Les modules avancés comme abonnement premium, boutique, assurance, live vidéo et recommandations intelligentes sont exclus de la V1.

### 1.4 Principe directeur

> **Principe de conception**
> Le backend doit être construit comme le cœur unique de la plateforme. Le back-office utilise les mêmes règles métier et les mêmes entités que les futures interfaces. Les endpoints doivent donc être propres, versionnés, réutilisables, documentés et suffisamment complets pour éviter de dupliquer la logique dans les frontends.

---

## 2. Stack technique retenue

La stack ci-dessous est recommandée pour garantir une architecture propre, maintenable et adaptée à un produit de mise en relation avec recherche géographique, validation de profils, gestion de missions et administration interne.

| Couche | Choix recommandé | Rôle dans le projet |
|---|---|---|
| Backend API | Node.js + NestJS + TypeScript | Construire une API modulaire, typée, testable et maintenable. |
| Base de données | PostgreSQL + PostGIS | Stocker les données relationnelles et gérer les recherches géographiques. |
| ORM | Prisma | Modéliser les tables, générer les migrations et sécuriser l'accès aux données. |
| Cache et files de tâches | Redis + BullMQ | Gérer OTP, cache court terme, files de notification et traitements asynchrones. |
| Back-office web | React + TypeScript + Vite | Créer une interface d'administration rapide, moderne et maintenable. |
| UI Back-office | Tailwind CSS + shadcn/ui ou Material UI | Produire des écrans professionnels : tableaux, formulaires, filtres, modales. |
| Formulaires | React Hook Form + Zod | Valider les données côté interface et côté API avec des schémas cohérents. |
| Gestion de données front | TanStack Query | Charger, cacher, rafraîchir et synchroniser les données du back-office. |
| Tableaux admin | TanStack Table | Afficher les listes admin avec filtres, tri, pagination et actions de masse. |
| Documentation API | Swagger / OpenAPI | Documenter les endpoints pour l'équipe frontend et les intégrations futures. |
| Temps réel interne | WebSocket / Socket.IO si nécessaire | Afficher les nouveaux tickets, alertes ou changements de statut en temps réel. |
| Authentification | JWT access token + refresh token | Sécuriser les sessions et les appels API. |

### 2.1 Pourquoi NestJS pour le backend

- Architecture modulaire adaptée aux grands projets.
- TypeScript natif pour réduire les erreurs de typage.
- Séparation claire entre controllers, services, DTO, guards, modules et repositories.
- Support naturel de Swagger, validation, guards RBAC, WebSocket et tâches asynchrones.
- Plus robuste qu'un backend Express simple lorsque le projet grandit.

---

## 3. Architecture backend et organisation modulaire

### 3.1 Organisation recommandée des modules NestJS

| Module | Responsabilité |
|---|---|
| `AuthModule` | Inscription, connexion, OTP, refresh token, mot de passe oublié, déconnexion. |
| `UsersModule` | Gestion du compte utilisateur commun : identité, contact, statut, rôle. |
| `AdminModule` | Fonctions réservées au back-office : tableaux de bord, modération, actions sensibles. |
| `RolesModule` | Rôles, permissions, RBAC, affectation des droits. |
| `ClientsModule` | Profils clients, adresses, favoris, historique. |
| `ProvidersModule` | Profils prestataires, validation, score, statut de disponibilité. |
| `DocumentsModule` | Documents de vérification, pièces jointes, statuts, motifs de refus. |
| `CatalogModule` | Catégories, sous-catégories, prestations, packs, options. |
| `ZonesModule` | Villes, communes, zones d'intervention, coordonnées et rayon. |
| `AvailabilityModule` | Disponibilités hebdomadaires et indisponibilités exceptionnelles. |
| `MissionsModule` | Réservations, affectation, statuts, historique, annulation et reprogrammation. |
| `MessagesModule` | Conversations liées à une mission, messages, pièces jointes. |
| `ReviewsModule` | Notes, avis, modération, signalement d'avis. |
| `DisputesModule` | Litiges, tickets support, preuves, décisions, historique. |
| `NotificationsModule` | Templates, notifications système, canaux, statut d'envoi. |
| `FilesModule` | Upload, stockage logique, métadonnées, association aux entités. |
| `SettingsModule` | Paramètres fonctionnels : délais, limites, textes, seuils, options. |
| `AuditModule` | Historique des actions sensibles réalisées dans le back-office. |
| `ReportsModule` | Exports et statistiques opérationnelles hors module financier. |

### 3.2 Structure de code proposée

La structure suivante permet de séparer les domaines métier et de faciliter la maintenance :

```text
src/
  modules/
    auth/
    users/
    admin/
    roles/
    clients/
    providers/
    documents/
    catalog/
    zones/
    availability/
    missions/
    messages/
    reviews/
    disputes/
    notifications/
    files/
    settings/
    audit/
    reports/
  common/
    decorators/
    filters/
    guards/
    interceptors/
    pipes/
    utils/
  prisma/
    prisma.service.ts
    schema.prisma
```

---

## 4. Back-office Admin : interface web de gestion

Le back-office est l'interface web interne permettant aux équipes PRESTGO de contrôler la plateforme. Il doit être clair, sécurisé, rapide et orienté opérations.

### 4.1 Menu principal recommandé

| Menu | Objectif | Fonctions principales |
|---|---|---|
| Tableau de bord | Avoir une vision globale de l'activité. | KPIs, courbes, alertes, comptes en attente, missions actives, litiges ouverts. |
| Utilisateurs | Gérer tous les comptes. | Recherche, filtres, consultation, blocage, statut, historique. |
| Clients | Suivre les clients de la plateforme. | Profil, adresses, historique, avis, signalements, actions support. |
| Prestataires | Valider et suivre les professionnels. | Profil, documents, catégories, disponibilités, score, suspension. |
| Vérifications | Traiter les dossiers en attente. | Documents soumis, contrôle, validation, rejet motivé, journalisation. |
| Catalogue | Gérer l'offre de services. | Catégories, sous-catégories, packs, options, icônes, ordre d'affichage. |
| Zones | Gérer les zones couvertes. | Villes, communes, zones, rayons, activation/désactivation. |
| Missions | Superviser les demandes et prestations. | Liste, détail, statut, changement manuel, reprogrammation, historique. |
| Messages | Superviser les échanges liés aux missions. | Conversations, signalements, pièces jointes, actions support. |
| Avis | Modération de la réputation. | Avis clients, avis signalés, masquage, motifs, historique. |
| Litiges | Traiter les problèmes clients/prestataires. | Tickets, preuves, commentaires internes, décision, clôture. |
| Notifications | Piloter les messages système. | Templates, historique d'envoi, relance, statut. |
| Paramètres | Configurer les règles fonctionnelles. | Délais, limites, seuils, statuts, textes, options. |
| Audit | Tracer les actions sensibles. | Qui a fait quoi, quand, sur quelle ressource, avant/après. |
| Exports | Extraire les données opérationnelles. | CSV/Excel : comptes, prestataires, missions, litiges, avis. |

### 4.2 Écran Tableau de bord

- **Cartes statistiques** : utilisateurs actifs, prestataires validés, prestataires en attente, missions du jour, missions en cours, litiges ouverts, avis à modérer.
- **Graphiques** : inscriptions par période, missions par catégorie, missions par zone, taux d'annulation, temps moyen de validation prestataire.
- **Listes rapides** : derniers prestataires inscrits, derniers litiges, missions en retard, documents à vérifier.
- **Filtres globaux** : période, ville, catégorie, statut.

### 4.3 Écran Prestataires

- Liste avec recherche par nom, téléphone, email, catégorie, ville, statut de validation, disponibilité et score.
- Fiche détaillée : informations personnelles, profil public, services proposés, tarifs, disponibilités, documents, historique de missions, avis et litiges.
- Actions : valider, rejeter, demander correction, suspendre, réactiver, modifier une catégorie, ajouter une note interne.
- Toutes les actions sensibles doivent être historisées dans l'audit log.

### 4.4 Écran Missions

- Liste paginée avec filtres : statut, date, catégorie, ville, client, prestataire, type d'intervention.
- Détail mission : client, prestataire, prestation, lieu, date, instructions, statut actuel, historique des changements.
- Actions admin : changer un statut selon les règles autorisées, reprogrammer, annuler, ajouter une note interne, ouvrir un litige.
- Aucune action ne doit supprimer l'historique d'origine.

### 4.5 Écran Litiges

- Liste des tickets avec statut : ouvert, en analyse, attente client, attente prestataire, résolu, rejeté, clos.
- Fiche litige : mission concernée, parties impliquées, motif, description, pièces jointes, commentaires internes, décisions.
- Actions : demander une information, ajouter une preuve, affecter un agent support, prendre une décision, clôturer.
- Chaque décision doit contenir un motif et être horodatée.

---

## 5. Rôles, droits et sécurité applicative

### 5.1 Rôles internes du back-office

| Rôle | Description | Droits principaux |
|---|---|---|
| Super admin | Responsable principal de la plateforme. | Gestion des admins, paramètres sensibles, tous les modules, audit complet. |
| Admin | Responsable opérationnel. | Gestion clients, prestataires, catégories, missions, litiges, avis et exports. |
| Agent support | Équipe chargée d'assister les utilisateurs. | Lecture des comptes et missions, traitement litiges, notes internes, pas de paramètres sensibles. |
| Agent validation | Équipe chargée de vérifier les prestataires. | Lecture profils prestataires, validation/rejet documents, demande de correction. |
| Modérateur | Équipe chargée de la qualité. | Modération des avis, signalements, conversations signalées et contenus publics. |
| Lecture seule | Profil de consultation. | Accès aux tableaux et listes sans action sensible. |

### 5.2 Règles de sécurité

- Toutes les routes admin doivent vérifier le token, le rôle et les permissions.
- Les actions sensibles doivent exiger une permission explicite et être journalisées.
- Les mots de passe doivent être hashés avec un algorithme robuste.
- Les endpoints listés doivent toujours appliquer pagination, filtrage autorisé et validation des entrées.
- Les erreurs API ne doivent jamais révéler des informations sensibles.
- Les documents d'identité et fichiers sensibles doivent avoir un contrôle d'accès strict.

---

## 6. Workflows de gestion

### 6.1 Validation d'un prestataire

1. Le prestataire crée son compte et complète son profil.
2. Il renseigne sa catégorie, sa zone, sa description, ses services et ses disponibilités.
3. Il soumet les documents obligatoires.
4. Le dossier apparaît dans le back-office avec le statut **En attente**.
5. L'agent de validation consulte les informations et les documents.
6. Il valide le profil, rejette avec motif ou demande une correction.
7. En cas de validation, le prestataire devient visible dans les recherches.
8. L'action est journalisée avec l'identifiant de l'agent et la date.

### 6.2 Traitement d'un litige

1. Un client, un prestataire ou un agent ouvre un litige lié à une mission.
2. Le ticket reçoit un numéro unique et un statut **Ouvert**.
3. Le support analyse la mission, les messages, les pièces jointes et les avis.
4. Le support peut demander des informations complémentaires.
5. Une décision est saisie avec motif, preuves et action retenue.
6. Le ticket passe au statut **Résolu** puis **Clos** après vérification.
7. Toutes les étapes sont conservées dans l'historique du litige.

### 6.3 Modération d'un avis

1. Un avis est publié après une mission terminée.
2. L'avis peut être signalé ou détecté comme sensible.
3. Un modérateur consulte le contenu, le contexte et l'historique.
4. Il peut conserver, masquer ou supprimer l'avis selon les règles.
5. La décision doit être motivée et historisée.

---

## 7. Modèle de données et tables à prévoir

Les tables ci-dessous constituent une base solide pour démarrer le backend et le back-office. Les noms peuvent être adaptés au standard choisi dans le schéma Prisma, mais les entités doivent rester présentes pour couvrir les besoins métier.

| Table | Rôle | Champs principaux | Relations / remarques |
|---|---|---|---|
| `users` | Compte utilisateur commun. | `id`, `first_name`, `last_name`, `phone`, `email`, `password_hash`, `status`, `phone_verified_at`, `email_verified_at`, `created_at` | Lié aux profils, rôles et actions. |
| `roles` | Rôles système. | `id`, `code`, `name`, `description`, `is_system` | Lié à `users` via `user_roles`. |
| `permissions` | Permissions fines. | `id`, `code`, `module`, `action`, `description` | Lié à `roles` via `role_permissions`. |
| `user_roles` | Affectation rôles. | `user_id`, `role_id` | Many-to-many users/roles. |
| `role_permissions` | Affectation permissions. | `role_id`, `permission_id` | Many-to-many roles/permissions. |
| `admin_profiles` | Infos internes admin. | `user_id`, `job_title`, `department`, `is_active` | Lié à `users`. |
| `client_profiles` | Profil client. | `user_id`, `avatar_file_id`, `default_address_id`, `notes` | Lié à `users`, `addresses`. |
| `provider_profiles` | Profil prestataire. | `user_id`, `public_name`, `bio`, `experience_years`, `validation_status`, `availability_status`, `score` | Lié à `users`, `categories`, `documents`, `packs`. |
| `provider_documents` | Documents de vérification. | `id`, `provider_id`, `type`, `file_id`, `status`, `rejection_reason`, `reviewed_by`, `reviewed_at` | Lié à `provider_profiles`, `files`, `users`. |
| `provider_internal_notes` | Notes internes sur prestataire. | `id`, `provider_id`, `admin_id`, `note`, `created_at` | Visible back-office uniquement. |
| `categories` | Catégories principales. | `id`, `name`, `slug`, `description`, `icon_file_id`, `active`, `display_order` | Lié aux prestations. |
| `service_types` | Sous-services. | `id`, `category_id`, `name`, `slug`, `description`, `active` | Lié à `categories`. |
| `provider_services` | Services proposés par un prestataire. | `id`, `provider_id`, `service_type_id`, `title`, `description`, `active` | Lié à `provider_profiles` et `service_types`. |
| `service_packs` | Packs de prestation. | `id`, `provider_service_id`, `title`, `description`, `price`, `duration_minutes`, `active` | Lié à `provider_services`. |
| `service_pack_options` | Options complémentaires. | `id`, `pack_id`, `title`, `price`, `duration_minutes`, `active` | Lié à `service_packs`. |
| `provider_portfolio_items` | Portfolio prestataire. | `id`, `provider_id`, `file_id`, `title`, `description`, `display_order` | Lié à `files`. |
| `cities` | Villes. | `id`, `name`, `country_code`, `active` | Lié aux zones. |
| `zones` | Zones/communes couvertes. | `id`, `city_id`, `name`, `latitude`, `longitude`, `radius_km`, `active` | Utilise PostGIS pour la recherche. |
| `addresses` | Adresses utilisateurs. | `id`, `user_id`, `label`, `city`, `commune`, `details`, `latitude`, `longitude`, `is_default` | Lié à `users`. |
| `provider_zones` | Zones d'intervention. | `provider_id`, `zone_id` | Many-to-many prestataires/zones. |
| `provider_availabilities` | Disponibilités hebdomadaires. | `id`, `provider_id`, `weekday`, `start_time`, `end_time`, `active` | Lié à `provider_profiles`. |
| `provider_unavailabilities` | Indisponibilités exceptionnelles. | `id`, `provider_id`, `start_at`, `end_at`, `reason` | Lié à `provider_profiles`. |
| `missions` | Demande/réservation de prestation. | `id`, `client_id`, `provider_id`, `pack_id`, `scheduled_at`, `address_id`, `status`, `instructions`, `created_at` | Lié à `users`, `packs`, `status_history`. |
| `mission_status_history` | Historique des statuts. | `id`, `mission_id`, `old_status`, `new_status`, `changed_by`, `reason`, `created_at` | Lié à `missions` et `users`. |
| `mission_reschedules` | Reprogrammations. | `id`, `mission_id`, `old_date`, `new_date`, `requested_by`, `status`, `reason` | Lié à `missions`. |
| `mission_cancellations` | Annulations. | `id`, `mission_id`, `cancelled_by`, `reason`, `details`, `created_at` | Lié à `missions`. |
| `chat_threads` | Conversation liée à une mission. | `id`, `mission_id`, `status`, `created_at` | Lié à `missions`. |
| `chat_messages` | Messages. | `id`, `thread_id`, `sender_id`, `message`, `created_at`, `read_at` | Lié à `chat_threads`, `users`. |
| `chat_message_files` | Pièces jointes message. | `message_id`, `file_id` | Lié à `chat_messages`, `files`. |
| `reviews` | Avis et notes. | `id`, `mission_id`, `author_id`, `target_id`, `rating`, `comment`, `status`, `created_at` | Lié à `missions` et `users`. |
| `review_reports` | Signalements avis. | `id`, `review_id`, `reporter_id`, `reason`, `status` | Lié à `reviews`. |
| `disputes` | Litiges. | `id`, `mission_id`, `opened_by`, `reason`, `description`, `status`, `assigned_to`, `decision` | Lié à `missions`, `users`. |
| `dispute_messages` | Échanges litige. | `id`, `dispute_id`, `sender_id`, `message`, `internal_only`, `created_at` | Lié à `disputes`. |
| `dispute_files` | Preuves de litige. | `dispute_id`, `file_id` | Lié à `disputes`, `files`. |
| `notifications` | Notifications système. | `id`, `user_id`, `type`, `title`, `body`, `channel`, `status`, `created_at`, `sent_at` | Lié à `users`. |
| `notification_templates` | Modèles de notification. | `id`, `code`, `title_template`, `body_template`, `active` | Utilisé par `notifications`. |
| `files` | Métadonnées fichiers. | `id`, `owner_id`, `original_name`, `mime_type`, `size`, `storage_key`, `visibility`, `created_at` | Lié à documents, portfolio, litiges. |
| `system_settings` | Paramètres fonctionnels. | `key`, `value`, `type`, `description`, `updated_by`, `updated_at` | Paramètres back-office. |
| `audit_logs` | Journal d'audit. | `id`, `actor_id`, `action`, `entity`, `entity_id`, `old_value`, `new_value`, `ip`, `created_at` | Trace actions sensibles. |
| `export_jobs` | Demandes d'export. | `id`, `requested_by`, `type`, `filters`, `status`, `file_id`, `created_at` | Lié à `files` et `users`. |

---

## 8. Catalogue des API backend

Toutes les routes doivent être préfixées par `/api/v1`. Les listes doivent être paginées et filtrables. Les endpoints admin doivent exiger une permission spécifique. Les réponses doivent suivre un format standard : `success`, `message`, `data`, `errors`, `meta`.

| Module | Méthode | Endpoint | Objectif |
|---|---|---|---|
| Auth | `POST` | `/auth/register` | Créer un compte utilisateur. |
| Auth | `POST` | `/auth/login` | Connecter un utilisateur. |
| Auth | `POST` | `/auth/refresh` | Renouveler un access token. |
| Auth | `POST` | `/auth/logout` | Fermer la session. |
| Auth | `POST` | `/auth/forgot-password` | Demander une réinitialisation du mot de passe. |
| Auth | `POST` | `/auth/reset-password` | Réinitialiser le mot de passe. |
| Auth | `POST` | `/auth/otp/send` | Envoyer un code OTP. |
| Auth | `POST` | `/auth/otp/verify` | Vérifier un code OTP. |
| Admin Dashboard | `GET` | `/admin/dashboard/summary` | Afficher les indicateurs principaux. |
| Admin Dashboard | `GET` | `/admin/dashboard/charts` | Afficher les statistiques par période, catégorie et zone. |
| Admin Users | `GET` | `/admin/users` | Lister les utilisateurs avec filtres. |
| Admin Users | `GET` | `/admin/users/{id}` | Consulter la fiche utilisateur. |
| Admin Users | `PATCH` | `/admin/users/{id}/status` | Changer le statut d'un compte. |
| Admin Users | `POST` | `/admin/users/{id}/notes` | Ajouter une note interne. |
| Admin Roles | `GET` | `/admin/roles` | Lister les rôles. |
| Admin Roles | `POST` | `/admin/roles` | Créer un rôle. |
| Admin Roles | `PATCH` | `/admin/roles/{id}` | Modifier un rôle. |
| Admin Roles | `GET` | `/admin/permissions` | Lister les permissions. |
| Clients | `GET` | `/admin/clients` | Lister les clients. |
| Clients | `GET` | `/admin/clients/{id}` | Consulter un client. |
| Clients | `GET` | `/admin/clients/{id}/missions` | Voir l'historique d'un client. |
| Prestataires | `GET` | `/admin/providers` | Lister les prestataires. |
| Prestataires | `GET` | `/admin/providers/{id}` | Consulter la fiche prestataire. |
| Prestataires | `PATCH` | `/admin/providers/{id}` | Modifier des informations admin autorisées. |
| Prestataires | `PATCH` | `/admin/providers/{id}/status` | Suspendre, réactiver ou rejeter un prestataire. |
| Prestataires | `POST` | `/admin/providers/{id}/notes` | Ajouter une note interne prestataire. |
| Vérification | `GET` | `/admin/verifications/providers` | Lister les dossiers en attente. |
| Vérification | `GET` | `/admin/verifications/documents/{id}` | Consulter un document soumis. |
| Vérification | `POST` | `/admin/verifications/documents/{id}/approve` | Valider un document. |
| Vérification | `POST` | `/admin/verifications/documents/{id}/reject` | Rejeter un document avec motif. |
| Vérification | `POST` | `/admin/verifications/providers/{id}/approve` | Valider le profil prestataire. |
| Catalogue | `GET` | `/categories` | Lister les catégories actives. |
| Catalogue | `GET` | `/admin/categories` | Lister toutes les catégories côté admin. |
| Catalogue | `POST` | `/admin/categories` | Créer une catégorie. |
| Catalogue | `PATCH` | `/admin/categories/{id}` | Modifier une catégorie. |
| Catalogue | `DELETE` | `/admin/categories/{id}` | Désactiver une catégorie. |
| Catalogue | `POST` | `/admin/service-types` | Créer un sous-service. |
| Catalogue | `PATCH` | `/admin/service-types/{id}` | Modifier un sous-service. |
| Catalogue | `GET` | `/providers/{id}/service-packs` | Lister les packs d'un prestataire. |
| Catalogue | `POST` | `/providers/me/service-packs` | Créer un pack de prestation. |
| Catalogue | `PATCH` | `/providers/me/service-packs/{id}` | Modifier un pack. |
| Zones | `GET` | `/zones` | Lister les zones actives. |
| Zones | `GET` | `/admin/zones` | Lister les zones administrables. |
| Zones | `POST` | `/admin/zones` | Créer une zone. |
| Zones | `PATCH` | `/admin/zones/{id}` | Modifier une zone. |
| Disponibilités | `GET` | `/providers/{id}/availabilities` | Consulter les disponibilités. |
| Disponibilités | `PUT` | `/providers/me/availabilities` | Mettre à jour les disponibilités. |
| Missions | `GET` | `/admin/missions` | Lister les missions. |
| Missions | `GET` | `/admin/missions/{id}` | Consulter une mission. |
| Missions | `PATCH` | `/admin/missions/{id}/status` | Changer un statut autorisé. |
| Missions | `POST` | `/admin/missions/{id}/reschedule` | Reprogrammer une mission. |
| Missions | `POST` | `/admin/missions/{id}/cancel` | Annuler une mission avec motif. |
| Missions | `GET` | `/missions/{id}/history` | Afficher l'historique des statuts. |
| Messages | `GET` | `/admin/messages/threads` | Lister les conversations. |
| Messages | `GET` | `/admin/messages/threads/{id}` | Consulter une conversation. |
| Messages | `POST` | `/messages/threads/{id}/messages` | Envoyer un message. |
| Avis | `GET` | `/admin/reviews` | Lister les avis. |
| Avis | `PATCH` | `/admin/reviews/{id}/status` | Masquer, publier ou rejeter un avis. |
| Avis | `GET` | `/providers/{id}/reviews` | Lister les avis publics d'un prestataire. |
| Litiges | `GET` | `/admin/disputes` | Lister les litiges. |
| Litiges | `GET` | `/admin/disputes/{id}` | Consulter un litige. |
| Litiges | `POST` | `/disputes` | Ouvrir un litige. |
| Litiges | `POST` | `/admin/disputes/{id}/messages` | Ajouter un message ou commentaire. |
| Litiges | `PATCH` | `/admin/disputes/{id}/assign` | Assigner le litige à un agent. |
| Litiges | `PATCH` | `/admin/disputes/{id}/status` | Changer le statut du litige. |
| Notifications | `GET` | `/admin/notifications` | Lister les notifications. |
| Notifications | `POST` | `/admin/notifications/send` | Envoyer une notification système. |
| Notifications | `GET` | `/admin/notification-templates` | Lister les templates. |
| Notifications | `PATCH` | `/admin/notification-templates/{id}` | Modifier un template. |
| Fichiers | `POST` | `/files/upload` | Uploader un fichier. |
| Fichiers | `GET` | `/files/{id}` | Télécharger/consulter un fichier autorisé. |
| Fichiers | `DELETE` | `/files/{id}` | Désactiver un fichier. |
| Paramètres | `GET` | `/admin/settings` | Lister les paramètres. |
| Paramètres | `PATCH` | `/admin/settings/{key}` | Modifier un paramètre. |
| Audit | `GET` | `/admin/audit-logs` | Consulter les logs d'audit. |
| Exports | `POST` | `/admin/exports` | Créer une demande d'export. |
| Exports | `GET` | `/admin/exports/{id}` | Suivre une demande d'export. |

---

## 9. Règles métier hors module financier

### 9.1 Statuts utilisateur

| Statut | Description | Effet |
|---|---|---|
| `draft` | Profil commencé mais incomplet. | Accès limité aux fonctions sensibles. |
| `pending` | Compte en attente de vérification. | Visible en back-office pour action admin. |
| `active` | Compte validé. | Accès complet selon rôle. |
| `rejected` | Compte ou dossier rejeté. | Motif obligatoire et affichage selon contexte. |
| `suspended` | Compte suspendu. | Accès bloqué ou limité selon décision admin. |
| `deleted` | Compte désactivé. | Données conservées selon règles internes et obligations légales. |

### 9.2 Statuts prestataire

| Statut validation | Déclencheur | Règle |
|---|---|---|
| `profile_incomplete` | Informations ou documents manquants. | Le profil ne doit pas apparaître dans les recherches. |
| `pending_review` | Dossier soumis. | Un agent doit valider ou rejeter. |
| `approved` | Dossier conforme. | Prestataire éligible selon disponibilité et zone. |
| `changes_requested` | Correction demandée. | Prestataire doit fournir les éléments demandés. |
| `rejected` | Dossier refusé. | Motif obligatoire. |
| `suspended` | Décision admin. | Prestataire retiré des recherches. |

### 9.3 Statuts mission

| Statut | Description | Action suivante possible |
|---|---|---|
| `draft` | Demande préparée mais non confirmée. | Confirmer ou abandonner. |
| `pending_provider` | Mission en attente de décision prestataire. | Accepter, refuser, expirer. |
| `confirmed` | Mission acceptée. | Démarrer, reprogrammer, annuler. |
| `in_progress` | Mission en cours. | Terminer ou ouvrir un litige. |
| `completed` | Mission terminée. | Avis, clôture, litige si besoin. |
| `closed` | Mission archivée. | Consultation historique. |
| `cancelled` | Mission annulée. | Historique et motif obligatoires. |
| `disputed` | Mission en litige. | Traitement support. |

---

## 10. Exigences non fonctionnelles

| Sujet | Exigence |
|---|---|
| Performance API | Les listes paginées doivent répondre rapidement avec filtres et index adaptés. |
| Pagination | Toutes les listes doivent accepter `page`, `limit`, `sort` et filtres contrôlés. |
| Validation | Tous les DTO doivent valider les entrées et renvoyer des erreurs lisibles. |
| Sécurité | JWT, RBAC, rate limiting, contrôle d'accès fichiers et hashage mot de passe. |
| Audit | Validation prestataire, suspension, changement de statut, modération et paramètres doivent être tracés. |
| Logs | Les erreurs serveur doivent être journalisées avec correlation id. |
| Recherche | Les recherches par zone doivent exploiter les index géographiques. |
| Qualité API | Swagger doit être à jour et utilisable par les développeurs front. |
| Accessibilité back-office | Interface lisible, contrastes corrects, formulaires clairs et messages d'erreur explicites. |

---

## 11. Critères d'acceptation

- Un admin peut se connecter, voir son tableau de bord et accéder uniquement aux modules autorisés.
- Un super admin peut créer des rôles, affecter des permissions et gérer les utilisateurs internes.
- Un prestataire soumis apparaît dans la file de validation avec documents et informations complètes.
- Un agent peut valider, rejeter ou demander correction avec motif obligatoire.
- Les catégories, sous-services, zones et packs sont administrables depuis le back-office.
- Les missions sont consultables, filtrables et historisées avec changement de statut contrôlé.
- Les litiges peuvent être ouverts, assignés, commentés, traités et clôturés.
- Les avis peuvent être consultés et modérés avec motif.
- Les fichiers sensibles ne sont accessibles qu'aux utilisateurs autorisés.
- Chaque action sensible crée une entrée dans `audit_logs`.
- Swagger expose tous les endpoints avec méthodes, DTO, exemples et codes réponse.
- La base de données contient les tables prévues avec relations, index et contraintes essentielles.

---

## 12. Roadmap de développement backend et back-office

| Phase | Objectif | Livrables |
|---|---|---|
| **Phase 1** | Socle backend | Projet NestJS, Prisma, PostgreSQL, modules Auth, Users, Roles, Swagger. |
| **Phase 2** | Back-office minimal | Connexion admin, layout, menu, dashboard, gestion utilisateurs et rôles. |
| **Phase 3** | Catalogue et zones | Catégories, sous-services, packs, zones, disponibilités. |
| **Phase 4** | Prestataires et vérification | Profils prestataires, documents, validation, notes internes, statuts. |
| **Phase 5** | Missions | Création, affectation, statuts, historique, reprogrammation, annulation. |
| **Phase 6** | Qualité et support | Avis, litiges, messages, fichiers, notifications. |
| **Phase 7** | Audit et exports | Audit logs, exports opérationnels, critères d'acceptation, tests API. |

---

## Conclusion

Ce document doit servir de base au développement du backend et du back-office PRESTGO. Une fois cette base stable, les futures interfaces pourront consommer les endpoints existants sans recréer de logique métier côté frontend.
