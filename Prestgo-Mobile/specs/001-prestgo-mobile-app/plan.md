# Implementation Plan: Application mobile PRESTGO (client + prestataire)

**Branch**: `001-prestgo-mobile-app` | **Date**: 2026-07-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-prestgo-mobile-app/spec.md`

## Summary

Livrer une application mobile Flutter unique portant les deux surfaces PRESTGO
(client et prestataire) au-dessus du service REST existant, dont le contrat est
figé et vérifié dans
[docs/PRESTGO-Mobile-Flutter-Cahier-des-charges.md](../../docs/PRESTGO-Mobile-Flutter-Cahier-des-charges.md)
(90 opérations hors back-office).

Approche technique : un socle transverse (`core/`) porte l'unique modèle
d'enveloppe de réponse, l'unique exception applicative, l'intercepteur
d'authentification à renouvellement sérialisé, la clé d'idempotence, le cache de
lecture et le service de notifications ; au-dessus, un découpage **feature-first**
sépare la surface client de la surface prestataire, les deux ne partageant que le
socle et les fonctionnalités communes (authentification, profil, messagerie,
notifications). L'état est géré avec Riverpod (`AsyncValue` couvre nativement le
triptyque chargement/erreur/vide qui domine l'application), la navigation avec
`go_router` (un unique `redirect` porte le gardien d'authentification et
l'aiguillage par rôle), et **aucune machine à états métier n'est dupliquée côté
client** : les transitions de mission et la complétude du dossier prestataire sont
lues auprès du service, jamais recalculées.

Le chemin critique est la boucle de valeur *chercher → réserver* (US2), qui dépend
d'US1 ; l'onboarding prestataire (US4) peut être mené en parallèle dès la fin
d'US1 car les deux surfaces ne partagent que le socle.

## Technical Context

**Language/Version**: Dart 3.10.3 / Flutter 3.38.4 stable (version installée et
vérifiée sur le poste ; `environment: sdk: ^3.10.0`)

**Primary Dependencies**:
`flutter_riverpod` + `riverpod_annotation`/`riverpod_generator` (état),
`dio` (HTTP, intercepteurs de première classe pour le rejeu après renouvellement),
`go_router` (navigation déclarative + redirection unique),
`flutter_secure_storage` (jetons — Keychain / Keystore),
`freezed` + `json_serializable` (modèles immuables et sérialisation),
`firebase_core` + `firebase_messaging` + `flutter_local_notifications` (push et
bannière au premier plan), `uuid` (clé d'idempotence),
`intl` (formats `fr_CI`, montants XOF), `connectivity_plus` (bannière hors ligne),
`drift` (cache de lecture persistant), `geolocator` + `flutter_map` +
`latlong2` (sélecteur de position pour le carnet d'adresses),
`image_picker` / `file_picker` + `flutter_image_compress` (justificatifs, photo de
profil, portfolio, pièces jointes), `cached_network_image` (avatars et
réalisations), `sentry_flutter` (rapport d'incident porteur du `correlationId`).

**Storage**:
- Jetons de session et jeton d'appareil : `flutter_secure_storage` uniquement.
- Cache de lecture persistant (profil, catalogue, carnet d'adresses, 1re page des
  missions, détail de mission, fils de discussion) : base locale `drift`.
- Recherche, fiche publique et notifications : cache **mémoire seulement**
  (résultats dépendants de la position et de l'heure).
- Aucun contenu de fichier `sensitive` (justificatifs) n'est écrit sur disque.

**Testing**: `flutter_test` (unitaires + widgets), `mocktail` (doublures),
`http_mock_adapter` (contrats dio rejoués sur les captures JSON réelles du cahier
des charges), `integration_test` (parcours de bout en bout sur émulateur contre
l'API de démonstration), `golden_toolkit` limité aux composants d'état partagés
(vide / erreur / chargement).

**Target Platform**: Android 8.0 (API 26) et plus, iOS 14 et plus — planchers
imposés par `firebase_messaging`, `flutter_secure_storage` et `geolocator`.

**Project Type**: application mobile — **un seul paquet Flutter** à la racine du
dépôt, organisé en modules de fonctionnalités (feature-first). L'API est un
service externe déjà en production : aucun code serveur n'est produit ici.

**Performance Goals**:
- Premier écran de résultats de recherche visible en moins de 2 s sur connexion
  mobile moyenne, état de chargement affiché sous 1 s (SC-005).
- Démarrage à froid jusqu'à l'écran d'atterrissage routé en moins de 3 s (cache de
  `GET /me` servi immédiatement, revalidation en arrière-plan).
- Défilement des listes paginées à 60 images/s sur un appareil d'entrée de gamme
  (Android API 26, 2 Go de RAM).
- Sessions sans plantage ≥ 99,5 % (SC-010).

**Constraints**:
- Jeton d'accès de 15 minutes, jeton de renouvellement de 7 jours avec **rotation**
  : un seul renouvellement en vol, requêtes concurrentes mises en file, rejeu
  unique, jeton de renouvellement systématiquement remplacé.
- Écritures hors ligne **interdites** — aucune file d'attente différée.
- Aucun flux temps réel (ni WebSocket, ni SSE) : rafraîchissement à l'ouverture, au
  geste, au retour au premier plan et sur notification.
- Réservation protégée par `Idempotency-Key` (durée de vie 10 minutes, 10
  réservations par heure).
- Heures d'agenda manipulées **sans conversion de fuseau** ; dates d'intervention
  échangées en UTC.
- Débits serrés sur l'authentification (5 à 10 appels/minute) : aucun rejeu
  automatique sur ces routes.
- Devise unique XOF, non portée par l'API.

**Scale/Scope**: ~60 écrans, 90 opérations d'API consommées, 2 surfaces de rôle,
10 récits utilisateur, 102 exigences fonctionnelles, 19 entités de domaine.
9 lots de livraison (L0 à L8) définis au §9 du cahier des charges.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**État de la constitution** : [.specify/memory/constitution.md](../../.specify/memory/constitution.md)
est **le gabarit non renseigné** (aucun principe ratifié, aucune version). Aucune
règle de gouvernance projet ne peut donc être opposée à ce plan.

En l'absence de constitution ratifiée, les portes ci-dessous sont dérivées des
invariants explicites du cahier des charges et de la spécification ; elles sont
proposées comme socle à ratifier via `/speckit-constitution`.

| # | Porte | Vérification | Statut (pré-conception) | Statut (post-conception) |
|---|---|---|---|---|
| G1 | **Le serveur est l'autorité métier** — aucune machine à états ni règle de complétude dupliquée côté client | Les transitions de mission et la checklist prestataire sont lues, pas recalculées ; les validations locales servent le confort de saisie, jamais la décision | ✅ | ✅ — [data-model.md](./data-model.md) décrit la machine à états en lecture seule ; FR-041/FR-051/FR-060 |
| G2 | **Un seul modèle d'enveloppe et une seule exception** — aucun écran ne lit `data` brut ni ne teste un code HTTP | Revue de code : `response.data['data']` interdit hors de `core/api/` | ✅ | ✅ — [contracts/api-envelope.md](./contracts/api-envelope.md) |
| G3 | **Aucun seuil métier figé à la compilation** | Les six seuils viennent de `GET /settings/public` ; les constantes ne servent que de repli | ✅ | ✅ — FR-094, [contracts/settings-and-limits.md](./contracts/settings-and-limits.md) |
| G4 | **Aucune écriture différée, aucun rejeu non sûr** | Politique de rejeu explicite par type de requête ; transitions de mission jamais rejouées | ✅ | ✅ — [contracts/retry-and-idempotency.md](./contracts/retry-and-idempotency.md) |
| G5 | **Séparation des surfaces** — un écran client n'importe pas un dépôt prestataire et réciproquement | Découpage feature-first + règle d'import vérifiée par analyse statique | ✅ | ✅ — arborescence ci-dessous |
| G6 | **Aucune donnée sensible sur disque** | Jetons en stockage sécurisé ; contenus `sensitive` jamais mis en cache | ✅ | ✅ — FR-098, [data-model.md](./data-model.md) §Persistance |
| G7 | **Testabilité du contrat** | Chaque dépôt est couvert par un test rejouant les captures JSON réelles du cahier des charges | ✅ | ✅ — [quickstart.md](./quickstart.md) |

**Violations** : aucune. La section *Complexity Tracking* reste vide.

⚠️ **Action recommandée hors de ce plan** : ratifier la constitution
(`/speckit-constitution`) en reprenant G1 à G7, afin que ces portes deviennent
opposables aux revues et non de simples conventions de ce plan.

## Project Structure

### Documentation (this feature)

```text
specs/001-prestgo-mobile-app/
├── plan.md                              # Ce fichier (/speckit-plan)
├── spec.md                              # Spécification fonctionnelle (/speckit-specify)
├── research.md                          # Phase 0 — décisions techniques
├── data-model.md                        # Phase 1 — entités, règles, états
├── quickstart.md                        # Phase 1 — mise en route et validation
├── contracts/                           # Phase 1 — contrats d'interface
│   ├── api-envelope.md                  #   enveloppe, erreurs, pagination
│   ├── api-consumption.md               #   les 90 opérations → dépôts et écrans
│   ├── navigation-routes.md             #   routes go_router et gardiens
│   ├── push-payloads.md                 #   charges utiles de notification → routage
│   ├── retry-and-idempotency.md         #   politique de rejeu par type d'écriture
│   └── settings-and-limits.md           #   seuils serveur et plafonds de saisie
├── checklists/
│   └── requirements.md                  # Qualité de la spécification
└── tasks.md                             # Phase 2 (/speckit-tasks — NON créé ici)
```

### Source Code (repository root)

```text
pubspec.yaml
analysis_options.yaml                    # lints stricts + règles d'import inter-features
build.yaml                               # freezed / json_serializable / riverpod_generator
l10n.yaml                                # localisation fr (+ fr_CI pour les formats)

lib/
├── main.dart                            # amorçage : Firebase, Sentry, ProviderScope
├── bootstrap.dart                       # séquence de démarrage (settings, session, push)
├── app/
│   ├── app.dart                         # MaterialApp.router
│   ├── router.dart                      # go_router + redirection unique (auth + rôle)
│   ├── routes.dart                      # constantes de chemins (cf. contracts/navigation-routes.md)
│   └── theme/
├── core/
│   ├── api/
│   │   ├── api_client.dart              # instance dio configurée + User-Agent applicatif
│   │   ├── api_envelope.dart            # modèle UNIQUE {success,message,data,errors,meta}
│   │   ├── api_exception.dart           # exception UNIQUE + messageForField()
│   │   ├── envelope_interceptor.dart    # conversion erreur → ApiException
│   │   ├── auth_interceptor.dart        # 401 → renouvellement sérialisé → rejeu
│   │   ├── retry_policy.dart            # rejeu des lectures et des écritures sûres
│   │   └── idempotency.dart             # génération et cycle de vie de la clé
│   ├── session/
│   │   ├── secure_token_store.dart
│   │   └── session_controller.dart      # état de session, purge globale à la déconnexion
│   ├── settings/
│   │   ├── public_settings.dart         # seuils serveur + repli
│   │   └── app_constants.dart           # plafonds de saisie, devise, pagination
│   ├── cache/
│   │   ├── local_database.dart          # drift : tables de cache de lecture
│   │   └── stale_while_revalidate.dart
│   ├── connectivity/
│   │   └── offline_gate.dart            # bannière + désactivation des écritures
│   ├── push/
│   │   ├── push_service.dart            # cycle de vie du jeton d'appareil
│   │   └── notification_router.dart     # routage unique (push + notification interne)
│   ├── files/
│   │   └── file_upload_service.dart     # filtrage type/taille, compression, envoi
│   ├── format/
│   │   ├── money.dart                   # XOF, locale fr_CI
│   │   └── datetime.dart                # UTC pour les missions, HH:MM brut pour l'agenda
│   ├── error/
│   │   └── error_reporter.dart          # journalisation du correlationId
│   └── widgets/                         # états vide / erreur / chargement partagés
├── features/
│   ├── auth/                            # inscription, OTP, connexion, mot de passe oublié
│   ├── profile/                         # /me, mot de passe, adresses, favoris, appareils
│   ├── search/                          # recherche, catégories, zones, fiche publique
│   ├── booking/                         # brouillon, récapitulatif, confirmation
│   ├── missions/                        # listes, détail, frise, annulation, reports (2 rôles)
│   ├── reviews/                         # dépôt, mes avis, signalement
│   ├── messaging/                       # fils, conversation, pièces jointes
│   ├── notifications/                   # centre, compteurs
│   ├── disputes/                        # ouverture et suivi
│   ├── provider_onboarding/             # P1 à P9, checklist, soumission, suivi
│   └── provider_space/                  # tableau de bord, offre, zones, agenda,
│                                        # portfolio, justificatifs, actions de mission
└── shared/                              # modèles et widgets réellement partagés

test/
├── unit/                                # validateurs, formateurs, politiques de rejeu
├── contract/                            # dépôts rejouant les captures JSON du cahier des charges
├── widget/                              # écrans clés et états partagés
└── fixtures/                            # captures JSON réelles (§2 à §5 du cahier des charges)

integration_test/
└── flows/                               # parcours de bout en bout (cf. quickstart.md)

android/  ios/                           # projets natifs (permissions, Firebase, App Links)
```

**Structure Decision** : **un seul paquet Flutter à la racine du dépôt**, découpé
en modules de fonctionnalités (`lib/features/<domaine>/{data,domain,presentation}`)
au-dessus d'un socle `lib/core/`. Ce choix suit le §1.2 du cahier des charges et se
justifie par le périmètre : la surface prestataire représente environ la moitié des
écrans et évolue indépendamment de la surface client, alors que les deux partagent
un tiers des routes (authentification, profil, messagerie, notifications,
fichiers). Un découpage par couches placerait chaque évolution dans trois dossiers
éloignés et n'empêcherait pas un écran client d'importer un dépôt prestataire — ici
la frontière est matérialisée par l'arborescence et vérifiée par les règles d'import
de `analysis_options.yaml` (porte G5).

Un découpage en plusieurs paquets (`packages/core`, `packages/client`,
`packages/provider`) a été écarté : il apporterait l'isolation à la compilation au
prix d'une orchestration `melos` et de trois cycles de génération de code, pour une
équipe et un périmètre qui n'en ont pas besoin en V1. Le passage en multi-paquets
reste possible sans réécriture, l'arborescence étant déjà alignée.

## Complexity Tracking

> Aucune violation de porte à justifier : la section reste vide.
