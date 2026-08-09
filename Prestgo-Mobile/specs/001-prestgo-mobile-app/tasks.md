---

description: "Task list for PRESTGO mobile app implementation"
---

# Tasks: Application mobile PRESTGO (client + prestataire)

**Input**: Design documents from `/specs/001-prestgo-mobile-app/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Les tâches de test sont **incluses** — la porte G7 du plan et la décision
R12 de la recherche imposent que chaque dépôt soit couvert par un test rejouant les
captures JSON réelles du cahier des charges. Les fixtures viennent de
[docs/PRESTGO-Mobile-Flutter-Cahier-des-charges.md](../../docs/PRESTGO-Mobile-Flutter-Cahier-des-charges.md).

**Organization**: Tâches groupées par récit utilisateur pour permettre une
implémentation et une validation indépendantes.

## Format: `[ID] [P?] [Story] Description`

- **[P]** : parallélisable (fichiers différents, aucune dépendance sur une tâche en cours)
- **[Story]** : récit utilisateur concerné (US1 à US10)
- Chemins de fichiers exacts inclus dans chaque description

## Path Conventions

Paquet Flutter unique à la racine du dépôt (voir *Structure Decision* du plan) :
`lib/core/`, `lib/features/<domaine>/{data,domain,presentation}/`, `lib/app/`,
`test/`, `integration_test/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Création du projet Flutter et de son outillage

- [X] T001 Créer le projet Flutter à la racine (`flutter create --org test.prestgo --project-name prestgo_mobile --platforms android,ios .`) et vérifier que `docs/` et `specs/` restent intacts
- [X] T002 Déclarer les dépendances du plan (riverpod, dio, go_router, flutter_secure_storage, freezed, json_serializable, firebase_core/messaging, flutter_local_notifications, uuid, intl, connectivity_plus, drift, geolocator, flutter_map, latlong2, image_picker, file_picker, flutter_image_compress, cached_network_image, sentry_flutter) dans `pubspec.yaml`, avec `environment: sdk: ^3.10.0`
- [X] T003 [P] Configurer les lints stricts et la **règle de frontière d'import** entre `features/*` (porte G5) dans `analysis_options.yaml`
- [X] T004 [P] Configurer la génération de code (freezed, json_serializable, riverpod_generator, drift) dans `build.yaml`
- [X] T005 [P] Créer les fichiers d'environnement `env/dev.json`, `env/staging.json`, `env/prod.json` (base d'API contenant déjà `/api/v1`, activation Sentry, journaux réseau) et les référencer dans `.gitignore` si nécessaire
- [X] T006 [P] Configurer la localisation française dans `l10n.yaml` et créer `lib/l10n/app_fr.arb`
- [X] T007 Créer l'arborescence de modules vide `lib/app/`, `lib/core/`, `lib/features/`, `lib/shared/` conformément au plan
- [X] T008 [P] Créer l'arborescence de tests `test/unit/`, `test/contract/`, `test/widget/`, `test/fixtures/`, `integration_test/flows/`
- [X] T009 [P] Configurer Android dans `android/app/build.gradle.kts` et `android/app/src/main/AndroidManifest.xml` : `minSdk 26`, saveurs `dev`/`staging`/`prod`, trafic en clair **limité à `dev`**, permissions (internet, notifications, localisation, appareil photo)
- [X] T010 [P] Configurer iOS dans `ios/Runner/Info.plist` et `ios/Podfile` : cible iOS 14, exception ATS **limitée au domaine de développement**, descriptions d'usage (localisation, photothèque, appareil photo, notifications)
- [X] T011 [P] Créer le script d'intégration continue (`flutter analyze` + `flutter test`) dans `.github/workflows/ci.yml`
- [X] T012 [P] Initialiser Sentry conditionné par l'environnement (désactivé en `dev`) dans `lib/core/error/sentry_bootstrap.dart`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Socle L0 — enveloppe unique, session, cache, formats, routeur. Rien de
ce qui suit ne peut démarrer sans cette phase.

**⚠️ CRITICAL**: Aucun travail de récit utilisateur ne commence avant la fin de cette phase.

- [X] T013 [P] Implémenter `ApiEnvelope<T>`, `ApiErrorDetail`, `ApiMeta` (+ `hasMore`) dans `lib/core/api/api_envelope.dart` selon [contracts/api-envelope.md](./contracts/api-envelope.md)
- [X] T014 [P] Implémenter `ApiException` (prédicats `isUserFixable`/`isAuth`/`isForbidden`/`isNotFound`/`isRateLimited`/`isServer`, `messageForField`) dans `lib/core/api/api_exception.dart`
- [X] T015 Implémenter `EnvelopeInterceptor` (conversion unique erreur → `ApiException`, messages de repli réseau/429/5xx) dans `lib/core/api/envelope_interceptor.dart`
- [X] T016 [P] Implémenter `SecureTokenStore` (écriture **atomique** des deux jetons, lecture, purge) dans `lib/core/session/secure_token_store.dart`
- [X] T017 Implémenter `AuthInterceptor` (`QueuedInterceptor`, un seul renouvellement en vol, rejeu unique par marqueur, exclusion des routes publiques, instance de renouvellement séparée, rotation du jeton) dans `lib/core/api/auth_interceptor.dart`
- [X] T018 [P] Implémenter la politique de rejeu par type de requête dans `lib/core/api/retry_policy.dart` selon [contracts/retry-and-idempotency.md](./contracts/retry-and-idempotency.md)
- [X] T019 [P] Implémenter la génération et le cycle de vie de la clé d'idempotence dans `lib/core/api/idempotency.dart`
- [X] T020 Configurer l'instance HTTP (base d'API de l'environnement **sans re-préfixer** `/api/v1`, `User-Agent` applicatif lisible, délais) dans `lib/core/api/api_client.dart`
- [X] T021 Exposer `apiClientProvider` et `refreshDioProvider` (instance **sans** `AuthInterceptor`) dans `lib/core/api/api_providers.dart`
- [X] T022 [P] Implémenter la lecture de configuration d'environnement dans `lib/core/config/app_environment.dart`
- [X] T023 [P] Centraliser tous les plafonds de saisie et constantes dans `lib/core/settings/app_constants.dart` selon [contracts/settings-and-limits.md](./contracts/settings-and-limits.md)
- [X] T024 [P] Créer le modèle `PublicSettings` (6 seuils + valeurs de repli) dans `lib/core/settings/public_settings.dart`
- [X] T025 Implémenter `SettingsRepository` + provider mémoire (`GET /settings/public` au démarrage, repli si échec) dans `lib/core/settings/settings_repository.dart`
- [X] T026 [P] Définir le schéma de base locale (tables de cache : profil, catalogue, zones, adresses, missions, détail, messages, avec `fetchedAt`) dans `lib/core/cache/local_database.dart`
- [X] T027 [P] Implémenter l'utilitaire « servir le cache puis revalider » dans `lib/core/cache/stale_while_revalidate.dart`
- [X] T028 Implémenter les accesseurs de cache (écriture, lecture, invalidation par entité, **purge globale**) dans `lib/core/cache/cache_dao.dart`
- [X] T029 [P] Implémenter la détection de connectivité et le verrou d'écriture hors ligne dans `lib/core/connectivity/offline_gate.dart`
- [X] T030 [P] Implémenter le formateur monétaire unique XOF (locale `fr_CI`, sans décimale) dans `lib/core/format/money.dart`
- [X] T031 [P] Implémenter les utilitaires de date (conversion **UTC** pour les missions, `HH:MM` traité comme chaîne **sans conversion de fuseau**) dans `lib/core/format/datetime.dart`
- [X] T032 [P] Implémenter les validateurs de saisie (mot de passe, téléphone, email, longueurs, plafonds) dans `lib/core/validation/validators.dart`
- [X] T033 [P] Implémenter `ErrorReporter` attachant le `correlationId` en étiquette à chaque incident dans `lib/core/error/error_reporter.dart`
- [X] T034 [P] Créer les composants d'état partagés (chargement, erreur + reprise, vide + action, bannière hors ligne) dans `lib/core/widgets/`
- [X] T035 [P] Implémenter la base de liste paginée (`page`/`limit`/`total`, `loadMore`) dans `lib/core/pagination/paged_notifier.dart`
- [X] T036 Implémenter `FileUploadService` (filtrage type et taille **avant** envoi, compression d'image, champ multipart `file`, exclusion du rejeu automatique) dans `lib/core/files/file_upload_service.dart`
- [X] T037 [P] Créer le modèle `FileRef` et le composant d'affichage d'image (public sans jeton, protégé avec jeton) dans `lib/core/files/`
- [X] T038 Implémenter `SessionController` (état de session, purge du stockage sécurisé **et** de la base locale, recréation du conteneur d'état) dans `lib/core/session/session_controller.dart`
- [X] T039 Créer le squelette de routeur et le **gardien unique** (authentification + aiguillage par rôle, mémorisation de la route d'origine) dans `lib/app/router.dart` et `lib/app/routes.dart` selon [contracts/navigation-routes.md](./contracts/navigation-routes.md)
- [X] T040 [P] Créer le thème de l'application dans `lib/app/theme/app_theme.dart`
- [X] T041 Implémenter l'amorçage (`lib/main.dart`, `lib/bootstrap.dart`, `lib/app/app.dart`) : Sentry, `ProviderScope`, lecture des réglages publics, restauration de session
- [X] T042 [P] Ajouter les libellés communs (états vides, erreurs, actions) dans `lib/l10n/app_fr.arb`
- [X] T043 [P] Test de contrat : décodage des **trois formes** de `data` (objet, tableau, objet structuré) dans `test/contract/api_envelope_test.dart`
- [X] T044 [P] Test unitaire : conversion d'erreur → `ApiException`, messages de repli, `messageForField`, `correlationId` dans `test/unit/api_exception_test.dart`
- [X] T045 [P] Test unitaire : `AuthInterceptor` — un seul renouvellement pour N requêtes concurrentes, rotation enregistrée, rejeu unique, routes publiques exclues, échec → purge dans `test/unit/auth_interceptor_test.dart`
- [X] T046 [P] Test unitaire : matrice de la politique de rejeu (lectures, écritures idempotentes, transitions jamais rejouées, 429) dans `test/unit/retry_policy_test.dart`
- [X] T047 [P] Test unitaire : cycle de vie de la clé d'idempotence (stable sur contenu identique, renouvelée sur changement) dans `test/unit/idempotency_test.dart`
- [X] T048 [P] Test unitaire : validateurs de saisie dans `test/unit/validators_test.dart`
- [X] T049 [P] Test unitaire : formateur XOF et utilitaires de date (UTC, `HH:MM` non converti) dans `test/unit/format_test.dart`
- [X] T050 [P] Test unitaire : réglages publics — valeurs serveur prioritaires, repli si échec dans `test/unit/public_settings_test.dart`
- [X] T051 [P] Tests de widgets des composants d'état partagés dans `test/widget/shared_states_test.dart`
- [X] T052 Vérifier `flutter analyze` sans avertissement, règle de frontière d'import active, et exécuter `dart run build_runner build --delete-conflicting-outputs`

**Checkpoint**: Socle prêt — les récits utilisateur peuvent démarrer

---

## Phase 3: User Story 1 - Créer un compte et accéder à l'application (Priority: P1) 🎯 MVP

**Goal**: Inscription, activation par code, connexion (mot de passe ou téléphone),
session persistante, aiguillage par rôle, mot de passe oublié, déconnexion,
désactivation de compte, gestion du profil.

**Independent Test**: Créer un compte neuf, l'activer, se connecter, fermer et rouvrir
l'application, se déconnecter, réinitialiser le mot de passe, se reconnecter —
scénarios 1.1 à 1.10 de [quickstart.md](./quickstart.md).

### Tests for User Story 1

- [X] T053 [P] [US1] Copier les captures JSON réelles (register, otp/send, otp/verify, login, refresh, logout, me, patch me, delete me) dans `test/fixtures/auth/` — un fichier par opération, chaque cas nommé (`created`, `duplicate`, `rateLimited`…), relevé sur `prestgo-main`
- [X] T054 [P] [US1] Test de contrat inscription (201 statut `pending`, 400 validations, 409 doublon, 429) dans `test/contract/auth_register_test.dart`
- [X] T055 [P] [US1] Test de contrat code de vérification (200 avec `expiresInMinutes`, `activated` vrai/faux, 400 message unique, 401 après 5 tentatives) dans `test/contract/auth_otp_test.dart`
- [X] T056 [P] [US1] Test de contrat connexion (200 jetons, 401 identifiants invalides, 401 compte non actif, 429) dans `test/contract/auth_login_test.dart`
- [X] T057 [P] [US1] Test de contrat connexion par téléphone (`purpose: login` → **couple de jetons**, pas `{verified, activated}`) dans `test/contract/auth_phone_login_test.dart`
- [X] T058 [P] [US1] Test de contrat mot de passe oublié / réinitialisation (message neutre systématique, 400 jeton invalide ou expiré) dans `test/contract/auth_password_reset_test.dart`
- [X] T059 [P] [US1] Test de contrat profil (`GET /me`, `PATCH /me` avec `pendingVerifications`, `POST /me/password`, `DELETE /me` avec message chiffré de blocage) dans `test/contract/me_repository_test.dart`

### Implementation for User Story 1

- [X] T060 [P] [US1] Créer les DTO d'authentification (inscription, code, connexion, réinitialisation) dans `lib/features/auth/data/dto/`
- [X] T061 [P] [US1] Créer les modèles `Me`, `UserStatus`, `ProviderValidationStatus`, `PendingVerification` dans `lib/features/profile/domain/`
- [X] T062 [US1] Implémenter `AuthRepository` (opérations 1 à 8 de [contracts/api-consumption.md](./contracts/api-consumption.md)) dans `lib/features/auth/data/auth_repository.dart`
- [X] T063 [US1] Implémenter `MeRepository` (opérations 9 à 12) dans `lib/features/profile/data/me_repository.dart`
- [X] T064 [US1] Implémenter la restauration de session et la séquence de démarrage (jetons → `GET /me` → aiguillage) dans `lib/bootstrap.dart` et `lib/core/session/session_controller.dart`
- [X] T065 [US1] Implémenter la table d'aiguillage par rôle (7 branches de `providerValidationStatus`, `roles` **jamais** utilisé) dans `lib/app/router.dart`
- [X] T066 [P] [US1] Écrans d'inscription C1 (choix du canal), C2 (identité) et C3 (mot de passe + confirmation locale) dans `lib/features/auth/presentation/register/`
- [X] T067 [US1] Écran de vérification C4 (6 chiffres, compte à rebours sur `expiresInMinutes`, renvoi limité à 1/minute, saisie désactivée après 5 échecs) dans `lib/features/auth/presentation/verify/verify_screen.dart`
- [X] T068 [US1] Écran de transition C5 — connexion automatique après activation dans `lib/features/auth/presentation/verify/auto_login_screen.dart`
- [X] T069 [P] [US1] Écran de connexion email + mot de passe (message unique non discriminant) dans `lib/features/auth/presentation/login/login_screen.dart`
- [X] T070 [US1] Écran de connexion par téléphone (`purpose: login` toujours renseigné) dans `lib/features/auth/presentation/login/phone_login_screen.dart`
- [X] T071 [P] [US1] Écran « mot de passe oublié » (message neutre, navigation systématique vers la saisie du jeton) dans `lib/features/auth/presentation/password/forgot_password_screen.dart`
- [X] T072 [US1] Écran de réinitialisation (champ large + bouton « Coller », purge et retour à la connexion après succès) dans `lib/features/auth/presentation/password/reset_password_screen.dart`
- [X] T073 [US1] Séquence de déconnexion (désenregistrement d'appareil → fermeture de session → purge → `/login`, étapes réseau au mieux) dans `lib/features/auth/presentation/logout_controller.dart`
- [X] T074 [US1] Écran de désactivation de compte (double confirmation, saisie du mot de passe, vocabulaire « Désactiver », message serveur affiché tel quel) dans `lib/features/profile/presentation/deactivate_account_screen.dart`
- [X] T075 [P] [US1] Écran de profil (identité, contacts avec pastille « non vérifié », ancienneté, entrée espace prestataire) dans `lib/features/profile/presentation/profile_screen.dart`
- [X] T076 [US1] Édition du profil avec enchaînement automatique vers la vérification si `pendingVerifications` est non vide (mapping `sms` → `phone_verification`) dans `lib/features/profile/presentation/profile_edit_screen.dart`
- [X] T077 [US1] Écran de changement de mot de passe (session conservée, message serveur avec le nombre de sessions fermées) dans `lib/features/profile/presentation/change_password_screen.dart`
- [X] T078 [US1] Bascule explicite entre espace client et espace prestataire (sans reconnexion) dans `lib/features/profile/presentation/role_switch.dart`
- [X] T079 [US1] Traitement du dépassement de débit sur les écrans d'authentification (message d'attente + désactivation temporaire, aucun rejeu) dans `lib/features/auth/presentation/rate_limit_handler.dart`
- [X] T080 [US1] Mettre `Me` en cache persistant pour permettre l'aiguillage au démarrage hors ligne dans `lib/features/profile/data/me_repository.dart`
- [X] T081 [P] [US1] Tests de widgets des écrans d'authentification clés (code, connexion, réinitialisation) dans `test/widget/auth_screens_test.dart`
- [X] T082 [US1] Test d'intégration du parcours US1 (scénarios 1.1 à 1.10) dans `integration_test/flows/us1_account_flow_test.dart` — scénarios dans `us1_account_flow.dart`, déroulés par deux points d'entrée : sur appareil, et sans appareil via `test/flows/us1_account_flow_test.dart` (le seul que `flutter test` atteint, donc l'intégration continue)

**Checkpoint**: US1 pleinement fonctionnel et testable seul — **MVP livrable**

> **Corrigé en cours de phase** — `authInterceptorProvider` lisait `apiDioProvider`,
> qui l'observait : Riverpod y voit une dépendance circulaire et `Ref.read` la refuse.
> Le défaut ne se manifestait qu'au premier renouvellement de session, déguisé en
> « erreur réseau », et aucun test d'intercepteur ne pouvait le voir puisqu'ils
> construisent l'intercepteur à la main. Le provider a été supprimé au profit de
> `buildAuthenticatedDio`, qui construit l'instance et son intercepteur ensemble ;
> `test/unit/api_providers_test.dart` verrouille le câblage.
>
> Deux ajouts au socle, imposés par des routes de cette phase :
> `kSkipRefreshExtra` (`POST /me/password` et `DELETE /me` répondent **401 sur un mot
> de passe erroné** — sans ce marqueur, une faute de frappe déconnectait) et
> `lib/core/forms/form_submission.dart` (états d'envoi partagés par tous les
> formulaires).

---

## Phase 4: User Story 2 - Trouver un prestataire et réserver (Priority: P1)

**Goal**: Recherche publique, fiche prestataire, carnet d'adresses géolocalisées,
favoris, composition et confirmation d'une réservation protégée contre les doublons.

**Independent Test**: Depuis un compte client avec une adresse géolocalisée, chercher,
ouvrir une fiche, réserver un créneau valide et retrouver la mission — scénarios 2.1 à
2.10 de [quickstart.md](./quickstart.md).

### Tests for User Story 2

- [X] T083 [P] [US2] Copier les captures JSON (categories, zones, search, fiche publique, addresses, POST /missions) dans `test/fixtures/booking/`
- [X] T084 [P] [US2] Test de contrat catalogue (`/categories`, `/zones`, `/zones/nearby` — non paginés) dans `test/contract/catalog_repository_test.dart`
- [X] T085 [P] [US2] Test de contrat recherche (paramètres, pagination `limit ≤ 50`, 400 « tri distance sans position », 400 « date sans heure ») dans `test/contract/search_repository_test.dart`
- [X] T086 [P] [US2] Test de contrat fiche publique (sections complètes en un appel, 404 non approuvé) dans `test/contract/provider_public_test.dart`
- [X] T087 [P] [US2] Test de contrat carnet d'adresses (création, plafond 10, `default` renvoyant la liste, suppression aux **deux** formes de réponse) dans `test/contract/address_repository_test.dart`
- [X] T088 [P] [US2] Test de contrat réservation (201, 200 « déjà enregistrée », 409 « en cours de traitement », tous les 400 métier, 429) dans `test/contract/booking_repository_test.dart`
- [X] T089 [P] [US2] Test unitaire des calculs de réservation (prix total, durée totale, créneau contenant entièrement la durée, délai minimum) dans `test/unit/booking_rules_test.dart`

### Implementation for User Story 2

- [X] T090 [P] [US2] Modèles `Category`, `ServiceType`, `Zone` dans `lib/features/search/domain/`
- [X] T091 [P] [US2] Modèles `ProviderSearchResult` et `ProviderSearchQuery` dans `lib/features/search/domain/`
- [X] T092 [P] [US2] Modèles de fiche publique (`ProviderPublicProfile`, `PublicService`, `ServicePack`, `PackOption`, `WeeklySlot`, `Unavailability`) dans `lib/features/search/domain/`
- [X] T093 [P] [US2] Modèle `Address` dans `lib/features/profile/domain/address.dart`
- [X] T094 [US2] `CatalogRepository` avec cache persistant 24 h dans `lib/features/search/data/catalog_repository.dart`
- [X] T095 [US2] `SearchRepository` (cache **mémoire seulement**) dans `lib/features/search/data/search_repository.dart`
- [X] T096 [US2] `AddressRepository` (opérations 13 à 17) dans `lib/features/profile/data/address_repository.dart`
- [X] T097 [US2] `BookingRepository` avec en-tête `Idempotency-Key` dans `lib/features/booking/data/booking_repository.dart`
- [X] T098 [US2] Écran de recherche avec défilement continu sur `meta` dans `lib/features/search/presentation/search_screen.dart`
- [X] T099 [US2] Panneau de filtres (catégorie/type, position et rayon 1–50, **date et heure liées**, note minimale, tri avec « distance » indisponible sans position) dans `lib/features/search/presentation/search_filters.dart`
- [X] T100 [US2] Carte de résultat (« Nouveau » si aucun avis, distance masquée si absente, prix d'appel masqué si absent) dans `lib/features/search/presentation/widgets/provider_card.dart`
- [X] T101 [US2] États de la recherche (chargement, erreur, vide avec « Élargir le rayon » et « Retirer les filtres ») dans `lib/features/search/presentation/search_states.dart`
- [X] T102 [US2] Écran de fiche prestataire en **un seul chargement** (en-tête, présentation, prestations et tarifs, options, réalisations, agenda, zones, répartition des notes, derniers avis) dans `lib/features/search/presentation/provider_profile_screen.dart`
- [X] T103 [US2] Écran « tous les avis » paginé (`data` = tableau) dans `lib/features/search/presentation/provider_reviews_screen.dart`
- [X] T104 [US2] `FavoritesRepository` + action cœur idempotente avec garde « mon propre compte » dans `lib/features/profile/data/favorites_repository.dart`
- [X] T105 [US2] Écran des favoris (prestataires non réservables grisés, jamais masqués) dans `lib/features/profile/presentation/favorites_screen.dart`
- [X] T106 [P] [US2] Écran du carnet d'adresses (adresse par défaut en tête, état vide incitatif) dans `lib/features/profile/presentation/addresses_screen.dart`
- [X] T107 [US2] Formulaire d'adresse avec **sélecteur de position** (position courante + ajustement du marqueur sur carte, repli sur Abidjan si permission refusée) dans `lib/features/profile/presentation/address_form_screen.dart`
- [X] T108 [US2] Action « définir par défaut » (alimenter la liste avec la réponse) et blocage de l'ajout au plafond de 10 dans `lib/features/profile/presentation/addresses_screen.dart`
- [X] T109 [US2] Suppression d'adresse gérant les deux issues (retrait réel / archivage avec motif) dans `lib/features/profile/presentation/addresses_screen.dart`
- [X] T110 [US2] État de brouillon de réservation et **cycle de vie de la clé d'idempotence** (générée à l'affichage du récapitulatif, renouvelée à tout changement de contenu, jamais dans une méthode de construction) dans `lib/features/booking/presentation/booking_draft_controller.dart`
- [X] T111 [US2] Écran de choix formule et options avec prix et durée recalculés en direct dans `lib/features/booking/presentation/pack_selection_screen.dart`
- [X] T112 [US2] Sélecteur de date et d'heure restreint par l'agenda hebdomadaire, les absences, la durée totale et le délai minimum en vigueur, envoi en **UTC** dans `lib/features/booking/presentation/schedule_picker_screen.dart`
- [X] T113 [US2] Étape de choix d'adresse (adresse par défaut présélectionnée, renvoi vers la création si le carnet est vide) dans `lib/features/booking/presentation/address_step.dart`
- [X] T114 [US2] Étape instructions (compteur 500 caractères) dans `lib/features/booking/presentation/instructions_step.dart`
- [X] T115 [US2] Écran récapitulatif et confirmation appliquant la **séquence exacte de rejeu** de [contracts/retry-and-idempotency.md](./contracts/retry-and-idempotency.md) dans `lib/features/booking/presentation/booking_summary_screen.dart`
- [X] T116 [US2] Correspondance erreur → étape corrigeable (zone hors couverture avec zones affichées, créneau pris, adresse non géolocalisée, option inconnue) en conservant le brouillon dans `lib/features/booking/presentation/booking_error_mapper.dart`
- [X] T117 [US2] Mur d'authentification avec retour sur la route d'origine après connexion dans `lib/app/router.dart`
- [X] T118 [P] [US2] Tests de widgets (états de recherche, récapitulatif de réservation) dans `test/widget/booking_screens_test.dart`
- [X] T119 [US2] Test d'intégration du parcours US2 (scénarios 2.1 à 2.10, dont la coupure réseau sans doublon) dans `integration_test/flows/us2_booking_flow_test.dart` — scénarios dans `us2_booking_flow.dart`, deux points d'entrée comme pour US1

**Checkpoint**: Boucle de valeur complète — chercher → réserver

> **Corrigés en cours de phase** — trois défauts, tous sortis par le test d'intégration :
>
> 1. **`/providers` classé comme `/provider`.** `Routes.isProviderSpace` comparait des
>    chaînes brutes : `'/providers/p-1'.startsWith('/provider')` vaut `true`. Tout
>    client connecté ouvrant une fiche publique était renvoyé à son accueil. La
>    comparaison se fait désormais sur les **segments** de chemin.
> 2. **Route mémorisée perdue après connexion.** Le mur d'authentification empilait
>    l'écran de connexion (`push`) au-dessus d'une route publique ; le gardien
>    continuait d'évaluer la route de base et la détournait dès l'ouverture de session,
>    emportant l'écran empilé. Le mur remplace maintenant la pile (`go`), le gardien
>    laisse les écrans d'authentification en place le temps du chargement du profil, et
>    c'est **lui** qui lit `?from=` — le seul endroit qui survive au démontage.
> 3. **`openSession` rendait la main avant le profil.** `read(…future)` juste après
>    `invalidate` pouvait rendre le futur précédent ; l'appelant naviguait sur un
>    profil encore nul et le gardien le détournait vers l'atterrissage. Le chargement
>    est désormais explicite.
>
> Deux ajouts au socle : `ApiEnvelope.isCreated` (distinguer 201 « créée » de 200
> « déjà enregistrée » sans exposer de code HTTP, porte G2) et
> `lib/core/location/location_service.dart` (position, avec repli sur Abidjan).

---

## Phase 5: User Story 3 - Suivre et gérer mes réservations (Priority: P2)

**Goal**: Listes par onglets, détail, frise chronologique, annulation avec
avertissement de tardiveté, reports, ouverture de litige.

**Independent Test**: Sur un compte client avec au moins une mission, parcourir les
onglets, ouvrir un détail, annuler, proposer un report — scénarios 3.1 à 3.5.

### Tests for User Story 3

- [X] T120 [P] [US3] Copier les captures JSON (liste, détail, historique, annulation, reports) dans `test/fixtures/missions/`
- [X] T121 [P] [US3] Test de contrat listes et détail (filtre `status` **multi-valeurs**, `to` inclusif, tri par défaut, 403 non partie) dans `test/contract/mission_repository_test.dart`
- [X] T122 [P] [US3] Test de contrat annulation (`late` vrai/faux, transition invalide, motif obligatoire) dans `test/contract/mission_cancel_test.dart`
- [X] T123 [P] [US3] Test de contrat reports (proposition, une seule en attente, acceptation revalidée, 403 sur sa propre demande) dans `test/contract/reschedule_repository_test.dart`

### Implementation for User Story 3

- [X] T124 [P] [US3] Modèles `MissionListItem`, `MissionDetail`, `MissionHistoryEntry`, `Cancellation`, `RescheduleRequest` dans `lib/features/missions/domain/`
- [X] T125 [US3] `MissionRepository` côté client (opérations 31 à 35, 40) dans `lib/features/missions/data/mission_repository.dart`
- [X] T126 [US3] `RescheduleRepository` (opérations 41 à 44) dans `lib/features/missions/data/reschedule_repository.dart`
- [X] T127 [US3] Écran « Mes missions » avec 4 onglets construits en **un appel par onglet** (statuts multiples) et tri décroissant dans `lib/features/missions/presentation/my_missions_screen.dart`
- [X] T128 [US3] Écran de détail de mission (montant `null` affiché « — », annulation tardive signalée, entrée conversation, aucune coordonnée personnelle) dans `lib/features/missions/presentation/mission_detail_screen.dart`
- [X] T129 [US3] Frise chronologique alimentée par l'historique dans `lib/features/missions/presentation/mission_history_view.dart`
- [X] T130 [US3] Parcours d'annulation avec avertissement de tardiveté **avant** l'envoi (seuil lu auprès du service) puis affichage du message serveur dans `lib/features/missions/presentation/cancel_mission_sheet.dart`
- [X] T131 [US3] Écran de proposition de report (une seule demande en attente, validation locale de la date) dans `lib/features/missions/presentation/reschedule_request_screen.dart`
- [X] T132 [US3] Réponse à un report (actions masquées sur ses propres demandes, contre-proposition si le créneau n'est plus disponible) dans `lib/features/missions/presentation/reschedule_response_view.dart`
- [X] T133 [US3] Invalidations après écriture (listes, détail, compteurs) dans `lib/features/missions/presentation/mission_providers.dart`
- [X] T134 [US3] `DisputeRepository` et écrans d'ouverture et de suivi de litige dans `lib/features/disputes/`
- [X] T135 [US3] Cache persistant de la première page et des détails de mission dans `lib/features/missions/data/mission_repository.dart`
- [X] T136 [P] [US3] Tests de widgets (onglets, détail, états vides par onglet) dans `test/widget/mission_screens_test.dart`
- [X] T137 [US3] Test d'intégration du parcours US3 (scénarios 3.1 à 3.5) dans `integration_test/flows/us3_mission_tracking_test.dart` — scénarios dans `us3_mission_tracking.dart`, deux points d'entrée comme pour US1 et US2

**Checkpoint**: Suivi client complet

> **Corrigé en cours de phase** — le bouton « Accepter » d'un report gardait son
> état occupé pendant tout le dialogue de contre-proposition et l'écran poussé :
> son indicateur tournait en arrière-plan sans fin (le parcours d'intégration ne
> se stabilisait jamais). L'occupation s'arrête désormais à la réponse réseau.
>
> Ajouts nés de cette phase : `RescheduleSubmission` (la demande **et** le message
> serveur, affiché tel quel) ; la constante `cancellationDetailsMaxLength` ; les
> aides de chemin `missionHistoryFor`, `missionDisputeFor` et `conversationFor`
> dans `Routes` ; et une garde d'affichage — aucun bouton Accepter/Refuser tant
> que le profil (`me.id`) n'est pas connu, l'auteur d'une demande ne pouvant être
> déterminé sans lui. Le compteur de notifications cité par T133 sera branché à
> l'arrivée du centre de notifications (T198) — l'invalidation est prête.

---

## Phase 6: User Story 4 - Devenir prestataire et faire valider son dossier (Priority: P2)

**Goal**: Parcours d'inscription prestataire en hub (profil, prestations, zones,
agenda, justificatifs), soumission pilotée par le service, suivi et correction.

**Independent Test**: Depuis un compte actif sans profil prestataire, dérouler les
cinq étapes jusqu'à la soumission, puis vérifier le suivi et la correction —
scénarios 4.1 à 4.9.

### Tests for User Story 4

- [X] T138 [P] [US4] Copier les captures JSON (providers/me, checklist, documents, zones, availabilities, erreurs de soumission) dans `test/fixtures/provider/`
- [X] T139 [P] [US4] Test de contrat dossier prestataire (201, **409 traité comme succès**, verrou 400 en vérification, `canSubmit`) dans `test/contract/provider_self_test.dart`
- [X] T140 [P] [US4] Test de contrat prestations, formules et options (404 type inactif, 409 doublon, chemins imbriqué/à plat) dans `test/contract/provider_offer_test.dart`
- [X] T141 [P] [US4] Test de contrat zones (remplacement intégral, plafond 15, **400 atomique** listant les zones invalides) dans `test/contract/provider_zones_test.dart`
- [X] T142 [P] [US4] Test de contrat agenda (lecture miroir de l'écriture, plafond 50 créneaux) dans `test/contract/provider_availabilities_test.dart`
- [X] T143 [P] [US4] Test de contrat justificatifs (`requiredTypes`/`missingTypes`/`current`/`documents`, 400 document déjà validé, retour automatique en vérification) dans `test/contract/provider_documents_test.dart`
- [X] T144 [P] [US4] Test de contrat soumission (400 avec `errors[].field` → lignes rouges, 403 re-soumission bloquée) dans `test/contract/provider_submit_test.dart`
- [X] T145 [P] [US4] Test unitaire des règles d'agenda (fin après début, absence de chevauchement, jour 0–6, plafond 50) dans `test/unit/weekly_slots_test.dart`

### Implementation for User Story 4

- [X] T146 [P] [US4] Modèles `ProviderProfile`, `ProviderChecklist` dans `lib/features/provider_onboarding/domain/`
- [X] T147 [P] [US4] Modèles `ProviderService`, `ServicePack`, `PackOption` (côté prestataire) dans `lib/features/provider_space/domain/`
- [X] T148 [P] [US4] Modèles `WeeklySlot`, `Unavailability`, `ProviderDocument` dans `lib/features/provider_space/domain/`
- [X] T149 [US4] `ProviderSelfRepository` (opérations 65 à 84) dans `lib/features/provider_onboarding/data/provider_self_repository.dart`
- [X] T150 [US4] Écrans P1 (présentation du parcours) et P2 (création du profil public) dans `lib/features/provider_onboarding/presentation/`
- [X] T151 [US4] Écran **hub** de complétude P8 (5 lignes alimentées par le service, libellés explicites « nom public **et** présentation », « service **avec** formule active », bouton piloté par `canSubmit`) dans `lib/features/provider_onboarding/presentation/checklist_screen.dart`
- [X] T152 [US4] Étape P3 — déclaration d'un service avec sélecteur à deux niveaux dans `lib/features/provider_onboarding/presentation/service_step_screen.dart`
- [X] T153 [US4] Étapes P4 et P4b — création d'une formule et de ses options dans `lib/features/provider_onboarding/presentation/pack_step_screen.dart`
- [X] T154 [US4] Étape P5 — zones à cocher (état complet envoyé, plafond 15, **confirmation explicite si la liste passe de non vide à vide**) dans `lib/features/provider_onboarding/presentation/zones_step_screen.dart`
- [X] T155 [US4] Étape P6 — grille d'agenda 7 jours (dimanche en premier, `HH:MM` **non converti**, contrôles locaux de chevauchement et d'ordre) dans `lib/features/provider_onboarding/presentation/availabilities_step_screen.dart`
- [X] T156 [US4] Étape P7 — justificatifs construits depuis `requiredTypes`, envoi en deux temps, historique des versions, re-dépôt interdit sur un document validé dans `lib/features/provider_onboarding/presentation/documents_step_screen.dart`
- [X] T157 [US4] Action de soumission avec correspondance `errors[].field` → lignes rouges exactes dans `lib/features/provider_onboarding/presentation/submit_controller.dart`
- [X] T158 [US4] Écran de suivi P9 couvrant les 5 états (motif en tête, actions par état, contact support si re-soumission bloquée) dans `lib/features/provider_onboarding/presentation/status_screen.dart`
- [X] T159 [US4] Verrou en vérification : champs d'identité en lecture seule, **interrupteur de disponibilité actif** dans `lib/features/provider_space/presentation/provider_profile_screen.dart`
- [X] T160 [US4] Rechargement du dossier après chaque dépôt de justificatif + message « reparti en vérification » et retrait du bouton de re-soumission dans `lib/features/provider_onboarding/presentation/documents_step_screen.dart`
- [X] T161 [P] [US4] Tests de widgets (hub de complétude, écran de suivi par état) dans `test/widget/provider_onboarding_test.dart`
- [X] T162 [US4] Test d'intégration du parcours US4 (scénarios 4.1 à 4.9) dans `integration_test/flows/us4_provider_onboarding_test.dart`

**Checkpoint**: Un prestataire peut constituer et soumettre son dossier

> **Décisions prises en cours de phase** :
>
> 1. **`Category`, `ServiceType` et `Zone` ont déménagé dans `lib/shared/catalog/`.**
>    L'onboarding (P3, P5) lit le même catalogue que la recherche, mais la porte G5
>    interdit à la surface prestataire d'importer `features/search`.
>    `features/search/domain/catalog.dart` est devenu un réexport — aucun autre
>    fichier n'a bougé.
> 2. **`provider_space` atteint le dossier via `providerOverviewProvider`**
>    (présentation de `provider_onboarding`), jamais via le dépôt : la règle
>    `cross_feature_data` interdit d'importer la couche `data/` d'une autre
>    fonctionnalité. Le contrôleur relaie les écritures (`updateIdentity`,
>    `setAvailability`) et adopte l'aperçu rendu — un seul état du dossier, quel
>    que soit l'écran.
> 3. **L'interrupteur de disponibilité vit aussi sur l'écran de suivi P9** : en
>    `pending_review`, le gardien détourne `/provider/profile` (réservé aux
>    dossiers approuvés), or c'est précisément le statut où « seul l'interrupteur
>    reste actif ». P9 l'héberge donc, et pousse l'écran de profil verrouillé en
>    lecture seule (`AvailabilityControl` partagé, scénario 4.8).
> 4. **Le sélecteur de fichier de P7 est derrière `documentPickerProvider`** : les
>    greffons de plateforme n'existent ni en test de widget ni dans le parcours
>    sans appareil. Le harnais de flux accepte désormais des `extraOverrides` pour
>    ce genre de point d'injection.
> 5. Dans les parcours, `tester.pageBack()` est proscrit : il cherche l'infobulle
>    anglaise « Back » alors que l'application est localisée (« Retour ») — le
>    retour se fait par `find.byType(BackButton)`.

---

## Phase 7: User Story 5 - Piloter ma journée de prestataire (Priority: P2)

**Goal**: Tableau de bord composé, actions de mission conformes à l'état, fenêtre de
démarrage, expiration des demandes, interrupteur de disponibilité.

**Independent Test**: Sur un compte prestataire approuvé avec une demande en attente,
accepter, démarrer, terminer — scénarios 5.1 à 5.6.

### Tests for User Story 5

- [X] T163 [P] [US5] Copier les captures JSON (missions prestataire, transitions) dans `test/fixtures/provider_missions/`
- [X] T164 [P] [US5] Test de contrat liste prestataire (tri **croissant**, filtres `from`/`to` inclusifs, statuts multiples) dans `test/contract/provider_missions_test.dart`
- [X] T165 [P] [US5] Test de contrat transitions (accepter, refuser, démarrer, terminer, annuler + 400 « action impossible », 403 non prestataire) dans `test/contract/mission_transitions_test.dart`

### Implementation for User Story 5

- [X] T166 [US5] Méthodes de transition dans `lib/features/provider_space/data/provider_mission_repository.dart` — *transitions déplacées dans `mission_transition_controller.dart` (voir note de phase), le dépôt porte la liste, son cache et les compteurs*
- [X] T167 [US5] Tableau de bord composé de blocs **indépendants** (demandes en attente, missions du jour, non-lus) dans `lib/features/provider_space/presentation/dashboard_screen.dart`
- [X] T168 [US5] Interrupteur de disponibilité avec explication de « Occupé » vs « Indisponible » dans `lib/features/provider_space/presentation/availability_switch.dart`
- [X] T169 [US5] Écran planning et demandes (tri serveur conservé) dans `lib/features/provider_space/presentation/provider_missions_screen.dart`
- [X] T170 [US5] Boutons d'action par état (jamais « Refuser » et « Annuler » ensemble, aucune action sur état terminal) dans `lib/features/missions/presentation/mission_actions_bar.dart`
- [X] T171 [US5] Fenêtre de démarrage : bouton indisponible hors fenêtre + heure d'activation affichée (seuil lu auprès du service) dans `lib/features/missions/presentation/start_action.dart`
- [X] T172 [US5] Compte à rebours d'expiration des demandes en attente dans `lib/features/provider_space/presentation/widgets/pending_expiry_badge.dart`
- [X] T173 [US5] Dialogues de motif pour refus et annulation (3 caractères minimum, avertissement de tardiveté) dans `lib/features/missions/presentation/reason_dialog.dart`
- [X] T174 [US5] Interdiction de rejeu sur les transitions : rechargement de l'état réel en cas de réponse non reçue dans `lib/features/missions/data/mission_transition_controller.dart`
- [X] T175 [US5] Reformulation à la deuxième personne des messages de disponibilité côté prestataire dans `lib/features/missions/presentation/provider_message_rewriter.dart`
- [X] T176 [P] [US5] Tests de widgets (tableau de bord avec un bloc en erreur, boutons par état) dans `test/widget/provider_dashboard_test.dart`
- [X] T177 [US5] Test d'intégration du parcours US5 (scénarios 5.1 à 5.6) dans `integration_test/flows/us5_provider_day_test.dart` — scénarios dans `us5_provider_day.dart`, deux points d'entrée comme pour US1 à US4

**Checkpoint**: Le cycle complet d'une mission fonctionne des deux côtés

> **Décisions prises en cours de phase** :
>
> 1. **Les cinq transitions vivent dans `features/missions`, pas dans
>    `provider_space`.** T166 les plaçait dans `provider_mission_repository.dart`,
>    mais les boutons qui les déclenchent sont sur l'écran de détail **commun**
>    (`features/missions`), et la règle `cross_feature_data` interdit à `missions`
>    d'importer le dépôt d'une autre fonctionnalité. Elles rejoignent donc
>    `mission_transition_controller.dart` (T174) — conforme au contrat
>    [api-consumption.md](./contracts/api-consumption.md), qui affecte les
>    opérations 36 à 40 au `mission_repository` de `features/missions` (L6
>    compris). Le dépôt `provider_mission_repository` garde l'opération 33, le
>    cache du planning (rôle `provider`, séparé du cache client : tris opposés)
>    et le compteur de non-lus.
> 2. **Le compteur de non-lus du tableau de bord est provisoirement lu par
>    `provider_space`** (`unreadNotifications()` sur le dépôt) : le centre de
>    notifications n'existe pas encore. À T196/T198, la route repart dans
>    `features/notifications` et le bloc se branche sur les compteurs communs.
> 3. **`AvailabilityControl` a déménagé dans `availability_switch.dart`** (T168) :
>    trois écrans l'affichent désormais — tableau de bord (en évidence), profil de
>    l'espace prestataire, suivi P9 — et il vivait dans l'écran de profil.
> 4. **« Proposer un report » s'affiche pour les deux parties** sur le détail de
>    mission (il était réservé au client depuis US3) : la table de data-model §5.3
>    le classe dans les actions communes, et l'écran de proposition était déjà
>    neutre quant au rôle. Les messages d'agenda du service (« Le prestataire ne
>    travaille pas sur ce créneau »…) y sont reformulés à la deuxième personne
>    quand le lecteur est le prestataire (T175, FR-049) — la comparaison logique
>    (`kSlotGoneMessage`) reste sur le message brut.
> 5. **Le scénario 5.5 traverse la chaîne d'intercepteurs de production** : le
>    service simulé mute l'état PUIS perd la réponse — le parcours vérifie donc
>    aussi, de bout en bout, que la politique de rejeu épargne les transitions
>    (un seul POST) et que l'écran relit l'état réel au lieu de le présumer.

---

## Phase 8: User Story 6 - Échanger par messagerie (Priority: P3)

**Goal**: Liste des conversations, fil paginé, envoi avec pièces jointes, marquage lu,
rafraîchissement sans temps réel.

**Independent Test**: Ouvrir une conversation depuis l'onglet et depuis une mission,
envoyer un message avec pièce jointe, vérifier les compteurs — scénarios 6.1 à 6.4.

### Tests for User Story 6

- [X] T178 [P] [US6] Copier les captures JSON (fils, messages paginés, compteur global) dans `test/fixtures/messaging/`
- [X] T179 [P] [US6] Test de contrat messagerie (pagination et tri par défaut **croissant**, compteur global, marquage lu, plafonds d'envoi, 400 fil clôturé) dans `test/contract/messaging_repository_test.dart`

### Implementation for User Story 6

- [X] T180 [P] [US6] Modèles `Thread` et `Message` dans `lib/features/messaging/domain/`
- [X] T181 [US6] `MessagingRepository` (opérations 48 à 53) dans `lib/features/messaging/data/messaging_repository.dart`
- [X] T182 [US6] Écran liste des conversations + pastille globale dans `lib/features/messaging/presentation/threads_screen.dart`
- [X] T183 [US6] Écran de conversation ouvrant sur les messages **récents** puis chargeant l'historique en remontant dans `lib/features/messaging/presentation/conversation_screen.dart`
- [X] T184 [US6] Zone de saisie (1 à 4000 caractères, 3 pièces jointes au maximum envoyées au préalable) dans `lib/features/messaging/presentation/message_composer.dart`
- [X] T185 [US6] Envoi optimiste, état d'échec et **renvoi manuel** (aucun rejeu automatique) dans `lib/features/messaging/presentation/message_send_controller.dart`
- [X] T186 [US6] Masquage de la saisie sur un fil non ouvert dans `lib/features/messaging/presentation/conversation_screen.dart`
- [X] T187 [US6] Marquage lu à l'ouverture et mise à jour des compteurs dans `lib/features/messaging/presentation/conversation_screen.dart`
- [X] T188 [US6] Déclencheurs de rafraîchissement (ouverture, geste, retour au premier plan, notification de message) dans `lib/features/messaging/presentation/conversation_refresh.dart`
- [X] T189 [US6] Cache persistant par fil pour la relecture hors ligne dans `lib/features/messaging/data/messaging_repository.dart`
- [X] T190 [P] [US6] Tests de widgets (conversation, fil clôturé, bulle en échec) dans `test/widget/messaging_test.dart`
- [X] T191 [US6] Test d'intégration du parcours US6 (scénarios 6.1 à 6.4) dans `integration_test/flows/us6_messaging_test.dart` — scénarios dans `us6_messaging.dart`, deux points d'entrée comme pour US1 à US5

**Checkpoint**: Mise en relation opérationnelle sans exposer de coordonnées

> **Décisions prises en cours de phase** :
>
> 1. **Comment un écran de conversation connaît-il le statut de son fil ?** Il
>    n'existe pas de route `GET /threads/{id}` — le statut vient soit de la liste
>    des fils, soit de la mission porteuse. `Routes.conversationFor` accepte donc
>    un `missionId` optionnel (`?mission=`) : `conversationInfoProvider` cherche
>    d'abord le fil dans la liste (elle porte aussi le nom de l'interlocuteur),
>    puis interroge `GET /missions/{id}/thread` (opération 50 — précisément prévue
>    pour « arriver sans avoir chargé /me/threads »), et sinon considère le fil
>    ouvert : le 400 « Conversation clôturée » du service reste le filet. Le
>    détail de mission passe désormais la mission au fil qu'il ouvre.
> 2. **Le sélecteur de pièce jointe a sa propre interface**
>    (`messageAttachmentPickerProvider`, calquée sur `documentPickerProvider` de
>    P7) : la frontière G5 interdit à `messaging` d'importer la présentation de
>    `provider_onboarding`, et les greffons de plateforme n'existent pas dans les
>    tests. Les extensions proposées couvrent tous les MIME acceptés en
>    messagerie (images, PDF, texte) — P7 reste limité aux justificatifs.
> 3. **`chatMessageSignalProvider` est le point d'ancrage de T203** : le
>    rafraîchissement « sur notification de message » (FR-080) écoute ce signal
>    par fil ; le routage des notifications l'actionnera à l'arrivée d'une charge
>    utile `chat` (US7). D'ici là, seuls les parcours de test le lèvent.
> 4. **Le scénario 6.3 traverse la chaîne d'intercepteurs de production** (comme
>    5.5) : le service simulé coupe le transport sur le POST seul, et le parcours
>    compte les appels — un seul part, la politique de rejeu épargne bien
>    `POST /messages/threads/{id}/messages` de bout en bout ; le « Renvoyer »
>    manuel en émet un second, sans doublon à l'écran.

---

## Phase 9: User Story 7 - Être averti au bon moment (Priority: P3)

**Goal**: Centre de notifications, compteurs, cycle de vie du jeton d'appareil,
routage identique pour les notifications internes et poussées.

**Independent Test**: Provoquer un évènement depuis l'autre rôle, vérifier la liste, le
compteur, le marquage lu et le routage — scénarios 7.1 à 7.5.

### Tests for User Story 7

- [X] T192 [P] [US7] Copier les captures JSON (notifications, compteur, appareils) dans `test/fixtures/notifications/`
- [X] T193 [P] [US7] Test de contrat notifications et appareils (filtre `unread`, marquage **idempotent**, enregistrement idempotent, désenregistrement tolérant) dans `test/contract/notification_repository_test.dart`
- [X] T194 [P] [US7] Test unitaire du routage par charge utile (4 types + type inconnu → centre de notifications) dans `test/unit/notification_router_test.dart`

### Implementation for User Story 7

- [X] T195 [P] [US7] Modèles `AppNotification` et `NotificationPayload` dans `lib/features/notifications/domain/`
- [X] T196 [US7] `NotificationRepository` et `DeviceRepository` (opérations 54 à 60) dans `lib/features/notifications/data/`
- [X] T197 [US7] Écran centre de notifications (filtre non lues, marquage unitaire et global, **aucune suppression**) dans `lib/features/notifications/presentation/notifications_screen.dart`
- [X] T198 [US7] Compteurs et moments de rafraîchissement (démarrage, retour au premier plan, réception) dans `lib/features/notifications/presentation/badge_providers.dart`
- [X] T199 [US7] Initialisation Firebase et demande d'autorisation **au bon moment** (après connexion) dans `lib/core/push/push_service.dart`
- [X] T200 [US7] Cycle de vie du jeton d'appareil (connexion, démarrage sur session restaurée, changement de jeton, **avant** déconnexion) dans `lib/core/push/push_service.dart`
- [X] T201 [US7] Câblage des trois points d'entrée (premier plan, arrière-plan, application tuée) dans `lib/core/push/push_entry_points.dart`
- [X] T202 [US7] Bannière interne au premier plan via notification locale dans `lib/core/push/foreground_presenter.dart`
- [X] T203 [US7] Fonction de routage **unique** partagée par les notifications internes et poussées, avec destination différée si la session est absente dans `lib/core/push/notification_router.dart`
- [X] T204 [P] [US7] Test de widget du centre de notifications dans `test/widget/notifications_test.dart`
- [X] T205 [US7] Test d'intégration du parcours US7 avec charges utiles **simulées** (scénarios 7.1 à 7.5) dans `integration_test/flows/us7_notifications_test.dart` — scénarios dans `us7_notifications.dart`, deux points d'entrée comme pour US1 à US6

**Checkpoint**: Réactivité assurée, application fonctionnelle même sans autorisation

> **Décisions prises en cours de phase** :
>
> 1. **Le socle n'importe aucune feature — l'assemblage vit dans
>    `lib/app/push_driver.dart`.** `core/push/` déclare des contrats
>    (`PushMessenger`, `DeviceRegistrar`, `ForegroundPresenter`) et une
>    résolution de chemin **injectée** : la table charge utile → route
>    (`destinationPathFor`) et le branchement sur go_router, le dépôt des
>    appareils et le profil se font dans la couche applicative. `PushDriver`
>    enveloppe `MaterialApp.router` — en production comme dans le harnais de
>    parcours, qui traverse donc le pilote réel.
> 2. **`NotificationPayload` vit dans `core/push/`** (le routeur du socle en
>    dépend) ; `features/notifications/domain/notification_payload.dart` est un
>    réexport — même mouvement que le catalogue à la phase 6. L'analyse est
>    tolérante : valeurs **chaînes** (transport FCM), type inconnu ou charge
>    mutilée → centre de notifications, jamais une erreur.
> 3. **Tout le push est « au mieux »** : `FirebasePushMessenger` s'initialise
>    paresseusement et devient un non-évènement sans configuration Firebase
>    (tests, poste de développement, saveur sans identifiants). Aucun parcours
>    ne dépend d'une autorisation ni d'un enregistrement réussi (FR-085) — c'est
>    ce qui permet aux parcours US1 à US6 de traverser le pilote sans surcharge.
> 4. **L'enregistrement part sur chaque transition vers « session ouverte »** :
>    la restauration au démarrage produit la même transition que la connexion —
>    un seul écouteur couvre les deux lignes du cycle de vie. Le
>    désenregistrement est l'étape 1 de la séquence de déconnexion (T073),
>    **avant** `POST /auth/logout` — l'ordre est vérifié par le scénario 7.5.
> 5. **Le compteur du tableau de bord prestataire est re-branché** sur
>    `notificationsUnreadCountProvider` (T198), comme promis à la phase 7 :
>    `unreadNotifications()` a quitté `provider_mission_repository`, et
>    `invalidateAfterMissionWrite` rafraîchit désormais aussi la pastille (T133).
> 6. **Un écran « Appareils connectés » minimal** (opération 58, consultation
>    seule) remplace l'emplacement `/profile/devices` — l'enregistrement et le
>    désenregistrement restent l'affaire exclusive du cycle de vie du jeton,
>    jamais d'un écran.

---

## Phase 10: User Story 8 - Gérer mon offre dans la durée (Priority: P3)

**Goal**: Gestion permanente du profil, des prestations, formules, options, zones,
agenda, absences, portfolio et justificatifs après approbation.

**Independent Test**: Modifier un prix, désactiver une formule, ajouter une absence,
ajouter puis retirer une réalisation — scénarios 8.1 à 8.5.

### Tests for User Story 8

- [X] T206 [P] [US8] Copier les captures JSON (services, formules, options, portfolio, absences) dans `test/fixtures/provider_offer/`
- [X] T207 [P] [US8] Test de contrat portfolio (plafond 20, images seules, visibilité `public` puis retour `restricted`) dans `test/contract/portfolio_repository_test.dart`
- [X] T208 [P] [US8] Test de contrat absences (fin après début, chevauchement, appartenance vérifiée) dans `test/contract/unavailabilities_test.dart`

### Implementation for User Story 8

- [X] T209 [US8] Écran de profil prestataire avec envoi de photo et **avertissement de visibilité publique** dans `lib/features/provider_space/presentation/provider_profile_screen.dart`
- [X] T210 [US8] Écran « Mes prestations » (vocabulaire « Désactiver », avertissement de disparition de la recherche) dans `lib/features/provider_space/presentation/services_screen.dart`
- [X] T211 [US8] Gestion des formules et options (mention que les missions réservées gardent leur montant, chemin de modification **à plat** pour les options) dans `lib/features/provider_space/presentation/packs_screen.dart`
- [X] T212 [US8] Écran de gestion des zones (pré-cochage par la lecture, remplacement intégral) dans `lib/features/provider_space/presentation/zones_screen.dart`
- [X] T213 [US8] Écran de gestion de l'agenda hebdomadaire s'appuyant sur la lecture dédiée dans `lib/features/provider_space/presentation/availabilities_screen.dart`
- [X] T214 [US8] Écran des absences exceptionnelles (création, suppression, contrôles locaux) dans `lib/features/provider_space/presentation/unavailabilities_screen.dart`
- [X] T215 [US8] Écran portfolio (ajout, modification, réordonnancement **élément par élément** avec repli sur l'ordre serveur, retrait avec invalidation du cache d'image) dans `lib/features/provider_space/presentation/portfolio_screen.dart`
- [X] T216 [US8] Écran des justificatifs après approbation (états par ligne, motif de refus, historique des versions, re-dépôt interdit si validé) dans `lib/features/provider_space/presentation/documents_screen.dart`
- [X] T217 [P] [US8] Tests de widgets des écrans de l'espace prestataire dans `test/widget/provider_space_test.dart`
- [X] T218 [US8] Test d'intégration du parcours US8 (scénarios 8.1 à 8.5) dans `integration_test/flows/us8_provider_offer_test.dart` — scénarios dans `us8_provider_offer.dart`, deux points d'entrée comme pour US1 à US7

**Checkpoint**: Vie du compte prestataire complète

> **Décisions prises en cours de phase** :
> 1. **Portfolio et absences dans `ProviderSelfRepository`** (opérations 85 à 88, plus la relecture 29) : le contrat les range sous ce dépôt, et l'accès de `provider_space` passe par la façade de présentation `provider_self_access.dart` — la couche `data/` d'une fonctionnalité ne s'importe pas depuis une autre (porte G5). L'aperçu du dossier, qui porte un état partagé, garde son relais dédié (`provider_overview_controller`).
> 2. **Zones (T212), agenda (T213) et justificatifs (T216) délèguent aux écrans des étapes P5/P6/P7** : les règles (remplacement intégral, heures `HH:MM` sans fuseau, re-dépôt interdit si validé, relecture de l'aperçu après dépôt) n'existent qu'à UN endroit — deux copies divergeraient.
> 3. **La relecture des absences passe par la route publique** `GET /providers/{id}/unavailabilities` (opération 29) avec l'identifiant de l'aperçu : il n'existe pas de `GET /providers/me/unavailabilities`.
> 4. **L'avertissement de disparition de la recherche (8.2) est calculé localement** (`deactivationClearsSearch`, `_lastReachablePack`) : il se déclenche sur la désactivation du dernier service réservable comme de la dernière formule active — et un refus n'envoie rien.
> 5. **Le retrait d'une réalisation purge le cache d'image** (`CachedNetworkImage.evictFromCache`) : le fichier redescend en `restricted`, la copie disque ne correspond plus à rien de servi. Le réordonnancement est deux PATCH `displayOrder` (l'élément et son voisin) ; tout échec replie sur l'ordre serveur par invalidation.
> 6. **L'avertissement de visibilité publique de la photo (8.4) précède le sélecteur de fichier** : renoncer n'ouvre rien, accepter enchaîne binaire (`POST /files/upload`, visibilité `public`, images seules refusées localement) puis rattachement (`PATCH /providers/me`).

---

## Phase 11: User Story 9 - Noter, être noté, signaler (Priority: P3)

**Goal**: Dépôt d'avis par le client dans la fenêtre autorisée, consultation de ses
avis avec états de modération, signalement.

**Independent Test**: Déposer un avis sur une mission terminée, le voir sur la fiche et
dans « Mes avis », constater la disparition de l'action — scénarios 9.1 à 9.4.

### Tests for User Story 9

- [X] T219 [P] [US9] Copier les captures JSON (dépôt, mes avis, signalement) dans `test/fixtures/reviews/`
- [X] T220 [P] [US9] Test de contrat avis (201, **409 traité comme succès**, 400 hors fenêtre, 403 prestataire, signalement et doublon) dans `test/contract/review_repository_test.dart`
- [X] T221 [P] [US9] Test unitaire des conditions d'affichage du bouton d'avis (statut, rôle, avis existant, fenêtre calculée depuis l'historique et le réglage) dans `test/unit/review_eligibility_test.dart`

### Implementation for User Story 9

- [X] T222 [P] [US9] Modèle `Review` dans `lib/features/reviews/domain/review.dart`
- [X] T223 [US9] `ReviewRepository` (opérations 45 à 47) dans `lib/features/reviews/data/review_repository.dart`
- [X] T224 [US9] Écran de dépôt d'avis avec temps restant affiché dans `lib/features/reviews/presentation/submit_review_screen.dart`
- [X] T225 [US9] Écran « Mes avis » avec états de modération (avis retiré remplacé par une mention) dans `lib/features/reviews/presentation/my_reviews_screen.dart`
- [X] T226 [US9] Action de signalement (masquée sur ses propres avis, mention « déjà signalé ») dans `lib/features/reviews/presentation/report_review_action.dart`
- [X] T227 [US9] Masquer toute action de notation côté prestataire dans `lib/features/missions/presentation/mission_detail_screen.dart`
- [X] T228 [P] [US9] Tests de widgets des états d'avis dans `test/widget/reviews_test.dart`
- [X] T229 [US9] Test d'intégration du parcours US9 (scénarios 9.1 à 9.4) dans `integration_test/flows/us9_reviews_test.dart` — scénarios dans `us9_reviews.dart`, deux points d'entrée comme pour US1 à US8

**Checkpoint**: Boucle de confiance fermée

> **Décisions prises en cours de phase** :
> 1. **Le 409 est une issue, jamais une erreur — deux fois** : `submitReview` rend `null` sur « déjà noté » (même chemin d'écran que le 201) et `reportReview` rend `ReportOutcome.alreadyReported` sur le doublon — la mention « Déjà signalé » à l'écran (9.4).
> 2. **L'éligibilité du bouton d'avis est une fonction pure** (`reviewEligibilityFor`) : statut `completed`/`closed`, rôle client, absence d'avis, fenêtre datée par l'entrée en `completed` de l'HISTORIQUE et dimensionnée par `reviewsWindowDays`. Historique muet → l'action s'affiche sans temps restant : le service reste l'autorité.
> 3. **Le dépôt s'ouvre par pile de navigation** depuis le détail de mission (pas de route dédiée) — conforme à navigation-routes.md, où le dépôt est une section du détail (`?tab=review` y atterrit par la route du détail).
> 4. **La mention « déjà signalé » survit à la navigation** via un état de session (`reportedReviewIdsProvider`) alimenté par le 201 comme par le 409 ; l'action est masquée par construction dans « Mes avis » (`isOwn`), le 403 du service restant le filet sur la page publique, qui n'identifie pas l'auteur.
> 5. **Aucune action de notation côté prestataire** : la zone d'avis vit exclusivement sous `asClient` dans le détail de mission — vérifié par le scénario 9.2 sur la MÊME mission vue par les deux comptes.

---

## Phase 12: User Story 10 - Rester utilisable en réseau dégradé (Priority: P4)

**Goal**: Consultation hors ligne avec âge des données, bannière permanente, écritures
indisponibles sans mise en file, reprise à la reconnexion.

**Independent Test**: Charger les écrans clés, couper le réseau, vérifier consultation,
bannière, horodatage et blocage des écritures — scénarios 10.1 à 10.4.

### Implementation for User Story 10

- [X] T230 [P] [US10] Compléter les tables de cache pour toutes les données du tableau de persistance de [data-model.md](./data-model.md) dans `lib/core/cache/local_database.dart` — les 7 tables couvraient déjà l'intégralité du tableau §12, vérifié ligne à ligne
- [X] T231 [US10] Câbler « servir le cache puis revalider » sur tous les dépôts concernés dans `lib/features/*/data/` — déjà câblé phase par phase (catalogue/zones en TTL 24 h, profil, adresses, missions liste et détail, messages, missions prestataire), vérifié dépôt par dépôt
- [X] T232 [US10] Composant d'affichage de l'âge des données (« Mis à jour il y a N min ») dans `lib/core/widgets/data_age_label.dart`
- [X] T233 [US10] Bannière hors ligne permanente avec horodatage dans `lib/core/connectivity/offline_banner.dart`
- [X] T234 [US10] Mécanisme **unique** de désactivation des actions d'écriture hors ligne avec explication, sans aucune mise en file dans `lib/core/connectivity/offline_gate.dart`
- [X] T235 [US10] Rafraîchissement automatique de l'écran courant au retour du réseau dans `lib/core/connectivity/reconnect_refresher.dart`
- [X] T236 [US10] Garantir l'absence de mise en cache disque des contenus sensibles et autoriser celle des contenus publics dans `lib/core/files/file_cache_policy.dart`
- [X] T237 [P] [US10] Tests unitaires du cache (durées de vie, purge à la déconnexion, aucune écriture différée) dans `test/unit/cache_policy_test.dart`
- [X] T238 [US10] Test d'intégration du parcours US10 (scénarios 10.1 à 10.4) dans `integration_test/flows/us10_offline_test.dart` — scénarios dans `us10_offline.dart`, deux points d'entrée comme pour US1 à US9

**Checkpoint**: Application exploitable sur le terrain

> **Décisions prises en cours de phase** :
> 1. **La bannière est montée par le `builder` du `MaterialApp`** (`GlobalOfflineBanner`) : elle coiffe TOUS les écrans sans qu'aucun n'y pense — c'est ce qui la rend permanente. Son horodatage (« Données du … ») est enregistré par la couche réseau à chaque réponse réussie (`lastDataTimestampProvider`, alimenté dans `apiClientProvider`).
> 2. **`OfflineWriteGuard` est LE mécanisme de désactivation** : le bouton reçoit `canWrite == false` hors ligne, l'explication s'affiche dessous, rien n'est mémorisé. Posé sur l'annulation de mission et l'envoi de message ; `OfflineGate.guardWrite` reste le garde-fou de dernier recours.
> 3. **Le rafraîchissement à la reconnexion est par écran** (`RefreshOnReconnect`) : seule la transition hors ligne → en ligne déclenche, et c'est l'écran courant qui se relit — pas une purge globale. Branché sur les onglets de missions et le détail de mission.
> 4. **L'âge des données ne s'affiche que hors ligne** (`DataAgeLabel` + `…FetchedAtProvider` lisant le `fetchedAt` du cache) : en ligne, la donnée est fraîche par construction.
> 5. **Le portier réseau tolère un greffon muet** (échec → en ligne, erreurs de flux avalées) : la connectivité est un filtre d'ergonomie, pas une preuve — et les harnais de test substituent un portier factice par défaut, le parcours US10 pilotant le sien.
> 6. **La politique fichiers est codifiée en un point** (`FileCachePolicy`) et appliquée à l'unique point d'affichage (`FileImage`) : `public` → moteur à cache disque, tout le reste → mémoire d'écran seulement — un justificatif rouvert hors ligne ne restitue rien (10.4).

---

## Phase 13: Polish & Cross-Cutting Concerns

**Purpose**: Finition transverse et vérifications de conformité

- [X] T239 [P] Rédiger le guide de mise en route (environnements, émulateur `10.0.2.2`, comptes de démonstration) dans `README.md`
- [X] T240 [P] Passe d'accessibilité (contrastes, taille des cibles, libellés de lecture d'écran) sur les écrans des parcours P1 dans `lib/features/`
- [X] T241 [P] Optimisation de performance (dimensionnement des images, virtualisation des listes, budget de démarrage à froid) dans `lib/features/search/` et `lib/features/missions/`
- [X] T242 [P] Instrumenter les traces de performance des écrans clés pour mesurer SC-005 dans `lib/core/error/error_reporter.dart`
- [X] T243 Auditer la couverture du `correlationId` sur 100 % des incidents remontés (SC-010) dans `lib/core/api/envelope_interceptor.dart`
- [X] T244 [P] Relecture éditoriale des libellés français, y compris les reformulations prestataire (FR-049), dans `lib/l10n/app_fr.arb`
- [X] T245 Auditer la purge et le changement de compte (SC-012) : aucune donnée du compte précédent visible, dans `lib/core/session/session_controller.dart`
- [X] T246 [P] Tests de référence visuelle des composants d'état partagés dans `test/widget/goldens/`
- [X] T247 Exécuter les vérifications transverses du §5 de [quickstart.md](./quickstart.md) (portes G2, G3, G5, G6) et consigner les résultats
- [X] T248 Configurer la livraison (icônes, noms d'application par environnement, versionnage) dans `android/app/src/` et `ios/Runner/`
- [X] T249 [P] Compléter l'intégration continue (analyse, tests, compilation de la saveur `staging`) dans `.github/workflows/ci.yml`

> **Constats et corrections de la phase** :
>
> 1. **T243 — la couverture du `correlationId` était de 0 %, pas de 100 %** :
>    `ErrorReporter.reportApiFailure` existait mais n'était appelé nulle part.
>    Le manque est comblé au bon étage : `IncidentReportingInterceptor`
>    (`envelope_interceptor.dart`), posé en **dernier** dans la chaîne — il ne
>    voit que les échecs définitifs, jamais un 401 rattrapé par le
>    renouvellement ni un 503 rejoué avec succès. Les deux instances HTTP
>    (principale et renouvellement) le reçoivent ; le tri incident / issue
>    attendue (réseau, saisie, débit, session) reste dans le rapporteur.
>    Verrouillé par `test/unit/incident_reporting_test.dart`.
> 2. **T242 — `traceScreen` existait mais aucun écran ne l'appelait.** Branché
>    sur la première page de résultats de recherche (`screen.search.results`,
>    la mesure directe de SC-005), les onglets de missions et le détail de
>    mission. Sa gestion d'erreur ne recapture plus les `ApiException` — déjà
>    remontées par la chaîne, les doubler contournait le tri de T243.
> 3. **T245 — `signIn` promettait une purge qu'il ne faisait pas** : son
>    commentaire annonçait la recréation du conteneur au changement de compte,
>    le code ne purgeait rien. Il purge désormais la base locale **avant**
>    d'écrire les jetons (ceinture — les parcours normaux passent déjà par la
>    purge de déconnexion) ; le conteneur, lui, n'est pas recréé : le gardien
>    lit `?from=` à cet instant précis. Test dans `cache_policy_test.dart`.
> 4. **T241 — les images étaient décodées à la taille du fichier** :
>    `FileImage` plafonne désormais le décodage à la taille d'affichage
>    (`memCacheWidth` / `cacheWidth` × devicePixelRatio) et `ProviderAvatar`
>    déclare sa taille. Les listes étaient déjà virtualisées.
> 5. **T246 — références visuelles sans dépendance nouvelle** (`matchesGoldenFile`
>    natif, `golden_toolkit` étant déprécié). Générées sous Windows, elles sont
>    étiquetées `golden` et **exclues de l'intégration continue Linux**
>    (`--exclude-tags=golden`) : le rendu diffère au pixel près entre systèmes.
> 6. **T248** : icône de lanceur provisoire (aplat de la couleur de marque,
>    générée par `flutter_launcher_icons` — l'identité définitive se substitue
>    dans `assets/icon/` sans reconfiguration), signature de livraison lue dans
>    `android/key.properties` (non versionné, repli sur la clé de débogage),
>    version applicative injectée par `--dart-define=APP_VERSION` depuis
>    `pubspec.yaml` (le `TODO(T248)` du `User-Agent` est levé). Les noms par
>    saveur existaient depuis T009.
> 7. **T247 — vérifications transverses du §5 de quickstart.md** :
>    - **G2** (`['data']` hors socle) : seules occurrences hors `core/api/` —
>      le champ `data` **propre** à l'entité notification (`app_notification.dart`),
>      pas l'enveloppe. Aucun test de code HTTP hors socle (`statusCode` absent
>      de `lib/features/`). ✅
>    - **G3** : les six seuils lus via `publicSettingsProvider` (9 points de
>      lecture), constantes en repli seulement (`public_settings_test.dart`). ✅
>    - **G5** : `flutter analyze` sans avertissement,
>      `dart run tool/check_import_boundaries.dart` — 199 fichiers, aucune
>      violation. ✅
>    - **G6** : jetons en stockage sécurisé, `FileCachePolicy` seul point de
>      décision disque, purge vérifiée par `cache_policy_test.dart` ;
>      l'inspection **sur appareil** après usage reste à faire à la recette. ✅
>    - `flutter test` : 727 tests au vert ; APK `staging` compilé localement
>      (66,9 Mo).
> 8. **La première compilation de livraison a échoué — et c'est T249 qui l'a
>    sortie.** `sentry_flutter` 8.x compile son module Android en Kotlin
>    « language version 1.6 », que le Kotlin 2.2 déclaré dans
>    `android/settings.gradle.kts` refuse désormais : `flutter test` et
>    `flutter analyze` n'y touchent jamais, seule une compilation Android réelle
>    le révèle. Le plancher est relevé pour ce **seul** module dans
>    `android/build.gradle.kts` — à retirer au passage à `sentry_flutter` 9.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)** : aucune dépendance
- **Foundational (Phase 2)** : dépend de la Phase 1 — **bloque tous les récits**
- **US1 (Phase 3)** : dépend de la Phase 2 — aucun autre récit ne peut être validé sans elle (toute écriture exige une session)
- **US2 (Phase 4)** : dépend de la Phase 2 ; la partie recherche et fiche est testable sans US1, la réservation exige US1
- **US3 (Phase 5)** : dépend de US2 pour disposer de missions réelles (testable avec les données de démonstration sinon)
- **US4 (Phase 6)** : dépend de US1 seulement — **parallélisable avec US2/US3**
- **US5 (Phase 7)** : dépend de US4 (compte prestataire) et de US3 (composants de mission partagés)
- **US6 (Phase 8)** : dépend de US2 ou US3 (une mission porte le fil)
- **US7 (Phase 9)** : dépend de US1 ; le routage complet suppose US3 et US6
- **US8 (Phase 10)** : dépend de US4
- **US9 (Phase 11)** : dépend de US3
- **US10 (Phase 12)** : dépend de US2 et US3 (données à mettre en cache)
- **Polish (Phase 13)** : dépend des récits retenus pour la livraison

### Within Each User Story

- Fixtures → tests de contrat → modèles → dépôts → écrans → test d'intégration
- Les tests de contrat doivent **échouer** avant l'implémentation du dépôt correspondant
- Les modèles marqués [P] d'un même récit sont parallélisables
- Un récit est terminé avant de passer au suivant, sauf répartition en équipe

### Parallel Opportunities

- Phase 1 : T003 à T012 en parallèle après T001–T002
- Phase 2 : T013, T014, T016, T018, T019, T022, T023, T024, T026, T027, T029 à T035, T037, T040, T042 en parallèle ; puis T015, T017, T020, T021, T025, T028, T036, T038, T039, T041
- Phase 2 tests : T043 à T051 tous en parallèle
- Toutes les tâches de fixtures et de tests de contrat d'un même récit sont parallélisables
- **US4 (onboarding prestataire) est parallélisable avec US2/US3 dès la fin d'US1** — les deux surfaces ne partagent que le socle

---

## Parallel Example: User Story 2

```bash
# Tests de contrat lancés ensemble (après les fixtures T083) :
Task: "Test de contrat catalogue dans test/contract/catalog_repository_test.dart"
Task: "Test de contrat recherche dans test/contract/search_repository_test.dart"
Task: "Test de contrat fiche publique dans test/contract/provider_public_test.dart"
Task: "Test de contrat carnet d'adresses dans test/contract/address_repository_test.dart"
Task: "Test de contrat réservation dans test/contract/booking_repository_test.dart"

# Modèles lancés ensemble :
Task: "Modèles catalogue dans lib/features/search/domain/"
Task: "Modèles de recherche dans lib/features/search/domain/"
Task: "Modèles de fiche publique dans lib/features/search/domain/"
Task: "Modèle Address dans lib/features/profile/domain/address.dart"
```

---

## Implementation Strategy

### MVP First (US1 seul)

1. Phase 1 : Setup
2. Phase 2 : Foundational (**critique — bloque tout**)
3. Phase 3 : US1
4. **ARRÊT et VALIDATION** : scénarios 1.1 à 1.10 de quickstart.md
5. Démonstration possible : un utilisateur crée un compte, se connecte, reste connecté

### Incremental Delivery

1. Setup + Foundational → socle prêt
2. + US1 → **MVP** (compte et session)
3. + US2 → boucle de valeur complète (chercher → réserver) — c'est le vrai jalon produit
4. + US3 → suivi client
5. + US4 → offre prestataire constituable
6. + US5 → cycle de mission complet des deux côtés
7. + US6, US7 → réactivité et mise en relation
8. + US8, US9 → vie du compte et confiance
9. + US10 → confort terrain

### Parallel Team Strategy

Après la Phase 2, avec deux développeurs :

- **Développeur A** : US1 → US2 → US3 → US6 → US9 (surface client)
- **Développeur B** : US4 → US5 → US8 (surface prestataire), démarrage dès la fin d'US1
- **À deux** : US7 (notifications) et US10 (hors ligne), qui touchent les deux surfaces

---

## Notes

- Les tâches [P] portent sur des fichiers différents et n'ont pas de dépendance en cours
- Chaque récit reste indépendamment testable via les scénarios de [quickstart.md](./quickstart.md)
- Vérifier que les tests de contrat échouent avant d'implémenter le dépôt visé
- Livrer par petits lots et s'arrêter à chaque point de contrôle pour valider
- Rappels récurrents : `/api/v1` déjà dans la base d'API, `10.0.2.2` sur émulateur
  Android, clé d'idempotence jamais générée dans une méthode de construction, heures
  `HH:MM` jamais converties de fuseau, dates d'intervention toujours en UTC
