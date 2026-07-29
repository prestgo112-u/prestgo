# PRESTGO — Cahier des charges de l'application mobile Flutter

**Public :** l'équipe Flutter (client + prestataire).
**Statut :** spécification de développement. Aucun code Flutter n'est livré avec ce document.
**Date de rédaction :** 29 juillet 2026.

---

## Méthode de rédaction — à lire avant tout

Chaque route, chaque champ de corps de requête, chaque code d'erreur et chaque
forme de réponse figurant dans ce document a été **vérifié dans le code source
du backend** (contrôleurs NestJS, DTO `class-validator`, DTO de réponse Swagger,
services métier), puis **recoupé avec le document OpenAPI live** obtenu par
`GET http://localhost:3000/api/docs-json` sur un serveur réellement démarré, et
enfin — pour les parcours principaux — **confirmé par de vrais appels HTTP**
contre la base de démonstration.

Les charges utiles JSON reproduites dans ce document sont des **captures réelles**,
pas des exemples reconstruits.

Quand le code ne tranche pas un comportement, c'est écrit explicitement
(« non déterminé par le code »). Quand un écran mobile a besoin d'une donnée
qu'aucun endpoint ne fournit, c'est consigné en **§7 — Écarts détectés**, jamais
comblé par une invention.

### Conventions des exemples curl

Tous les exemples supposent :

```bash
export API=http://localhost:3000/api/v1
```

Le préfixe `api/v1` est posé par `app.setGlobalPrefix("api/v1")`
([main.ts:10](apps/api/src/main.ts:10)) et apparaît donc déjà dans **tous** les
chemins du document OpenAPI. Un client qui concatène `serveur + chemin` ne doit
pas l'ajouter une seconde fois.

Comptes de démonstration utilisés (source : [SEED-DATA.md](Docs/SEED-DATA.md)) :

| Rôle | Email | Mot de passe |
|---|---|---|
| Prestataire **approuvé**, réservable | `provider.ready@prestgo.test` | `prestgo123!` |
| Client | `client.demo@prestgo.test` | `prestgo123!` |
| Prestataire `pending_review` | `kofi.plombier@prestgo.test` | `prestgo123!` |

Identifiants réels observés sur la base de démonstration au 29 juillet 2026
(ils changent à chaque `db:seed` sur une base réinitialisée — les traiter comme
des exemples de **forme**, pas comme des constantes) :

| Ressource | Identifiant |
|---|---|
| Prestataire démo approuvé | `bb1397e8-ff8f-4142-a9f9-b0a0d07dfa5c` |
| Formule « Intervention express » | `8fd727f4-65c7-4086-a72e-0ab231584612` |
| Zone Cocody | `fddb1349-5f23-4307-9560-710c6220c049` |
| Catégorie Plomberie | `13cac995-0ac6-4ab4-9840-9a2969d5770c` |
| Type de service « Réparation de fuite » | `c3fe35c0-9331-47d4-a809-bd63fe69a70f` |

---

## 1. Vue d'ensemble

### 1.1 Stack Flutter recommandée

| Besoin | Choix | Justification |
|---|---|---|
| Gestion d'état | **Riverpod** (`flutter_riverpod` + `riverpod_generator`) | Voir ci-dessous. |
| Client HTTP | **dio** | Intercepteurs de première classe — indispensable pour le rejeu automatique après refresh (§2.3). `http` obligerait à réimplémenter à la main la file d'attente des requêtes suspendues pendant le refresh. |
| Navigation | **go_router** | Routage déclaratif + `redirect` global : le gardien d'authentification et l'aiguillage client/prestataire (§1.3) s'écrivent en un seul endroit, au lieu d'être répétés dans chaque écran. |
| Stockage du token | **flutter_secure_storage** | Keychain iOS / Keystore Android. Le refresh token vaut 7 jours (§2.3) : le mettre dans `SharedPreferences` reviendrait à le stocker en clair. |
| Formulaires | **flutter_form_builder** + `form_builder_validators`, ou `Form`/`TextFormField` natifs | Voir §1.4 : la validation serveur ne renvoie pas de nom de champ, la validation côté client porte donc tout le confort de saisie. |
| Push | **firebase_messaging** (+ APNs sur iOS) | Cohérent avec le canal `push` et le transport FCM déjà câblés côté backend (`FCM_PROJECT_ID` / `FCM_CLIENT_EMAIL` / `FCM_PRIVATE_KEY` dans `.env.example`). |
| Sérialisation | `freezed` + `json_serializable` | Modèles immuables, `copyWith`, unions d'états. |
| Identifiants d'idempotence | `uuid` | Génération de la clé `Idempotency-Key` (§3.6). |

**Pourquoi Riverpod plutôt que Bloc.** Les deux conviennent. Riverpod est retenu
pour trois raisons propres à ce projet :

1. **Beaucoup de lecture, peu de machines à états côté client.** L'essentiel de
   l'application est « appeler un endpoint, afficher le résultat, gérer
   chargement/erreur/vide ». `AsyncValue` couvre ce triptyque nativement ;
   avec Bloc, il faut écrire un `State` scellé à trois branches par écran.
2. **La machine à états des missions vit côté serveur.** Elle est centralisée
   dans [mission-status.machine.ts](apps/api/src/modules/missions/mission-status.machine.ts)
   et appliquée par un service unique. Dupliquer une machine à états côté
   Flutter — ce à quoi Bloc invite — créerait la divergence que le backend s'est
   explicitement donné pour objectif d'éviter. L'application doit **lire** les
   transitions autorisées (§4.4), pas les recalculer.
3. **Invalidation en cascade simple.** Après `POST /missions/:id/accept`, il faut
   rafraîchir la liste des missions, le détail, et le compteur de notifications.
   `ref.invalidate(...)` sur trois providers est plus direct qu'un bus
   d'événements inter-blocs.

Si l'équipe est déjà rodée à Bloc, le document reste applicable tel quel : seule
la couche « présentation » change, jamais le contrat API.

### 1.2 Architecture de dossiers — **feature-first**

```
lib/
  main.dart
  app/
    app.dart                  # MaterialApp.router
    router.dart               # go_router + redirect global (auth + rôle)
    theme/
  core/
    api/
      api_client.dart         # instance dio configurée
      auth_interceptor.dart   # §2.3 — 401 → refresh → rejeu
      api_envelope.dart       # §5.1 — modèle UNIQUE {success,message,data,errors,meta}
      api_exception.dart
      idempotency.dart        # §5.2
    storage/
      secure_token_store.dart
    push/
      push_service.dart       # §5.3
    error/
    widgets/                  # états vides / erreur / chargement partagés
  features/
    auth/                     # login, register, otp, forgot/reset password
      data/    (dto, repository)
      domain/  (modèles)
      presentation/ (écrans, providers Riverpod)
    profile/                  # /me, /me/password, /me/addresses, /me/favorites
    search/                   # /providers/search, /providers/:id/public, /categories, /zones
    booking/                  # POST /missions, mes missions, annulation, report
    reviews/
    messaging/
    notifications/
    provider_onboarding/      # POST /providers/me → submit → attente
    provider_space/           # profil, services, packs, zones, dispos, portfolio, documents
    provider_missions/        # accept/refuse/start/complete
  shared/
```

**Pourquoi feature-first plutôt que layer-first.** Le périmètre se découpe
naturellement en deux applications qui partagent un socle : la surface
prestataire (onboarding + espace + missions) représente à elle seule une bonne
moitié des écrans, et elle évolue indépendamment de la surface client. En
layer-first (`data/`, `domain/`, `presentation/` à la racine), chaque évolution
d'une fonctionnalité toucherait trois dossiers éloignés, et rien n'empêcherait
un écran client d'importer un repository prestataire. Ici, la frontière est
matérialisée par l'arborescence.

**Le socle commun** (`core/` + `features/auth` + `features/profile`) est partagé :
un prestataire est d'abord un utilisateur. Les écrans d'authentification, de
profil (`/me`), de mot de passe, de notifications et de messagerie sont **les
mêmes** pour les deux rôles — ce sont les mêmes routes backend (§6).

### 1.3 Gestion des deux rôles dans une seule application

**Réponse vérifiée dans le code :** oui, un même compte **peut** techniquement
porter les deux profils. Ils vivent dans deux tables distinctes
(`client_profiles`, `provider_profiles`) liées à la même ligne `users`, et
[me.service.ts:64-67](apps/api/src/modules/me/me.service.ts:64) expose leur
existence séparément.

`GET /me` renvoie exactement ceci (capture réelle, compte prestataire démo) :

```json
{
  "success": true,
  "message": "OK",
  "data": {
    "id": "16c4f270-1e00-4afe-ad26-da3bb59a1bd0",
    "firstName": "Provider",
    "lastName": "Ready",
    "email": "provider.ready@prestgo.test",
    "phone": null,
    "status": "active",
    "emailVerified": false,
    "phoneVerified": false,
    "roles": [],
    "hasClientProfile": false,
    "hasProviderProfile": true,
    "providerId": "bb1397e8-ff8f-4142-a9f9-b0a0d07dfa5c",
    "providerValidationStatus": "approved",
    "createdAt": "2026-07-29T16:03:32.864Z"
  }
}
```

Champs et domaines de valeurs (source :
[response-dto.ts](apps/api/src/modules/me/response-dto.ts)) :

| Champ | Type | Valeurs |
|---|---|---|
| `status` | string | `draft`, `pending`, `active`, `rejected`, `suspended`, `deleted` |
| `emailVerified` / `phoneVerified` | bool | dérivés de `emailVerifiedAt` / `phoneVerifiedAt` non nuls |
| `roles` | string[] | codes de rôles **d'administration**. Vide pour un client et un prestataire ordinaires — vérifié sur les deux comptes démo. **Ne pas s'en servir pour aiguiller l'application.** |
| `hasClientProfile` | bool | existence d'une ligne `client_profiles` — **créée automatiquement à `POST /auth/register`** depuis la correction du 29 juillet 2026 (voir encadré ci-dessous) |
| `hasProviderProfile` | bool | existence d'une ligne `provider_profiles` |
| `providerId` | string \| null | identifiant du profil prestataire, `null` sinon |
| `providerValidationStatus` | string \| null | `profile_incomplete`, `pending_review`, `approved`, `changes_requested`, `rejected`, `suspended` |

#### Aiguillage attendu de l'application

`GET /me` est appelé **une fois au démarrage** (après restauration du token) et
**après chaque connexion**. Son résultat pilote la navigation :

| `hasProviderProfile` | `providerValidationStatus` | Écran d'atterrissage |
|---|---|---|
| `false` | `null` | **Espace client**. Une entrée « Devenir prestataire » ouvre le parcours §2.2. |
| `true` | `profile_incomplete` | **Reprise de l'onboarding prestataire** — écran checklist (§2.2, écran P7). |
| `true` | `pending_review` | **Écran d'attente** « dossier en cours de vérification » (§2.2, écran P9). L'espace client reste accessible. |
| `true` | `changes_requested` | **Écran de correction** avec le motif affiché (§2.2, écran P9). |
| `true` | `rejected` | Écran d'information avec le motif. Re-soumission possible **sauf si** `resubmissionBlocked` (voir §2.2). |
| `true` | `approved` | **Espace prestataire complet.** |
| `true` | `suspended` | Écran d'information. Aucune action de gestion, contact support. |

**Sélecteur de rôle.** Quand `hasProviderProfile == true` **et** que
l'utilisateur veut aussi réserver en tant que client, l'application propose un
basculement explicite (menu ou onglet). Les deux espaces coexistent, il n'y a
pas de reconnexion. Le token est le même — le backend ne distingue pas « une
session client » d'« une session prestataire ».

> ✅ **Corrigé depuis la rédaction initiale de ce document (écart n°1, clos).**
> `POST /auth/register` crée désormais la ligne `ClientProfile` **dans la même
> écriture** que le compte
> ([account.service.ts](apps/api/src/modules/auth/account.service.ts)) : tout
> compte inscrit via cette route a `hasClientProfile: true` dès son activation.
> Vérifié par appel réel : inscription → OTP → connexion → `GET /me` renvoie
> `hasClientProfile: true`, `hasProviderProfile: false`.
>
> ⚠️ **Ce flag reste néanmoins à ignorer pour l'aiguillage**, pour deux
> raisons :
> 1. **Comptes antérieurs à la correction** — les comptes de démonstration du
>    seed (`client.demo@prestgo.test`, `provider.ready@prestgo.test`…) et tout
>    compte inscrit avant le déploiement de ce correctif ont
>    `hasClientProfile: false` et le garderont : rien ne les fait rattraper
>    rétroactivement. La capture ci-dessus (compte prestataire démo) date
>    d'avant la correction et reste représentative de ces comptes historiques.
> 2. **Aucune route mobile ne crée de `ClientProfile` en dehors de
>    l'inscription** — un compte créé par une voie différente (import,
>    back-office) resterait à `false`.
>
> **Règle applicable, inchangée :** tout compte authentifié dont le `status`
> est `active` peut utiliser l'espace client, quel que soit `hasClientProfile`.
> Le champ est informatif, pas une condition d'accès.

### 1.4 Un mot sur la validation des formulaires

✅ **Corrigé depuis la rédaction initiale de ce document (écart n°13, clos).**
Les erreurs du `ValidationPipe` NestJS renseignent désormais **`field`** dans
chaque entrée de `errors[]` — l'`exceptionFactory` du pipe global reconstruit le
chemin complet du champ fautif, y compris pour un élément d'un tableau imbriqué
(`slots.1.startTime`, pas seulement `startTime`). Vérifié par appel réel sur
`/auth/register`, `/me/addresses`, `/missions` et `/providers/me/availabilities`.

```json
{
  "success": false,
  "message": "Adresse email invalide",
  "errors": [
    { "field": "email", "code": "validation_error", "message": "Adresse email invalide" },
    { "field": "password", "code": "validation_error", "message": "Le mot de passe doit contenir au moins 8 caractères, dont une lettre et un chiffre" }
  ]
}
```

**Conséquence opérationnelle, désormais possible :** le modèle Dart unique
(§5.1) peut mapper chaque entrée de `errors[]` sur le `TextFormField`
correspondant via `field` (`ApiException.messageForField(fieldName)`), au lieu
de se rabattre systématiquement sur une bannière de formulaire. La validation
côté client (longueurs, formats — toujours documentée endpoint par endpoint
dans ce document) reste nécessaire pour le confort de saisie immédiat, mais
n'est plus la SEULE ligne de défense contre un message mal placé.

**Deux limites qui subsistent :**
- `message` (le champ de tête) reste un texte unique — utile pour un
  `SnackBar` global, pas pour un mapping par champ.
- Les erreurs MÉTIER posées à la main par un service (ex. `409 Cet email ou ce
  numéro est déjà utilisé`) n'ont toujours pas de `field` : seules les erreurs
  du `ValidationPipe` en bénéficient. Continuer à les afficher en bannière.

---

## 2. Authentification et création de compte

C'est la section la plus détaillée du document, comme demandé.

### 2.0 Rappels transverses d'authentification

| Élément | Valeur vérifiée | Source |
|---|---|---|
| Format du jeton d'accès | JWT, `expiresIn: "15m"` | [auth.module.ts:18](apps/api/src/modules/auth/auth.module.ts:18) |
| Charge utile du JWT | `{ sub, roles, permissions, sid }` | [auth.service.ts:8-18](apps/api/src/modules/auth/auth.service.ts:8) |
| Format du jeton de rafraîchissement | **chaîne opaque hexadécimale**, pas un JWT | vérifié en appel réel (`b58c5a76a0aadbf0caaa…`) |
| Durée du refresh token | 7 jours | `REFRESH_TTL_DAYS = 7`, [refresh-session.service.ts:7](apps/api/src/modules/auth/refresh-session.service.ts:7) |
| Rotation | **Oui** : chaque `POST /auth/refresh` révoque l'ancien et en renvoie un nouveau | [auth.controller.ts:54-59](apps/api/src/modules/auth/auth.controller.ts:54) |
| En-tête attendu | `Authorization: Bearer <accessToken>` | [jwt.strategy.ts:9-13](apps/api/src/modules/auth/jwt.strategy.ts:9) |
| 401 sans en-tête | `{"success":false,"message":"Bearer token required","errors":[],"meta":{"correlationId":"…"}}` | appel réel |
| 401 jeton invalide/expiré | message `Invalid access token` | [auth.service.ts:215](apps/api/src/modules/auth/auth.service.ts:215) |

**Politique de débit (`429`)** — [throttle.config.ts](apps/api/src/common/config/throttle.config.ts) :

| Route(s) | Plafond par défaut | Fenêtre |
|---|---|---|
| `POST /auth/login` | 10 | 1 minute |
| `POST /auth/register`, `POST /auth/forgot-password`, `POST /auth/otp/send` | 5 | 1 minute |
| `POST /auth/refresh`, `POST /auth/otp/verify`, `POST /auth/reset-password`, `POST /me/password` | 30 | 1 minute |
| `POST /missions` | 10 | 1 heure |
| `POST /me/devices` | 30 | 1 jour |
| `POST /reviews/:id/report` | 20 | 1 jour |
| Tout le reste | 300 | 1 minute |

L'application doit traiter `429` de façon générique (§5.1) : message
« Trop de tentatives, réessayez dans un instant », et **désactivation temporaire
du bouton** plutôt qu'un rejeu automatique.

---

### 2.1 Inscription client

#### ⚠️ L'ordre réel diffère de l'ordre supposé

L'enchaînement « identité → OTP → mot de passe » n'est **pas** celui du backend.
`POST /auth/register` **exige le mot de passe dès la création**
([dto.ts:18-22](apps/api/src/modules/auth/dto.ts:18)), et **n'envoie aucun code
OTP** — `AccountService.register` ne fait aucun appel à `sendOtp`
([account.service.ts:65-109](apps/api/src/modules/auth/account.service.ts:65)).

**Ordre réel, vérifié par appels HTTP successifs :**

```
POST /auth/register   → 201, compte créé au statut "pending"
POST /auth/otp/send   → 200  (déclenché EXPLICITEMENT par l'application)
POST /auth/otp/verify → 200, { verified: true, activated: true } → statut "active"
POST /auth/login      → 200, { accessToken, refreshToken }
```

Preuve que l'ordre est contraignant : une tentative de `POST /auth/login` entre
`register` et `otp/verify` renvoie **401 `Account is not active`** — vérifié en
appel réel.

#### Diagramme d'écrans

| # | Écran | Sortie |
|---|---|---|
| C1 | **Choix du canal** — email ou téléphone | → C2 |
| C2 | **Identité et contact** — prénom, nom, email et/ou téléphone | → C3 |
| C3 | **Mot de passe** — saisie + confirmation | `POST /auth/register` → C4 |
| C4 | **Vérification OTP** — 6 chiffres, compte à rebours 10 min, lien « renvoyer » | `POST /auth/otp/send` à l'entrée, puis `POST /auth/otp/verify` → C5 |
| C5 | **Connexion automatique** (écran de transition) | `POST /auth/login` puis `GET /me` → accueil client |

C2 et C3 peuvent être fusionnés en un seul écran ; ce qui compte est que
**`register` reçoive contact + mot de passe en un seul appel**.

#### Écran C2 / C3 — champs et validation côté client

| Champ | Obligatoire | Règle serveur exacte | Message serveur |
|---|---|---|---|
| `email` | Optionnel* | `@IsEmail()` | `Adresse email invalide` |
| `phone` | Optionnel* | `^\+?[0-9\s-]{8,20}$` | `Numéro de téléphone invalide` |
| `password` | **Oui** | 8–128 caractères, `^(?=.*[A-Za-z])(?=.*\d).+$` | `Le mot de passe doit contenir au moins 8 caractères, dont une lettre et un chiffre` |
| `firstName` | Optionnel | ≤ 80 caractères | — |
| `lastName` | Optionnel | ≤ 80 caractères | — |

\* **Au moins un des deux** (`email` ou `phone`) est requis. La règle n'est pas
portée par un décorateur mais par le service
([account.service.ts:69-71](apps/api/src/modules/auth/account.service.ts:69)) :
sinon → `400 Un email ou un numéro de téléphone est obligatoire`.

Le champ « confirmation du mot de passe » est **purement côté client** — il
n'existe pas dans le DTO.

#### `POST /auth/register`

```bash
curl -i -X POST "$API/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "email": "awa.nouvelle@prestgo.test",
    "phone": "+225 07 00 11 22 33",
    "password": "prestgo123!",
    "firstName": "Awa",
    "lastName": "Koné"
  }'
```

**Réponse 201 (capture réelle) :**

```json
{
  "success": true,
  "message": "Compte créé. Vérifiez votre téléphone ou votre email pour l'activer.",
  "data": {
    "id": "97147fa2-41f1-4e95-ba3c-3b572f85514e",
    "email": "spec.check.1785344019@prestgo.test",
    "phone": null,
    "status": "pending",
    "createdAt": "2026-07-29T16:53:40.145Z"
  }
}
```

Aucun token n'est renvoyé. `data.status` vaut toujours `pending`.

| Code | Message serveur | Réaction de l'UI |
|---|---|---|
| **201** | `Compte créé. Vérifiez…` | Naviguer vers C4 et déclencher immédiatement `otp/send`. Mémoriser le `target` (email ou téléphone) et le mot de passe **en mémoire volatile** pour la connexion automatique en C5. |
| **400** | `Adresse email invalide` / `Numéro de téléphone invalide` / message mot de passe / `Un email ou un numéro de téléphone est obligatoire` | Bannière au-dessus du formulaire. Voir §1.4 : pas de mapping par champ possible. |
| **409** | `Un compte existe déjà avec cet email ou ce numéro` | Bannière + bouton « Se connecter » et « Mot de passe oublié ». |
| **429** | (message du throttler) | « Trop de tentatives. Réessayez dans une minute. » Bouton désactivé 60 s. |

#### `POST /auth/otp/send`

Corps ([dto.ts:55-65](apps/api/src/modules/auth/dto.ts:55)) : `target` (4–120
caractères, le numéro ou l'email), `purpose` optionnel parmi
`phone_verification` (défaut), `email_verification`, `login`.

Le backend choisit le transport en inspectant `target` : SMS si
`^\+?[0-9\s-]{8,20}$` correspond, email sinon
([account.service.ts:268](apps/api/src/modules/auth/account.service.ts:268)).

```bash
curl -i -X POST "$API/auth/otp/send" \
  -H "Content-Type: application/json" \
  -d '{"target":"awa.nouvelle@prestgo.test","purpose":"email_verification"}'
```

**Réponse 200 (capture réelle) :**

```json
{
  "success": true,
  "message": "Un code de vérification a été envoyé.",
  "data": { "message": "Un code de vérification a été envoyé.", "expiresInMinutes": 10 }
}
```

Points de comportement vérifiés :

- La réponse est **identique que le compte existe ou non** — volontaire, pour ne
  pas révéler qui est inscrit. L'application ne peut donc **pas** utiliser cette
  route pour tester l'existence d'un compte.
- Un envoi invalide les codes précédents du même couple (`target`, `purpose`) :
  **un seul code actif à la fois**.
- Durée de vie : **10 minutes** (`expiresInMinutes` est renvoyé, l'utiliser pour
  le compte à rebours plutôt qu'une constante en dur).
- `devCode` n'apparaît dans la réponse **que** si `AUTH_EXPOSE_DEV_CODES=true`.
  Cette variable est **commentée** dans le `.env` du dépôt — le champ est donc
  absent en pratique. L'application doit traiter `devCode` comme optionnel et ne
  jamais le pré-remplir en build de production.

| Code | Réaction de l'UI |
|---|---|
| 200 | Démarrer le compte à rebours sur `data.expiresInMinutes`. Bouton « Renvoyer » grisé jusqu'à expiration (ou 60 s minimum, pour respecter le plafond de 5/minute). |
| 400 | Corps mal formé (`target` trop court, `purpose` inconnu). Bannière. |
| 429 | 5 envois/minute dépassés. Griser « Renvoyer » 60 s. |

#### `POST /auth/otp/verify`

Corps : `target`, `code` (**exactement 6 chiffres**, `^\d{6}$`), `purpose`
optionnel — **doit être le même qu'à l'envoi**, sinon le code n'est pas retrouvé.

```bash
curl -i -X POST "$API/auth/otp/verify" \
  -H "Content-Type: application/json" \
  -d '{"target":"awa.nouvelle@prestgo.test","code":"418302","purpose":"email_verification"}'
```

**Réponse 200 :**

```json
{
  "success": true,
  "message": "Compte activé",
  "data": { "verified": true, "activated": true }
}
```

- `message` vaut **`Compte activé`** si le compte est passé de `pending` à
  `active`, **`Code vérifié`** sinon
  ([auth.controller.ts:110](apps/api/src/modules/auth/auth.controller.ts:110)).
- `data.activated` porte la même information de façon exploitable :
  `true` uniquement si le statut était `pending`
  ([account.service.ts:339](apps/api/src/modules/auth/account.service.ts:339)).
  **C'est ce champ que l'application doit tester**, pas le message.
- Un compte `suspended` ne se réactive pas en vérifiant son téléphone : la
  transition n'est appliquée que depuis `pending`.

| Code | Message serveur | Réaction de l'UI |
|---|---|---|
| **200**, `activated: true` | `Compte activé` | Enchaîner sur `POST /auth/login` (écran C5). |
| **200**, `activated: false` | `Code vérifié` | Cas d'une vérification d'un email/téléphone modifié sur un compte déjà actif (§3.1). Revenir à l'écran d'origine avec un message de succès. |
| **400** | `Code invalide ou expiré` | ⚠️ **Message volontairement ambigu** : le backend renvoie le même texte pour un code faux, un code expiré et un code déjà utilisé. Afficher « Code incorrect ou expiré », vider le champ, proposer « Renvoyer un code ». Vérifié en appel réel. |
| **401** | `Trop de tentatives. Demandez un nouveau code.` | Après **5 tentatives** sur le même code (`OTP_MAX_ATTEMPTS`). Désactiver la saisie, forcer le passage par « Renvoyer un code ». |
| **429** | — | 30 vérifications/minute dépassées. |

#### `POST /auth/login` (fin du parcours C5)

Voir §2.3 pour le détail complet. Après succès : stocker les deux jetons,
appeler `GET /me`, enregistrer le jeton push (§5.3), naviguer vers l'accueil.

---

### 2.2 Inscription prestataire — le parcours le plus long

#### Prérequis

Le parcours prestataire **démarre sur un compte utilisateur déjà actif**. Il n'y
a pas de `POST /auth/register` spécifique au prestataire : le champ
« type de compte » n'existe pas dans le DTO d'inscription. Deux entrées possibles :

- un visiteur crée un compte via §2.1, puis choisit « Devenir prestataire » ;
- un client existant choisit « Devenir prestataire » depuis son espace.

Dans les deux cas, l'appel qui bascule est `POST /providers/me`.

#### Diagramme d'écrans

| # | Écran | Appel(s) |
|---|---|---|
| P0 | Compte utilisateur créé et activé | §2.1 |
| P1 | **Présentation du parcours** (les 5 étapes de la checklist, les justificatifs attendus) | `GET /providers/me/documents` peut être appelé plus tard ; ici, purement informatif |
| P2 | **Création du profil prestataire** — nom public, présentation, années d'expérience | `POST /providers/me` |
| P3 | **Déclaration d'un service** — catégorie/type + titre + description | `GET /categories` puis `POST /providers/me/services` |
| P4 | **Déclaration d'une formule** — titre, description, prix, durée | `POST /providers/me/service-packs` |
| P4b | *(optionnel)* **Options de la formule** | `POST /providers/me/service-packs/:packId/options` |
| P5 | **Zones d'intervention** — liste à cocher | `GET /zones` puis `PUT /providers/me/zones` |
| P6 | **Disponibilités hebdomadaires** — grille 7 jours × créneaux | `PUT /providers/me/availabilities` |
| P7 | **Justificatifs** — upload puis rattachement | `GET /providers/me/documents`, `POST /files/upload`, `POST /providers/me/documents` |
| P8 | **Checklist de complétude** — 5 items verts/rouges, bouton « Soumettre » | `GET /providers/me` puis `POST /providers/me/submit` |
| P9 | **Suivi du dossier** — état, motif, actions | `GET /providers/me` (polling ou pull-to-refresh) |

L'ordre P3 → P7 est **libre** côté backend : aucune de ces routes n'exige que la
précédente ait réussi. L'application peut donc présenter P8 (la checklist) comme
un **hub** dont chaque ligne rouge ouvre l'étape correspondante, plutôt qu'un
tunnel linéaire. C'est la présentation recommandée : elle est aussi celle qui
gère naturellement la reprise après `changes_requested`.

**Toutes les routes `/providers/me/*` répondent `403` avec le message
`Authentification requise, ou ce compte n'a pas de profil prestataire`** tant que
`POST /providers/me` n'a pas réussi
([provider-context.service.ts](apps/api/src/modules/providers/provider-context.service.ts)).
Message exact levé par le service : `Ce compte n'a pas de profil prestataire`.

---

#### P2 — `POST /providers/me` (créer le profil prestataire)

Corps ([self-dto.ts:20-38](apps/api/src/modules/providers/self-dto.ts:20)) :

| Champ | Obligatoire | Règle |
|---|---|---|
| `publicName` | **Oui** | 2–120 caractères. Message : `Le nom public doit contenir au moins 2 caractères` |
| `bio` | Non (mais **requis pour la checklist**, voir P8) | ≤ 2000 caractères. Chaîne vide → traitée comme `undefined` |
| `experienceYears` | Non | entier 0–70. Message : `L'expérience doit être un nombre d'années` |

```bash
curl -i -X POST "$API/providers/me" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "publicName": "Koffi Électricité Générale",
    "bio": "Électricien depuis 8 ans à Abidjan. Installation, dépannage, mise aux normes.",
    "experienceYears": 8
  }'
```

**Réponse 201** — le corps est **le même DTO que `GET /providers/me`**
(`ProviderOverviewDto`), c'est-à-dire l'aperçu complet avec la checklist déjà
calculée. L'application peut donc alimenter l'écran P8 directement avec cette
réponse, sans second appel.

| Code | Message | Réaction de l'UI |
|---|---|---|
| **201** | `Profil prestataire créé. Complétez votre dossier pour le soumettre.` | Stocker `data.id` (le `providerId`). Naviguer vers P8 (hub checklist). |
| **400** | validation | Bannière. |
| **401** | `Bearer token required` / `Invalid access token` | Intercepteur (§2.3). |
| **409** | `Ce compte a déjà un profil prestataire` | **Ne pas traiter comme une erreur** : appeler `GET /providers/me` et naviguer vers P8. Ce cas survient à la reprise d'un parcours interrompu. |

---

#### P3 — `POST /providers/me/services`

Le catalogue des types de service se lit sur la route **publique**
`GET /categories` (capture réelle) :

```bash
curl -s "$API/categories"
```

```json
{
  "success": true,
  "message": "OK",
  "data": [
    {
      "id": "13cac995-0ac6-4ab4-9840-9a2969d5770c",
      "name": "Plomberie",
      "slug": "plomberie",
      "description": "Services de plomberie",
      "iconFileId": null,
      "active": true,
      "displayOrder": 1,
      "createdAt": "2026-07-19T11:16:12.629Z",
      "updatedAt": "2026-07-19T11:16:12.629Z",
      "serviceTypes": [
        { "id": "c3fe35c0-9331-47d4-a809-bd63fe69a70f", "name": "Réparation de fuite", "slug": "reparation-fuite", "description": null }
      ]
    }
  ]
}
```

L'écran présente un sélecteur à deux niveaux (catégorie → type de service).
`data` est **un tableau nu, sans `meta`** : pas de pagination sur cette route.

Corps de création ([self-dto.ts:78-92](apps/api/src/modules/providers/self-dto.ts:78)) :

| Champ | Obligatoire | Règle |
|---|---|---|
| `serviceTypeId` | **Oui** | UUID. Message : `Type de service invalide` |
| `title` | **Oui** | 3–150 caractères. Message : `Le titre doit contenir au moins 3 caractères` |
| `description` | Non | ≤ 1000 caractères |

```bash
curl -i -X POST "$API/providers/me/services" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "serviceTypeId": "c3fe35c0-9331-47d4-a809-bd63fe69a70f",
    "title": "Dépannage plomberie à domicile",
    "description": "Fuites, robinetterie, évacuation."
  }'
```

**Réponse 201** — forme brute Prisma (`ProviderServiceDto`) :
`{ id, providerId, serviceTypeId, title, description, active, createdAt }`.
**Retenir `data.id`** : c'est le `providerServiceId` exigé à l'étape P4.

| Code | Message | Réaction de l'UI |
|---|---|---|
| 201 | `Service déclaré` | Enchaîner sur P4 avec `providerServiceId = data.id`. |
| 403 | `Ce compte n'a pas de profil prestataire` | Renvoyer vers P2. |
| **404** | `Type de service introuvable ou inactif` | Le catalogue a changé. Recharger `GET /categories`. |
| **409** | `Vous proposez déjà un service actif de ce type` | Rediriger vers le service existant (`GET /providers/me/services`) plutôt que d'afficher une erreur brute. |

---

#### P4 — `POST /providers/me/service-packs` (prix et durée)

⚠️ **Cette route vit dans le module `catalog`, pas dans `providers`** — c'est
sans conséquence côté client, mais explique qu'elle soit absente de
`provider-self.controller.ts`.

Corps ([dto.ts:92-116](apps/api/src/modules/catalog/dto.ts:92)) :

| Champ | Obligatoire | Règle |
|---|---|---|
| `providerServiceId` | **Oui** | UUID du service créé en P3 |
| `title` | **Oui** | 2–150 caractères |
| `description` | Non | ≤ 2000 caractères |
| `price` | **Oui** | nombre **≥ 0**. Messages : `Le prix doit être un nombre` / `Le prix ne peut pas être négatif` |
| `durationMinutes` | **Oui** | entier **5–1440**. Messages : `La durée minimale est de 5 minutes` / `La durée ne peut pas dépasser une journée (1440 minutes)` |

La devise n'est **pas** portée par l'API : `price` est un nombre nu. Les données
de démonstration sont en XOF ; l'affichage de l'unité est une décision
d'application, à figer côté Flutter (`XOF`).

```bash
curl -i -X POST "$API/providers/me/service-packs" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "providerServiceId": "4698c3da-7697-41b5-8c6d-946fdcec95f0",
    "title": "Intervention express",
    "description": "Petite réparation, sur place en moins d'une heure.",
    "price": 5000,
    "durationMinutes": 45
  }'
```

| Code | Message | Réaction de l'UI |
|---|---|---|
| 201 | `Formule créée` | La case « services » de la checklist passe au vert **seulement maintenant** — voir P8. |
| 403 | `Ce compte n'a pas de profil prestataire` | — |
| 404 | `Service introuvable pour ce prestataire` | Le `providerServiceId` ne correspond pas. Recharger `GET /providers/me/services`. |

**Options (P4b, facultatif)** —
`POST /providers/me/service-packs/:packId/options`, corps
`{ title (2–150), price (≥ 0), durationMinutes? (0–1440, défaut 0) }`. Les
options remontent ensuite dans `optionIds` à la réservation (§3.6).

---

#### P5 — `PUT /providers/me/zones`

Les zones disponibles se lisent sur la route publique `GET /zones` (zones
actives uniquement) ou `GET /zones/nearby?latitude=…&longitude=…&radiusKm=…`.

Corps ([self-dto.ts:119-125](apps/api/src/modules/providers/self-dto.ts:119)) :
`{ "zoneIds": ["<uuid>", …] }`.

**C'est un `PUT`, pas un `POST` : le tableau envoyé remplace intégralement la
liste.** L'écran est une liste à cocher qui envoie l'état complet.

| Contrainte | Valeur | Message |
|---|---|---|
| Doublons | interdits | `La même zone est indiquée plusieurs fois` |
| Nombre max | **15** (`MAX_PROVIDER_ZONES`) | `Pas plus de 15 zones` (DTO) / `Vous ne pouvez pas couvrir plus de 15 zones` (service) |
| Format | UUID | `Chaque zone doit être un identifiant valide` |
| Liste vide | **acceptée** — signifie « je ne couvre plus aucune zone » | — |

```bash
curl -i -X PUT "$API/providers/me/zones" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"zoneIds":["fddb1349-5f23-4307-9560-710c6220c049"]}'
```

**Réponse 200** — tableau des zones à jour :
`[{ id, name, latitude, longitude, radiusKm, active, city: { id, name } }]`.

| Code | Message | Réaction de l'UI |
|---|---|---|
| 200 | `Zones d'intervention mises à jour` | Rafraîchir la checklist. |
| **400** | `Zone inconnue ou inactive : <uuid>, <uuid>` | Le contrôle est **atomique** : rien n'est écrit si une seule zone est invalide. Recharger `GET /zones` et réafficher. |
| 403 | `Ce compte n'a pas de profil prestataire` | — |

⚠️ **Attention à l'écran vide** : envoyer un tableau vide efface toutes les
zones et fait disparaître le prestataire de la recherche. Exiger une
confirmation explicite si la liste passe de non-vide à vide.

---

#### P6 — `PUT /providers/me/availabilities`

Corps ([dto.ts:32-54](apps/api/src/modules/availability/dto.ts:32)) :

```json
{ "slots": [ { "weekday": 1, "startTime": "08:00", "endTime": "18:00" } ] }
```

| Champ | Règle | Message |
|---|---|---|
| `weekday` | entier **0–6**, **0 = dimanche**, 6 = samedi | `Le jour va de 0 (dimanche) à 6 (samedi)` |
| `startTime` / `endTime` | `^([01]\d\|2[0-3]):[0-5]\d$` — « HH:MM » sur 24 h | `L'heure de début doit être au format HH:MM` |
| `slots` | ≤ **50** entrées | `Un agenda hebdomadaire ne peut pas dépasser 50 créneaux` |

⚠️ **Les heures sont interprétées en UTC.** La vérification de disponibilité à
la réservation compare `scheduledAt.getUTCDay()` et
`` `${getUTCHours()}:${getUTCMinutes()}` `` aux créneaux stockés
([mission-booking.service.ts:412-425](apps/api/src/modules/missions/mission-booking.service.ts:412)).
La Côte d'Ivoire est à UTC+0, donc heure locale = heure UTC — mais **l'écran ne
doit pas convertir les heures dans le fuseau de l'appareil**, sous peine de
décaler l'agenda d'un utilisateur en déplacement. Afficher et envoyer les
« HH:MM » tels quels.

```bash
curl -i -X PUT "$API/providers/me/availabilities" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "slots": [
      { "weekday": 1, "startTime": "08:00", "endTime": "12:00" },
      { "weekday": 1, "startTime": "14:00", "endTime": "18:00" },
      { "weekday": 2, "startTime": "08:00", "endTime": "18:00" }
    ]
  }'
```

| Code | Message documenté | Réaction de l'UI |
|---|---|---|
| 200 | `Disponibilités mises à jour` | Rafraîchir la checklist. |
| **400** | `Jour hors 0-6, heure de fin avant l'heure de début, ou créneaux qui se chevauchent` | Le contrôle du chevauchement et de l'ordre des heures est fait **côté service**, avec des messages non exposés dans les décorateurs Swagger. **Reproduire les deux règles côté client** (fin > début ; pas de chevauchement sur un même `weekday`) pour ne pas dépendre du message serveur. |
| 403 | `Ce compte n'a pas de profil prestataire` | — |

**Absences exceptionnelles** (hors checklist, disponible après approbation) :
`POST /providers/me/unavailabilities` avec
`{ startAt (ISO), endAt (ISO), reason? (≤300) }`, et
`DELETE /providers/me/unavailabilities/:id`.
400 si `endAt < startAt` ou chevauchement d'une absence existante.

---

#### P7 — Justificatifs : upload en deux temps

Le découpage est volontaire
([provider-self.controller.ts:157-163](apps/api/src/modules/providers/provider-self.controller.ts:157)) :
l'application gère l'envoi du binaire (progression, reprise) indépendamment de
la règle métier.

**Étape 1 — `POST /files/upload`** (`multipart/form-data`)

| Élément | Valeur |
|---|---|
| Champ du fichier | **`file`** (nom exact) |
| Champ optionnel | `visibility` ∈ { `restricted`, `sensitive` } — toute autre valeur est **silencieusement ramenée à `restricted`** |
| Taille max | **10 Mo** (`MAX_UPLOAD_BYTES`) |
| Types acceptés | `image/jpeg`, `image/png`, `image/webp`, `application/pdf`, `text/plain`, `text/csv` |

```bash
curl -i -X POST "$API/files/upload" \
  -H "Authorization: Bearer $TOKEN" \
  -F "file=@/chemin/vers/cni-recto.jpg" \
  -F "visibility=sensitive"
```

Réponse 200, `message: "Fichier enregistré"`, `data` = ligne `File` complète.
**Retenir `data.id`.**

| Code | Message | Réaction de l'UI |
|---|---|---|
| 200 | `Fichier enregistré` | Passer à l'étape 2 avec `fileId = data.id`. |
| **400** | `Aucun fichier reçu (champ attendu : « file »)` | Bug d'intégration : le champ multipart est mal nommé. |
| **400** | `Type de fichier non autorisé : <mime>` | Filtrer côté client **avant** l'envoi (le `image_picker` / `file_picker` doit restreindre aux types ci-dessus). |
| **413** | (Multer) | Dépassement des 10 Mo. Compresser l'image côté client avant l'envoi. |

**Étape 2 — `POST /providers/me/documents`**

Corps : `{ type (2–60 caractères), fileId (UUID) }`.

Les types **exigés** ne sont pas codés en dur : ils viennent du réglage
`provider.required_document_types`, valeur de repli `["id_card"]`
([settings.keys.ts:24](apps/api/src/modules/settings/settings.keys.ts:24)).
L'application **lit la liste** via `GET /providers/me/documents` ou
`GET /providers/me` (`requiredDocumentTypes`) et **construit son écran à partir
de là** — coder « pièce d'identité » en dur casserait le jour où un second
justificatif est exigé.

```bash
curl -i -X POST "$API/providers/me/documents" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type":"id_card","fileId":"1f2e3d4c-5b6a-4788-9900-aabbccddeeff"}'
```

| Code | Message | Réaction de l'UI |
|---|---|---|
| 201 | `Justificatif transmis` | Rafraîchir `GET /providers/me/documents`. |
| **400** | `Le type de document est obligatoire` | — |
| **400** | `Votre justificatif « id_card » est déjà validé` | Un document `approved` ne se remplace pas. Griser l'action de re-dépôt sur les lignes `approved`. |
| 403 | `Ce compte n'a pas de profil prestataire` | — |
| **404** | `Fichier introuvable ou ne vous appartenant pas` | Le `fileId` n'appartient pas au compte connecté ou a été désactivé. Recommencer l'étape 1. |

Comportements vérifiés à retenir :

- La visibilité du fichier est **forcée à `sensitive`** au rattachement, quelle
  qu'ait été celle du dépôt.
- Re-soumettre **crée une nouvelle version** (`version` incrémenté), sans
  effacer la précédente : l'agent voit l'ancienne à côté de la nouvelle.
- **Effet de bord important :** si le dossier est en `changes_requested`, le
  simple dépôt d'un justificatif le repasse **automatiquement** en
  `pending_review` (avec `submittedAt` remis à jour et `rejectionReason` effacé)
  — [provider-documents-self.service.ts:140-145](apps/api/src/modules/documents/provider-documents-self.service.ts:140).
  L'application doit donc **rafraîchir `GET /providers/me` après chaque dépôt**
  et ne pas supposer que le statut est resté `changes_requested`.

**`GET /providers/me/documents`** (capture réelle, compte démo) :

```json
{
  "success": true,
  "message": "OK",
  "data": {
    "requiredTypes": ["id_card"],
    "missingTypes": ["id_card"],
    "documents": [],
    "current": []
  }
}
```

| Champ | Usage à l'écran |
|---|---|
| `requiredTypes` | Construit la liste des lignes à afficher. |
| `missingTypes` | Types **sans justificatif exploitable** (absent, sans fichier, ou `rejected`) → lignes rouges. |
| `current` | **Dernière version de chaque type** → c'est ce qui est affiché par ligne. |
| `documents` | Toutes les versions, du plus récent au plus ancien par type → écran « historique » repliable. |

Chaque document porte `{ id, type, status (pending\|approved\|rejected), version,
rejectionReason?, reviewedAt?, createdAt, file: { id, originalName, mimeType, size } }`.
**`rejectionReason` est la donnée clé de l'écran de correction** : elle dit au
prestataire ce qu'il doit refaire.

Pour afficher l'aperçu d'un justificatif déjà déposé :
`GET /files/:id/content` avec le `Bearer` (renvoie le binaire, `Content-Type`
d'origine, `Content-Disposition: inline`).

---

#### P8 — Écran « checklist de complétude »

Source unique : `GET /providers/me`. **Capture réelle** (compte démo approuvé) :

```json
{
  "success": true,
  "message": "OK",
  "data": {
    "id": "bb1397e8-ff8f-4142-a9f9-b0a0d07dfa5c",
    "publicName": "PRESTGO Demo — Plomberie Express",
    "bio": "Compte de démonstration déjà approuvé, pour tester le parcours de réservation sans passer par la validation manuelle.",
    "experienceYears": 6,
    "validationStatus": "approved",
    "availabilityStatus": "available",
    "score": 4.5,
    "reviewsCount": 12,
    "checklist": {
      "profile": true,
      "services": true,
      "zones": true,
      "availabilities": true,
      "documents": false
    },
    "requiredDocumentTypes": ["id_card"],
    "rejectionReason": null,
    "resubmissionBlocked": false,
    "submittedAt": null,
    "canSubmit": false,
    "createdAt": "2026-07-29T16:03:32.866Z"
  }
}
```

**La checklist a exactement cinq cases**, et le calcul est celui de
[provider-checklist.ts:31-44](apps/api/src/modules/providers/provider-checklist.ts:31) :

| Case | Verte quand | Écran à ouvrir si rouge | Libellé d'erreur officiel |
|---|---|---|---|
| `profile` | `publicName` non vide **ET `bio` non vide** | P2 | `Complétez votre nom public et votre présentation` |
| `services` | ≥ 1 service `active` possédant **≥ 1 formule `active`** | P3 puis P4 | `Déclarez au moins un service avec une formule tarifaire active` |
| `zones` | ≥ 1 zone rattachée | P5 | `Choisissez au moins une zone d'intervention` |
| `availabilities` | ≥ 1 créneau `active` | P6 | `Renseignez vos disponibilités hebdomadaires` |
| `documents` | **tous** les `requiredDocumentTypes` ont un justificatif non `rejected` | P7 | `Fournissez tous les justificatifs obligatoires` |

Deux pièges à documenter dans l'UI :

1. **`bio` est facultative à la création mais obligatoire pour la checklist.**
   Un prestataire qui a créé son profil sans présentation verra `profile: false`
   sans comprendre pourquoi. Le libellé de la case doit dire « Nom public **et
   présentation** ».
2. **Un service sans formule ne compte pas.** La case `services` reste rouge tant
   que P4 n'est pas fait. Le libellé doit le dire.

**Le bouton « Soumettre » est piloté par `canSubmit`, pas par la checklist.**
`canSubmit` vaut `true` seulement si les cinq cases sont vertes **ET** que
`validationStatus ∈ { profile_incomplete, changes_requested, rejected }`
(`rejected` inclus depuis la correction de l'écart n°8, §7) **ET** que
`resubmissionBlocked == false`
([provider-self.service.ts:207](apps/api/src/modules/providers/provider-self.service.ts:207)).

C'est pourquoi le compte démo ci-dessus, pourtant `approved`, a
`canSubmit: false` : il n'y a rien à re-soumettre.

#### `POST /providers/me/submit`

Aucun corps.

```bash
curl -i -X POST "$API/providers/me/submit" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Length: 0"
```

**Réponse 200** — de nouveau l'aperçu complet, avec
`validationStatus: "pending_review"`, `submittedAt` renseigné et
`rejectionReason` remis à `null`.

| Code | Message | Réaction de l'UI |
|---|---|---|
| **200** | `Dossier soumis à la vérification` | Naviguer vers P9. |
| **400** | `Votre dossier n'est pas complet` | Le détail est dans `errors[]`, avec le champ `field` renseigné. Forme : `[{ "field": "documents", "code": "checklist_incomplete", "message": "Fournissez tous les justificatifs obligatoires" }]`. Marquer en rouge exactement les cases listées. Cette erreur reste construite à la main par le service (`checklistErrors()`) — ce n'est plus, depuis la correction de l'écart n°13, le seul endpoint à fournir un `field` : toutes les erreurs de validation `class-validator` en portent un désormais (§1.4, §5.1). |
| **400** | `Votre dossier est au statut « approved » : il n'y a rien à soumettre.` | Le statut a changé entre l'affichage et le clic. Rafraîchir `GET /providers/me`. |
| **403** | `La re-soumission de votre dossier a été bloquée. Contactez le support.` | Correspond à `resubmissionBlocked: true`. Masquer définitivement le bouton et afficher un écran de contact support. |
| 403 | `Ce compte n'a pas de profil prestataire` | — |

---

#### P9 — Écran de suivi « dossier en cours de vérification »

Un seul appel, `GET /providers/me`, alimente les quatre états. **Il n'existe pas
de flux temps réel** : rafraîchir au retour au premier plan et sur pull-to-refresh.
Les changements de décision déclenchent par ailleurs une notification push
(`provider.approved`, `provider.changes_requested`, `provider.rejected` —
[notification-events.service.ts:24-26](apps/api/src/modules/notifications/notification-events.service.ts:24)),
qui est le bon signal pour rafraîchir.

| `validationStatus` | Titre | Contenu | Actions offertes |
|---|---|---|---|
| `pending_review` | « Dossier en cours de vérification » | Date de soumission (`submittedAt`), rappel des 5 étapes validées | **Aucune modification de fond.** Voir le verrou ci-dessous. Seul l'interrupteur de disponibilité reste actif. |
| `changes_requested` | « Corrections demandées » | **`rejectionReason` affiché en évidence** + checklist + statuts/motifs par document (`GET /providers/me/documents` → `current[].rejectionReason`) | **Toutes les corrections sont ouvertes** — détail ci-dessous. Bouton « Re-soumettre » actif si `canSubmit`. |
| `rejected` | « Dossier refusé » | `rejectionReason` | ✅ **Écart n°8 clos** : si `resubmissionBlocked == false`, **mêmes corrections que `changes_requested`** — bouton « Re-soumettre » actif si `canSubmit` (checklist complète). Si `resubmissionBlocked == true` : contact support uniquement, bouton absent. |
| `approved` | « Dossier validé » | — | Bascule vers l'espace prestataire complet (§4). |
| `suspended` | « Compte suspendu » | — | Contact support. Aucune action de gestion. |

**Verrou en `pending_review`** — vérifié dans
[provider-self.service.ts:78-86](apps/api/src/modules/providers/provider-self.service.ts:78) :
`PATCH /providers/me` renvoie
**`400 Votre dossier est en cours de vérification : il n'est plus modifiable`**
dès que le corps contient l'un de `publicName`, `bio`, `experienceYears`,
`avatarFileId`. En revanche `availabilityStatus` **seul** passe toujours : c'est
un interrupteur d'exploitation, sans rapport avec la décision.

→ L'application doit **griser les champs d'identité** en `pending_review` et
laisser l'interrupteur de disponibilité actif.

#### Comportement précis en `changes_requested` — ce que l'app doit rouvrir

Aucune restriction n'est posée par le code sur ce statut. Les champs
re-corrigeables sont donc **tous** ceux du dossier :

| Élément | Route de correction | Note |
|---|---|---|
| Nom public, présentation, années d'expérience, photo | `PATCH /providers/me` | Autorisé (le verrou ne vise que `pending_review`). |
| Services (titre, description, activation) | `PATCH /providers/me/services/:id` | Pas de suppression : `active: false` désactive. |
| Nouveau service | `POST /providers/me/services` | — |
| Formules (titre, description, prix, durée, activation) | `PATCH /providers/me/service-packs/:id` | — |
| Nouvelle formule | `POST /providers/me/service-packs` | — |
| Options de formule | `POST /providers/me/service-packs/:packId/options`, `PATCH /providers/me/service-pack-options/:id` | — |
| Zones | `PUT /providers/me/zones` | Remplacement intégral. |
| Disponibilités | `PUT /providers/me/availabilities` | Remplacement intégral. |
| Justificatifs | `POST /files/upload` + `POST /providers/me/documents` | ⚠️ **Repasse automatiquement le dossier en `pending_review`** (voir P7). |
| Portfolio | `POST/PATCH/DELETE /providers/me/portfolio` | Hors checklist. |

**Ordre recommandé à l'écran :** afficher `rejectionReason` en tête, puis la
checklist, puis la liste des documents avec leur `rejectionReason` individuel.
Si le motif porte sur un document, le prestataire redépose et **le dossier
repart tout seul** — l'application doit alors afficher « Dossier renvoyé en
vérification » et **ne pas** proposer « Re-soumettre » une seconde fois. Si le
motif porte sur autre chose (bio, tarifs, zones), le prestataire corrige puis
appuie sur « Re-soumettre » (`POST /providers/me/submit`).

---

### 2.3 Connexion, mot de passe oublié, rafraîchissement de session

#### `POST /auth/login`

Corps : `{ email, password }`. `LoginBodyDto.email` est décoré `@IsEmail()`
([dto.ts:81-88](apps/api/src/modules/auth/dto.ts:81)), et le service cherche par
`where: { email }` : **cette route reste réservée aux comptes avec email**. Un
compte créé avec un téléphone seul se connecte par un chemin différent —
`POST /auth/otp/verify` avec `purpose: "login"`, voir juste après.

```bash
curl -i -X POST "$API/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"provider.ready@prestgo.test","password":"prestgo123!"}'
```

**Réponse 200 (capture réelle) :**

```json
{
  "success": true,
  "message": "Authenticated",
  "data": {
    "accessToken": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9…",
    "refreshToken": "b58c5a76a0aadbf0caaa…"
  }
}
```

L'en-tête `User-Agent` est conservé sur la session côté serveur : le renseigner
avec un libellé lisible (`PRESTGO-Android/1.0.3 (Pixel 7)`) rend l'écran
« appareils connectés » exploitable côté back-office.

| Code | Message serveur | Réaction de l'UI |
|---|---|---|
| **200** | `Authenticated` | Stocker les deux jetons (secure storage), appeler `GET /me`, enregistrer le device push (§5.3), router selon §1.3. |
| **400** | `Adresse email invalide` / `Le mot de passe est obligatoire` | Bannière. |
| **401** | `Invalid credentials` | ⚠️ **Message unique pour « email inconnu » et « mot de passe faux »** — volontaire. Afficher « Email ou mot de passe incorrect ». Ne jamais laisser entendre que l'email existe. Vérifié en appel réel. |
| **401** | `Account is not active` | Compte `pending` (jamais activé), `suspended`, `rejected` ou `deleted`. **L'API ne dit pas lequel.** Recommandation : proposer les deux issues — « Vérifier mon compte » (relance `otp/send` puis écran C4) et « Contacter le support ». Vérifié en appel réel sur un compte `pending`. |
| **429** | — | 10 tentatives/minute. Désactiver le bouton 60 s. |

#### Connexion par téléphone, sans mot de passe — `POST /auth/otp/verify` (`purpose: "login"`)

✅ **Ajouté depuis la rédaction initiale de ce document (écart n°2, clos).** Un
compte inscrit avec un numéro de téléphone seul (sans email) ne pouvait
auparavant jamais se connecter. Le motif `login` figurait déjà parmi les
valeurs acceptées par `SendOtpBodyDto`/`VerifyOtpBodyDto`, mais aucune route ne
l'exploitait — c'est corrigé.

**Parcours, réutilisant les mêmes routes que la vérification de compte (§2.1) :**

```
POST /auth/otp/send    { "target": "+225...", "purpose": "login" }   → 200
POST /auth/otp/verify  { "target": "+225...", "code": "…", "purpose": "login" } → 200, jetons émis
```

`POST /auth/otp/send` avec `purpose: "login"` répond **exactement comme pour
les autres motifs** (§2.1) — aucun changement de forme, aucune indication sur
l'existence du compte.

`POST /auth/otp/verify` avec `purpose: "login"` change en revanche
complètement de forme de réponse par rapport aux deux autres motifs : au lieu
de `{ verified, activated }`, il renvoie **exactement la forme de
`POST /auth/login`** — capture réelle :

```json
{
  "success": true,
  "message": "Authenticated",
  "data": {
    "accessToken": "eyJhbGciOiJIUzI1NiIs…",
    "refreshToken": "972f86cedaa8d252d2cd…"
  }
}
```

```bash
curl -i -X POST "$API/auth/otp/send" \
  -H "Content-Type: application/json" \
  -d '{"target":"+22507052500","purpose":"login"}'

curl -i -X POST "$API/auth/otp/verify" \
  -H "Content-Type: application/json" \
  -d '{"target":"+22507052500","code":"346826","purpose":"login"}'
```

| Code | Message serveur | Réaction de l'UI |
|---|---|---|
| **200** | `Authenticated` | Identique à `POST /auth/login` : stocker les deux jetons, appeler `GET /me`, enregistrer le device push (§5.3), router selon §1.3. |
| **400** | `Code invalide ou expiré` | Même message ambigu qu'en vérification de compte (§2.1) : code faux, expiré, ou déjà utilisé. |
| **401** | `Trop de tentatives. Demandez un nouveau code.` | Après 5 tentatives sur le même code. |
| **401** | **`Account is not active`** | ⚠️ Spécifique à `purpose: "login"` : le code est valide, mais **aucun compte actif** ne correspond au numéro (inexistant, encore `pending`, suspendu…). Ce n'est **pas une fuite** : avoir reçu et ressaisi le bon code prouve déjà la maîtrise du téléphone — contrairement à `otp/send` ou `forgot-password`, qui eux ne doivent rien révéler. Afficher un message générique (« Connexion impossible avec ce numéro ») et proposer l'inscription. |
| **429** | — | 30 vérifications/minute (throttle partagé avec les deux autres motifs). |

⚠️ **Ne pas confondre avec la vérification de compte.** Un même numéro peut
recevoir un OTP `phone_verification` (active le compte) et un OTP `login`
(connecte un compte déjà actif) : ce sont deux enregistrements distincts en
base, le `purpose` les sépare. L'écran de connexion par téléphone doit
toujours envoyer `purpose: "login"`, jamais laisser le champ vide (qui
retomberait sur `phone_verification`, une forme de réponse différente).

#### Mot de passe oublié — **la route existe**, en deux temps

`POST /auth/forgot-password` — corps `{ email }`.

```bash
curl -i -X POST "$API/auth/forgot-password" \
  -H "Content-Type: application/json" \
  -d '{"email":"client.demo@prestgo.test"}'
```

Réponse **toujours 200**, **toujours le même corps**, que le compte existe ou
non ([account.service.ts:153-157](apps/api/src/modules/auth/account.service.ts:153)) :

```json
{
  "success": true,
  "message": "Si un compte existe pour cette adresse, un lien de réinitialisation a été envoyé.",
  "data": { "message": "Si un compte existe pour cette adresse, un lien de réinitialisation a été envoyé." }
}
```

→ L'écran affiche ce message et navigue **systématiquement** vers l'écran de
saisie du jeton. Ne jamais afficher « adresse inconnue ».

`POST /auth/reset-password` — corps `{ token, password }`.

| Champ | Règle | Message |
|---|---|---|
| `token` | chaîne, **≥ 10 caractères** | `Jeton de réinitialisation invalide` |
| `password` | 8–128, une lettre + un chiffre | `Le mot de passe doit contenir au moins 8 caractères, dont une lettre et un chiffre` |

```bash
curl -i -X POST "$API/auth/reset-password" \
  -H "Content-Type: application/json" \
  -d '{"token":"3f9c1a…64 caractères hexadécimaux…","password":"nouveau2026"}'
```

| Code | Message | Réaction de l'UI |
|---|---|---|
| **200** | `Mot de passe mis à jour` | **Toutes les sessions sont révoquées, sans exception** — y compris celle de l'appareil qui fait la demande. Purger le stockage sécurisé et renvoyer vers l'écran de connexion. |
| **400** | `Lien de réinitialisation invalide ou expiré` | Message unique pour jeton faux, expiré (**30 minutes**) ou déjà utilisé. Proposer de relancer `forgot-password`. |

⚠️ **Point d'intégration non tranché par le code.** Le jeton est un hexadécimal
de 64 caractères envoyé **par email**, dans un corps de message qui dit
« Utilisez ce code pour réinitialiser votre mot de passe : `<token>` »
([account.service.ts:143](apps/api/src/modules/auth/account.service.ts:143)).
Ce n'est **pas** une URL, et **aucun lien profond (deep link) n'est construit
côté backend**. L'application doit donc présenter un **champ de saisie /
collage** du jeton, pas attendre un `App Link` / `Universal Link`. Si un
parcours par lien est souhaité, c'est une évolution backend — voir §7, écart n°3.

#### Rafraîchissement de session — `POST /auth/refresh`

Corps : `{ refreshToken }`. Réponse 200 :
`{ success, message: "Refreshed", data: { accessToken, refreshToken } }`.

**Trois propriétés à connaître avant d'écrire l'intercepteur :**

1. **Le refresh token tourne.** L'ancien est révoqué, un **nouveau** est renvoyé.
   Ne pas remplacer celui du stockage = déconnexion au refresh suivant.
2. **Les droits sont relus en base à chaque refresh**
   ([auth.service.ts:126-151](apps/api/src/modules/auth/auth.service.ts:126)) :
   un compte suspendu entre-temps se voit refuser (`401 Session expirée ou
   invalide`) et sa session est fermée au passage.
3. Débit : **30 appels/minute**. Un intercepteur qui boucle sur le refresh
   déclenchera un `429` avant de se rendre compte du problème — d'où le verrou
   « un seul refresh en vol » ci-dessous.

#### Intercepteur dio concret

Contraintes couvertes : **un seul refresh en vol**, **mise en file d'attente des
requêtes concurrentes**, **rejeu de la requête d'origine**, **pas de boucle
infinie**, **exclusion des routes d'authentification**.

```dart
// core/api/auth_interceptor.dart
import 'dart:async';
import 'package:dio/dio.dart';

class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({
    required Dio refreshDio,     // instance SANS cet intercepteur — sinon récursion
    required TokenStore store,
    required void Function() onSessionExpired,
  })  : _refreshDio = refreshDio,
        _store = store,
        _onSessionExpired = onSessionExpired;

  final Dio _refreshDio;
  final TokenStore _store;
  final void Function() _onSessionExpired;

  // Un seul refresh à la fois. Les appels concurrents attendent le même Future.
  Future<String?>? _inFlight;

  // Routes qui n'ont jamais de Bearer et ne doivent jamais déclencher un refresh.
  static const _publicPaths = <String>{
    '/auth/login',
    '/auth/register',
    '/auth/refresh',
    '/auth/forgot-password',
    '/auth/reset-password',
    '/auth/otp/send',
    '/auth/otp/verify',
  };

  bool _isPublic(RequestOptions o) => _publicPaths.any((p) => o.path.endsWith(p));

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_isPublic(options)) {
      final token = await _store.readAccessToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final options  = err.requestOptions;

    final isUnauthorized = response?.statusCode == 401;
    final alreadyRetried = options.extra['__retried__'] == true;

    if (!isUnauthorized || alreadyRetried || _isPublic(options)) {
      return handler.next(err);
    }

    // Un 401 sur une route protégée : on tente UN refresh, partagé entre appelants.
    final newToken = await (_inFlight ??= _refresh());

    if (newToken == null) {
      // Refresh refusé : la session est morte pour de bon.
      await _store.clear();
      _onSessionExpired();          // go_router redirige vers /login
      return handler.next(err);
    }

    // Rejeu de la requête d'origine, à l'identique, avec le nouveau jeton.
    options.extra['__retried__'] = true;
    options.headers['Authorization'] = 'Bearer $newToken';

    try {
      final retried = await _refreshDio.fetch<dynamic>(options);
      return handler.resolve(retried);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }

  Future<String?> _refresh() async {
    try {
      final refreshToken = await _store.readRefreshToken();
      if (refreshToken == null) return null;

      final res = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      final data = res.data?['data'] as Map<String, dynamic>?;
      final access  = data?['accessToken']  as String?;
      final rotated = data?['refreshToken'] as String?;
      if (access == null || rotated == null) return null;

      // IMPÉRATIF : le refresh token a tourné, l'ancien est déjà révoqué.
      await _store.write(accessToken: access, refreshToken: rotated);
      return access;
    } on DioException {
      return null;                  // 401 « Session expirée ou invalide », ou 429
    } finally {
      _inFlight = null;             // libère le verrou, succès comme échec
    }
  }
}
```

Notes d'implémentation :

- **`QueuedInterceptor` et non `Interceptor`** : dio sérialise alors les
  requêtes traversant cet intercepteur, ce qui évite que dix appels parallèles
  déclenchent dix refresh. Le verrou `_inFlight` couvre le cas résiduel.
- **`refreshDio` est une seconde instance `Dio`** partageant `baseUrl` mais
  **sans** `AuthInterceptor`. Sans cette séparation, l'appel `/auth/refresh` qui
  échoue en 401 relancerait un refresh — récursion infinie.
- **`options.extra['__retried__']`** garantit qu'une requête n'est rejouée
  qu'une fois : si le second appel renvoie encore 401, on abandonne.
- **`multipart/form-data` (upload de fichiers)** : un `FormData` est un flux à
  usage unique. Le rejouer tel quel envoie un corps vide. Deux options : soit
  rafraîchir le token **avant** un upload (l'application connaît la date
  d'expiration du JWT — 15 min), soit reconstruire le `FormData` dans un
  `retryBuilder`. **Recommandation : ne pas faire passer les uploads par le
  rejeu automatique**, et gérer le 401 de `POST /files/upload` par une reprise
  explicite de l'action utilisateur.
- **Rafraîchissement proactif** (optionnel mais recommandé) : décoder `exp` du
  JWT et refresh à T−60 s. Cela réduit le nombre de 401 traversés, donc la
  latence perçue.

---

### 2.4 Déconnexion et suppression de compte

#### `POST /auth/logout`

Particularité vérifiée : **le contrôleur entier est `@Public()`**
([auth.controller.ts:24](apps/api/src/modules/auth/auth.controller.ts:24)) — la
route est donc marquée `auth=no` dans OpenAPI. Elle lit malgré tout l'en-tête
`Authorization` si elle en trouve un. **Envoyer les deux** (en-tête + corps) est
la façon de garantir que la bonne session est fermée.

Corps : `{ refreshToken }` — **optionnel** (`@IsOptional`, ≤ 256 caractères).

```bash
curl -i -X POST "$API/auth/logout" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"refreshToken":"b58c5a76a0aadbf0caaa…"}'
```

**Réponse 200 :** `{ "success": true, "message": "Logged out", "data": { "loggedOut": true } }`

La route est **idempotente et tolérante** : un jeton d'accès invalide est ignoré
silencieusement, la déconnexion réussit quand même
([auth.service.ts:176-179](apps/api/src/modules/auth/auth.service.ts:176)).
Il n'y a **pas** de code d'erreur métier à gérer.

⚠️ **Le jeton d'accès reste valable jusqu'à son expiration (15 min).** Seule la
session de rafraîchissement est fermée. L'application doit donc **purger son
stockage local immédiatement**, sans attendre la réponse — c'est elle qui rend
la déconnexion effective côté appareil.

**Séquence de déconnexion imposée :**

1. `DELETE /me/devices/:token` — désenregistrer le jeton push (§5.3). **Avant**
   le logout : la route exige un `Bearer` valide.
2. `POST /auth/logout` (en-tête + `refreshToken` dans le corps).
3. Purger `flutter_secure_storage` et **tous les caches Riverpod**
   (`ref.invalidate` global ou recréation du `ProviderContainer`) — sinon les
   données du compte précédent restent affichées à la reconnexion.
4. Rediriger vers `/login`.

Les étapes 1 et 2 sont **best-effort** : si le réseau est coupé, passer quand
même aux étapes 3 et 4. Ne jamais bloquer une déconnexion sur un appel réseau.

#### `DELETE /me` — désactivation du compte

⚠️ **Ce n'est pas une suppression.** Le statut passe à `deleted`, **les données
restent en base** ([me.service.ts:147-201](apps/api/src/modules/me/me.service.ts:147)) :
les missions passées, les avis et les factures d'autres personnes référencent ce
compte. L'écran doit dire « Désactiver mon compte », pas « Supprimer mes données ».

**Un corps est obligatoire** : `{ password }`
([dto.ts:115-119](apps/api/src/modules/me/dto.ts:115)) — confirmation explicite
plutôt qu'un DELETE nu qu'un bouton mal placé déclencherait.

```bash
curl -i -X DELETE "$API/me" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"password":"prestgo123!"}'
```

**Réponse 200 :** `{ "success": true, "message": "Compte désactivé", "data": { "status": "deleted" } }`

| Code | Message serveur exact | Réaction de l'UI |
|---|---|---|
| **200** | `Compte désactivé` | Effets de bord vérifiés : **toutes** les sessions sont révoquées **et** tous les `deviceToken` passent à `active: false`. Purger le stockage, retourner à l'écran de connexion avec un message de confirmation. |
| **400** | **`Désactivation impossible : 2 mission(s) confirmée(s) ou en cours. Terminez-les ou annulez-les d'abord.`** | ⚠️ **Le message contient le nombre réel** (`blocking`), interpolé à l'exécution. Le compte est bloqué s'il a des missions `confirmed` ou `in_progress` **comme client ou comme prestataire** ([me.service.ts:172-182](apps/api/src/modules/me/me.service.ts:172)). **L'UI doit afficher le message serveur tel quel** et proposer un raccourci « Voir mes missions en cours ». Ne pas reconstruire le texte côté client. |
| **400** | `Ce compte est déjà désactivé` | Purger le stockage et retourner à la connexion. |
| **401** | `Mot de passe incorrect` | Erreur sous le champ mot de passe. C'est le seul endpoint du périmètre où l'origine de l'erreur est sans ambiguïté. |
| **404** | `Compte introuvable` | Session incohérente : purger et retourner à la connexion. |

**Écran recommandé :** double confirmation — un premier écran explicatif
(« vos missions passées et vos avis sont conservés »), puis une boîte de saisie
du mot de passe. Le libellé du bouton final doit être explicite
(« Désactiver définitivement »).

---

## 3. Écrans et parcours — côté CLIENT

Convention de cette section : pour chaque écran, **ce qui est affiché** (avec la
route qui le fournit), **les actions** (route, méthode, corps, curl) et **les
états vides / erreur / chargement**.

Règle générale sur les listes : une réponse paginée porte
`meta: { page, limit, total }` ; une réponse non paginée n'a **pas** de `meta`.
Le tableau §6 précise le cas de chaque route.

---

### 3.1 Profil

#### Affichage — `GET /me`

Forme complète en §1.3. À l'écran :

| Donnée | Champ | Remarque |
|---|---|---|
| Nom affiché | `firstName` + `lastName` | Les deux sont *nullable* : prévoir un repli sur l'email. |
| Email | `email` (nullable) | Pastille « non vérifié » si `emailVerified == false`. |
| Téléphone | `phone` (nullable) | Pastille « non vérifié » si `phoneVerified == false`. |
| Membre depuis | `createdAt` | — |
| Accès prestataire | `hasProviderProfile`, `providerValidationStatus` | Pilote l'entrée « Espace prestataire » / « Devenir prestataire ». |

**États :** chargement → squelette ; erreur → bouton « Réessayer » ; il n'y a pas
d'état vide (une réponse 200 implique un profil).

#### Action — `PATCH /me`

Corps ([dto.ts:15-33](apps/api/src/modules/me/dto.ts:15)), tous les champs
optionnels : `firstName` (≤80), `lastName` (≤80), `email` (`@IsEmail`),
`phone` (`^\+?[0-9\s-]{8,20}$`).

```bash
curl -i -X PATCH "$API/me" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"firstName":"Awa","lastName":"Koné","email":"awa.kone@prestgo.test"}'
```

**Réponse 200 :** le profil complet **plus** un champ `pendingVerifications` :

```json
{
  "success": true,
  "message": "Profil mis à jour. Un code de vérification vous a été envoyé.",
  "data": {
    "id": "…", "firstName": "Awa", "…": "…",
    "emailVerified": false,
    "pendingVerifications": [ { "channel": "email", "target": "awa.kone@prestgo.test" } ]
  }
}
```

Règle métier vérifiée
([me.service.ts:109-128](apps/api/src/modules/me/me.service.ts:109)) : changer
`email` ou `phone` **remet le champ en non vérifié** et **déclenche
automatiquement l'envoi d'un OTP** (`email_verification` ou `phone_verification`).

→ **Parcours attendu :** si `pendingVerifications` est non vide, naviguer
immédiatement vers l'écran OTP (C4 du §2.1) avec `target = entrée.target` et
`purpose = "email_verification"` si `channel == "email"`, sinon
`"phone_verification"`. La vérification passe par les mêmes routes publiques
`POST /auth/otp/verify`.

⚠️ `channel` vaut **`sms`** (pas `phone`) pour le téléphone
([me.service.ts:126](apps/api/src/modules/me/me.service.ts:126)) — le mapping
`sms → phone_verification` doit être explicite dans le code Flutter.

| Code | Message | Réaction de l'UI |
|---|---|---|
| 200, `pendingVerifications` vide | `Profil mis à jour` | `SnackBar` de succès, rester sur l'écran. |
| 200, `pendingVerifications` non vide | `Profil mis à jour. Un code de vérification vous a été envoyé.` | Naviguer vers l'écran OTP. |
| 400 | validation | Bannière. |
| **409** | `Cet email ou ce numéro est déjà utilisé` | Bannière + focus sur le champ concerné (déduit côté client : c'est celui qui a été modifié). |
| 404 | `Compte introuvable` | Session incohérente → déconnexion. |

#### Action — `POST /me/password`

Corps : `{ currentPassword, newPassword }`. `newPassword` : 8–128, une lettre et
un chiffre.

```bash
curl -i -X POST "$API/me/password" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"currentPassword":"prestgo123!","newPassword":"prestgo2026x"}'
```

**Réponse 200 :**

```json
{
  "success": true,
  "message": "Mot de passe mis à jour. 2 autre(s) session(s) fermée(s).",
  "data": { "revokedSessions": 2 }
}
```

**La session courante survit** — c'est la différence avec `reset-password`
(§2.3), qui coupe tout. L'utilisateur reste connecté sur cet appareil ; il n'y a
**pas** de nouveau couple de jetons à stocker.

| Code | Message | Réaction de l'UI |
|---|---|---|
| 200 | interpolé avec `revokedSessions` | Afficher le message serveur tel quel (il contient le nombre). |
| **400** | `Le nouveau mot de passe doit être différent de l'ancien` | Sous le champ « nouveau mot de passe ». |
| 400 | `Compte introuvable` | Déconnexion. |
| **401** | `Mot de passe actuel incorrect` | Sous le champ « mot de passe actuel ». |
| **429** | — | 30/minute. |

---

### 3.2 Adresses — `/me/addresses`

Le carnet d'adresses est un **prérequis de la réservation** : `POST /missions`
exige un `addressId` du carnet, et l'adresse doit être géolocalisée.

#### Liste — `GET /me/addresses`

**Capture réelle** (pas de `meta` : réponse **non paginée**) :

```json
{
  "success": true,
  "message": "OK",
  "data": [
    {
      "id": "b7ff0e66-b9cd-4f67-9782-e786212d8961",
      "label": "Domicile",
      "city": "Abidjan",
      "commune": "Cocody",
      "details": "Rue des Jardins, villa 12",
      "latitude": 5.35,
      "longitude": -3.98,
      "isDefault": true,
      "createdAt": "2026-07-19T13:10:01.372Z"
    }
  ]
}
```

L'adresse par défaut est renvoyée **en premier**. Le champ `userId` n'apparaît
que sur les réponses de création/modification — ne pas s'en servir.

**État vide :** `data: []` → écran d'appel à l'action « Ajouter une adresse »,
car sans adresse aucune réservation n'est possible.

#### Création — `POST /me/addresses`

| Champ | Obligatoire | Règle | Message |
|---|---|---|---|
| `label` | **Oui** | 1–50 | `Le libellé est obligatoire` |
| `city` | **Oui** | 1–80 | `La ville est obligatoire` |
| `commune` | Non | ≤ 80 (chaîne vide → `undefined`) | — |
| `details` | Non | ≤ 255 | — |
| `latitude` | **Oui** | latitude valide | `Latitude invalide` |
| `longitude` | **Oui** | longitude valide | `Longitude invalide` |
| `isDefault` | Non | booléen | — |

⚠️ **La géolocalisation est obligatoire**, et c'est structurant :
[dto.ts:58-67](apps/api/src/modules/me/dto.ts:58) le documente — c'est elle qui
permet de vérifier qu'une adresse tombe dans la zone d'intervention d'un
prestataire. **L'écran d'ajout d'adresse doit donc embarquer un sélecteur de
position** (position actuelle + ajustement sur carte), pas seulement des champs
texte. Une adresse sans coordonnées ne peut pas être créée.

```bash
curl -i -X POST "$API/me/addresses" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "label": "Bureau",
    "city": "Abidjan",
    "commune": "Plateau",
    "details": "Immeuble Alpha 2000, 4e étage",
    "latitude": 5.3241,
    "longitude": -4.0187,
    "isDefault": false
  }'
```

| Code | Message | Réaction de l'UI |
|---|---|---|
| 201 | `Adresse enregistrée` | Rafraîchir la liste. |
| **400** | `Vous ne pouvez pas enregistrer plus de 10 adresses` | Plafond `MAX_ADDRESSES_PER_USER = 10`. Griser le bouton « Ajouter » à 10 et afficher le motif. |
| 400 | `Latitude invalide` / `Longitude invalide` / libellé / ville | Bannière. |

#### Modification — `PATCH /me/addresses/:id`

Tous les champs optionnels : `label`, `city`, `commune`, `details`, `latitude`,
`longitude`. **`isDefault` n'est pas modifiable ici** — il a sa propre route.

```bash
curl -i -X PATCH "$API/me/addresses/b7ff0e66-b9cd-4f67-9782-e786212d8961" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"details":"Rue des Jardins, villa 12 (portail bleu)"}'
```

`404 Adresse introuvable` si l'identifiant n'existe pas **ou** n'appartient pas
au compte — les deux cas sont indiscernables, volontairement.

#### Adresse par défaut — `POST /me/addresses/:id/default`

Pas de corps. Réponse 200 : **la liste complète à jour**, pas l'adresse seule.

```bash
curl -i -X POST "$API/me/addresses/b7ff0e66-b9cd-4f67-9782-e786212d8961/default" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Length: 0"
```

Message : `Adresse par défaut mise à jour`. Alimenter directement la liste avec
`data` (économie d'un appel).

#### Suppression — `DELETE /me/addresses/:id`

**La suppression n'est pas toujours une suppression.** Réponse 200, deux formes :

```json
{ "success": true, "message": "Adresse supprimée",           "data": { "removed": true,  "archived": false } }
```
```json
{ "success": true, "message": "Adresse retirée du carnet",   "data": { "removed": false, "archived": true,
  "reason": "Adresse conservée car utilisée par des missions passées" } }
```

→ L'UI affiche `message` (qui diffère selon le cas) et, si `archived == true`,
peut afficher `data.reason` en explication secondaire. Dans les deux cas, la
ligne disparaît du carnet.

`404 Adresse introuvable` si elle n'existe pas ou n'appartient pas au compte.

---

### 3.3 Favoris — `/me/favorites`

#### Liste — `GET /me/favorites`

Réponse **non paginée**. Capture réelle sur le compte démo : `"data": []`.

Forme d'un élément (`FavoriteProviderDto`) :
`{ id, publicName, bio, score, reviewsCount, categories: string[], available, favoritedAt }`.

⚠️ `available` signifie **« validé ET non suspendu »**
([response-dto.ts:89](apps/api/src/modules/me/response-dto.ts:89)) — ce n'est
pas la disponibilité d'agenda. **Un favori suspendu reste listé avec
`available: false`.** L'UI doit alors griser la carte et désactiver le bouton
« Réserver », sans faire disparaître la ligne.

**État vide :** message « Aucun favori » + renvoi vers la recherche.

#### Ajouter — `POST /me/favorites/:providerId`

Pas de corps. **Idempotent.** Réponse 200 :
`{ "success": true, "message": "Ajouté aux favoris", "data": { "favorited": true } }`

```bash
curl -i -X POST "$API/me/favorites/bb1397e8-ff8f-4142-a9f9-b0a0d07dfa5c" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Length: 0"
```

| Code | Message | Réaction de l'UI |
|---|---|---|
| 200 | `Ajouté aux favoris` | Cœur plein. Mise à jour optimiste acceptable (l'appel est idempotent). |
| **400** | `Ce prestataire n'est pas encore validé, ou il s'agit de mon propre compte` | Revenir à l'état précédent + `SnackBar`. Prévenir le cas « mon propre compte » côté client en comparant `providerId` à `GET /me.providerId`. |
| **404** | `Prestataire introuvable` | Revenir à l'état précédent. |

#### Retirer — `DELETE /me/favorites/:providerId`

**Idempotent, jamais d'erreur métier** : retirer un favori absent renvoie 200
avec `{ "favorited": false }`. Message : `Retiré des favoris`.

---

### 3.4 Accueil / recherche de prestataires — `GET /providers/search`

Route **publique** : l'écran d'accueil s'affiche **sans compte**. C'est un choix
assumé du backend ([provider-search.controller.ts:10-19](apps/api/src/modules/providers/provider-search.controller.ts:10)),
et l'application doit le respecter — ne pas exiger de connexion avant la
recherche. Le mur d'authentification tombe au moment de **réserver**.

#### Paramètres — liste exhaustive et vérifiée

Source : [search-dto.ts](apps/api/src/modules/providers/search-dto.ts) +
[provider-search.service.ts](apps/api/src/modules/providers/provider-search.service.ts).
**Tous sont facultatifs.**

| Paramètre | Type | Contrainte | Message d'erreur |
|---|---|---|---|
| `categoryId` | UUID | — | `Catégorie invalide` |
| `serviceTypeId` | UUID | **prioritaire sur `categoryId`** si les deux sont fournis | `Type de service invalide` |
| `latitude` | number | latitude valide | `Latitude invalide` |
| `longitude` | number | longitude valide | `Longitude invalide` |
| `radiusKm` | number | **1 à 50**, défaut **10** | `Le rayon doit valoir au moins 1 km` / `Le rayon ne peut pas dépasser 50 km` |
| `zoneId` | UUID | **ignoré si `latitude`+`longitude` sont fournis** | `Zone invalide` |
| `date` | string | `AAAA-MM-JJ` | `« date » doit être au format AAAA-MM-JJ` |
| `startTime` | string | `HH:MM` (24 h) | `« startTime » doit être au format HH:MM` |
| `minRating` | number | 0 à 5 | `La note minimale ne peut pas dépasser 5` |
| `q` | string | ≤ 120 | — |
| `sort` | string | `distance` \| `rating` \| `recent` | `Tri accepté : distance, rating, recent` |
| `page` | int | ≥ 1 | `page doit être supérieur ou égal à 1` |
| `limit` | int | 1 à **50** (et non 100) | `limit ne peut pas dépasser 50 sur la recherche` |

**Filtres appliqués d'office, non contournables** : `validationStatus = approved`,
compte utilisateur `active`, `availabilityStatus != unavailable`, et **au moins
un service actif avec une formule active** (sinon la fiche n'aurait pas de bouton
« Réserver »).

**Tri par défaut :** `distance` si latitude+longitude sont fournis, `rating`
sinon.

**Deux combinaisons refusées en 400 — vérifiées en appel réel :**

```
GET /providers/search?sort=distance   (sans latitude/longitude)
  → 400 "Le tri par distance exige latitude et longitude"

GET /providers/search?date=2026-08-05   (sans startTime, ou l'inverse)
  → 400 "Indiquez à la fois « date » et « startTime » pour filtrer sur un créneau"
```

→ **L'UI doit prévenir ces deux cas** : griser le tri « distance » tant que la
géolocalisation n'est pas accordée, et lier date et heure dans un même sélecteur
de créneau (l'un ne s'envoie jamais sans l'autre).

#### Exemple avec géolocalisation — **appel réel**

```bash
curl -s "$API/providers/search?latitude=5.3599&longitude=-3.9967&radiusKm=15&sort=distance&limit=5"
```

```json
{
  "success": true,
  "message": "OK",
  "data": [
    {
      "id": "bb1397e8-ff8f-4142-a9f9-b0a0d07dfa5c",
      "publicName": "PRESTGO Demo — Plomberie Express",
      "score": 4.5,
      "reviewsCount": 12,
      "distanceKm": 2.15,
      "categories": ["Plomberie"],
      "startingPrice": 5000,
      "avatarFileId": null,
      "availableNow": true
    }
  ],
  "meta": { "page": 1, "limit": 5, "total": 1 }
}
```

Exemple filtré sur catégorie + créneau :

```bash
curl -s "$API/providers/search?categoryId=13cac995-0ac6-4ab4-9840-9a2969d5770c&date=2026-08-05&startTime=09:00&minRating=4&page=1&limit=20"
```

#### Rendu d'une carte de résultat

| Champ | Affichage | Piège |
|---|---|---|
| `publicName` | Titre | — |
| `score`, `reviewsCount` | « 4,5 ★ (12 avis) » | `score` est arrondi au dixième côté serveur. `score = 0` avec `reviewsCount = 0` signifie **« pas encore noté »**, pas « 0 étoile » — afficher « Nouveau ». |
| `distanceKm` | « à 2,2 km » | **`null` si aucune géoposition n'a été envoyée.** Masquer la ligne dans ce cas. |
| `categories` | Puces | **Tableau de chaînes** dans la recherche — mais **tableau d'objets** `{id, name, slug}` sur la fiche publique. Deux modèles Dart distincts. |
| `startingPrice` | « à partir de 5 000 XOF » | `null` possible → masquer. |
| `avatarFileId` | Photo via `GET /files/:id/content` | `null` → initiales. ✅ **Écart n°5 clos** : cette route est désormais accessible **sans jeton** pour un fichier `public` (avatar, portfolio) — l'appeler avec ou sans `Authorization` fonctionne indifféremment, y compris sur l'écran d'accueil non connecté. Un fichier non public reste refusé en 403, avec ou sans jeton. |
| `availableNow` | Pastille verte | `availabilityStatus == "available"`. Un prestataire `busy` apparaît avec `availableNow: false` mais reste réservable. |

**États :** chargement → shimmer de 3 cartes ; erreur → « Réessayer » ;
`data: []` → « Aucun prestataire ne correspond », avec bouton « Élargir le
rayon » (incrémente `radiusKm` jusqu'à 50) et « Retirer les filtres ».

**Pagination :** `meta.total` et `meta.limit` donnent le nombre de pages.
Défilement infini recommandé, en incrémentant `page`.

**Écrans annexes du même parcours :**

- `GET /categories` — sélecteur de catégorie/type (§2.2 P3), **non paginé**.
- `GET /zones` — liste des zones actives, **non paginé**.
- `GET /zones/nearby?latitude=…&longitude=…&radiusKm=…` — zones triées par
  distance ; `radiusKm` défaut **10**. Utile pour l'écran « Où intervenons-nous ? ».

---

### 3.5 Fiche prestataire publique — `GET /providers/:id/public`

**Un seul appel restitue tout l'écran** — c'est explicite dans le code
([provider-search.service.ts:89-95](apps/api/src/modules/providers/provider-search.service.ts:89)) :
multiplier les allers-retours ferait apparaître l'écran par morceaux sur une
connexion mobile. **Ne pas fragmenter en appels séparés** vers
`/providers/:id/service-packs`, `/availabilities` ou `/reviews` : tout est déjà là.

```bash
curl -s "$API/providers/bb1397e8-ff8f-4142-a9f9-b0a0d07dfa5c/public"
```

**Capture réelle (structure `data`, abrégée sur les répétitions) :**

```json
{
  "id": "bb1397e8-ff8f-4142-a9f9-b0a0d07dfa5c",
  "publicName": "PRESTGO Demo — Plomberie Express",
  "bio": "Compte de démonstration déjà approuvé, …",
  "experienceYears": 6,
  "avatarFileId": null,
  "availableNow": true,
  "score": 4.5,
  "reviewsCount": 12,
  "startingPrice": 5000,
  "categories": [
    { "id": "13cac995-0ac6-4ab4-9840-9a2969d5770c", "name": "Plomberie", "slug": "plomberie" }
  ],
  "services": [
    {
      "id": "4698c3da-7697-41b5-8c6d-946fdcec95f0",
      "title": "Dépannage plomberie express",
      "description": "Intervention rapide pour petites réparations.",
      "serviceType": {
        "id": "c3fe35c0-9331-47d4-a809-bd63fe69a70f",
        "name": "Réparation de fuite",
        "category": { "id": "13cac995-…", "name": "Plomberie", "slug": "plomberie" }
      },
      "packs": [
        {
          "id": "8fd727f4-65c7-4086-a72e-0ab231584612",
          "title": "Intervention express",
          "description": "Petite réparation, sur place en moins d'une heure.",
          "price": 5000,
          "durationMinutes": 45,
          "options": []
        }
      ]
    }
  ],
  "portfolio": [],
  "availability": [
    { "weekday": 0, "startTime": "08:00", "endTime": "18:00" },
    { "weekday": 1, "startTime": "08:00", "endTime": "18:00" }
  ],
  "upcomingUnavailabilities": [],
  "zones": [
    { "id": "fddb1349-5f23-4307-9560-710c6220c049", "name": "Cocody", "city": { "name": "Abidjan" } }
  ],
  "ratingDistribution": { "1": 0, "2": 0, "3": 0, "4": 0, "5": 0 },
  "latestReviews": [],
  "memberSince": "2026-07-29T16:03:32.866Z"
}
```

Correspondance écran ↔ données :

| Section de l'écran | Champ |
|---|---|
| En-tête (photo, nom, note, ancienneté) | `avatarFileId`, `publicName`, `score`, `reviewsCount`, `memberSince`, `experienceYears` |
| Présentation | `bio` |
| **Prestations et tarifs** | `services[].packs[]` — c'est **ici** que se prend le `packId` de la réservation |
| Options payantes | `services[].packs[].options[]` — `{ id, title, price, durationMinutes }`, source des `optionIds` |
| Réalisations | `portfolio[]` — chaque entrée porte un `file` ; l'image se charge via `GET /files/:id/content` |
| Agenda | `availability[]` (créneaux **actifs** uniquement) + `upcomingUnavailabilities[]` (absences **à venir**) |
| Zones couvertes | `zones[]` |
| Avis | `ratingDistribution` (histogramme, clés `"1"` à `"5"`) + `latestReviews` (**les 5 plus récents**, avec `authorFirstName`) |

**Pour la liste complète des avis** (au-delà des 5) :
`GET /providers/:id/reviews?page=…&limit=…`.

⚠️ **Forme atypique, vérifiée en appel réel** : cette route renvoie un **objet**,
pas un tableau, alors qu'elle porte quand même un `meta` de pagination :

```json
{
  "success": true, "message": "OK",
  "data": { "averageRating": null, "totalReviews": 0, "reviews": [] },
  "meta": { "page": 1, "limit": 20, "total": 0 }
}
```

Le modèle Dart doit lire `data.reviews`, **pas** `data` directement. C'est la
seule route paginée du périmètre dont `data` n'est pas un tableau
(elle n'a pas de DTO de réponse Swagger, d'où l'écart de forme).

**Erreur :** `404 Prestataire introuvable, ou non approuvé` — un dossier non
approuvé n'a **pas** de fiche publique, même en connaissant son identifiant.
L'UI affiche « Ce prestataire n'est plus disponible » et propose de revenir à la
recherche (cas typique : un favori suspendu depuis).

**Actions depuis la fiche :** « Ajouter aux favoris » (§3.3, exige un compte) et
**« Réserver »** (§3.6, exige un compte). Un visiteur non connecté qui appuie sur
« Réserver » est renvoyé vers la connexion **avec retour sur la fiche** après
authentification (`go_router` : mémoriser la route d'origine).

---

### 3.6 Création de réservation — `POST /missions`

C'est l'écriture la plus sensible de l'application. Trois choses la rendent
particulière : une longue liste de validations serveur, un plafond de débit
(10/heure), et **l'en-tête `Idempotency-Key`**.

#### Corps de la requête

Source : [mobile-dto.ts:22-47](apps/api/src/modules/missions/mobile-dto.ts:22).

| Champ | Obligatoire | Règle | Message |
|---|---|---|---|
| `providerId` | **Oui** | UUID | `Prestataire invalide` |
| `packId` | **Oui** | UUID, **doit appartenir à ce prestataire** | `Formule invalide` |
| `optionIds` | Non | tableau d'UUID, **uniques**, **≤ 10** | `La même option est indiquée plusieurs fois` / `Pas plus de 10 options` |
| `scheduledAt` | **Oui** | **ISO 8601** — ex. `2026-08-02T09:00:00Z` | `La date doit être au format ISO (ex : 2026-08-02T09:00:00Z)` |
| `addressId` | **Oui** | UUID d'une adresse **du carnet du client** | `Adresse invalide` |
| `instructions` | Non | ≤ 500 | `Les instructions ne peuvent pas dépasser 500 caractères` |

⚠️ **`scheduledAt` doit être envoyé en UTC.** Le contrôle de créneau compare
`getUTCDay()` et l'heure UTC aux créneaux hebdomadaires (§2.2 P6). En Flutter :
`dateTime.toUtc().toIso8601String()`.

#### Écran de réservation — enchaînement recommandé

1. **Formule** — choisie sur la fiche publique (`services[].packs[]`).
2. **Options** — cases à cocher sur `packs[].options[]`. Recalculer en direct
   le **prix total** (`pack.price + Σ option.price`) et la **durée totale**
   (`pack.durationMinutes + Σ option.durationMinutes`) : ce sont exactement les
   formules du serveur
   ([mission-booking.service.ts:120-140](apps/api/src/modules/missions/mission-booking.service.ts:120)).
3. **Date et heure** — restreindre le sélecteur avec `availability[]` et
   `upcomingUnavailabilities[]` de la fiche publique, **et** vérifier que
   `début + durée totale` tient **entièrement** dans un créneau. Le serveur
   applique cette règle (`endTime >= endTime calculé`) : une intervention de 60 min
   à 11 h 30 sur un créneau fermant à 12 h est **refusée**.
4. **Adresse** — sélecteur sur `GET /me/addresses`, adresse par défaut
   présélectionnée. Si le carnet est vide, ouvrir d'abord §3.2.
5. **Instructions** — champ libre, compteur 500.
6. **Récapitulatif + bouton « Confirmer »** — c'est ici que la clé
   d'idempotence est **générée**.

Le **délai minimum de réservation** est de **60 minutes** par défaut
(`mission.min_lead_time_minutes`). ✅ **Écart n°6 clos : ce réglage se lit
désormais via `GET /settings/public` → `missionMinLeadTimeMinutes`.** Appeler
cette route au démarrage (§8) et bloquer le sélecteur sur la valeur EN
VIGUEUR plutôt que sur 60 min codé en dur — le serveur reste de toute façon
l'autorité finale en cas de désaccord (le message du `400` est interpolé avec
la valeur réelle).

#### `Idempotency-Key` — comment la générer et la réutiliser

Mécanique vérifiée
([idempotency.service.ts](apps/api/src/common/idempotency/idempotency.service.ts)
et [mission-actions.controller.ts:103-132](apps/api/src/modules/missions/mission-actions.controller.ts:103)) :

- L'en-tête est **facultatif**. Sans lui, aucune protection : un rejeu crée une
  seconde mission. **L'envoyer systématiquement.**
- La clé est portée par le triplet (`userId`, `POST /missions`, `key`) et vit
  **10 minutes**.
- Rejeu d'une clé **terminée** → **200/201 avec la mission d'origine** et le
  message `Réservation déjà enregistrée`. Rien n'est recréé.
- Rejeu d'une clé **encore en vol** → **409
  `Une requête identique est déjà en cours de traitement. Réessayez dans
  quelques instants.`**
- En cas d'échec métier, la clé est **libérée** : le client peut corriger et
  réessayer **avec la même clé** ou une nouvelle, indifféremment.

**Règle d'application :**

> La clé est un UUID v4 généré **une seule fois, au moment où l'écran de
> récapitulatif s'affiche**, et conservée dans l'état de l'écran. Tous les appuis
> sur « Confirmer », **y compris les rejeux automatiques après timeout réseau**,
> réutilisent **cette même clé**. Une nouvelle clé n'est générée que si
> l'utilisateur **modifie le contenu de la réservation** (formule, options, date,
> adresse) ou repart d'un nouvel écran de réservation.

```dart
// features/booking/presentation/booking_summary_controller.dart
@riverpod
class BookingDraft extends _$BookingDraft {
  @override
  BookingDraftState build() =>
      BookingDraftState(idempotencyKey: const Uuid().v4());

  /// Toute modification du contenu invalide la clé : ce n'est plus la même
  /// réservation, la protection ne doit pas les confondre.
  void updateContent(BookingDraftState next) {
    state = next.copyWith(idempotencyKey: const Uuid().v4());
  }
}
```

⚠️ **Ne pas générer la clé dans le `build()` d'un widget** : chaque
reconstruction produirait une clé neuve et annulerait la protection.

#### curl complet

```bash
curl -i -X POST "$API/missions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: 9f2b7c14-6d3e-4a58-b0c1-2e5f8a7d4b31" \
  -d '{
    "providerId": "bb1397e8-ff8f-4142-a9f9-b0a0d07dfa5c",
    "packId": "8fd727f4-65c7-4086-a72e-0ab231584612",
    "optionIds": [],
    "scheduledAt": "2026-08-05T09:00:00Z",
    "addressId": "b7ff0e66-b9cd-4f67-9782-e786212d8961",
    "instructions": "Fuite sous l évier, portail bleu."
  }'
```

**Réponse 201** — `data` est le **détail complet de la mission**
(`MissionDetailDto`, même forme que `GET /missions/:id`, capture en §3.7), avec
`status: "pending_provider"` et `quotedAmount` figé.

#### Tous les codes d'erreur et la réaction attendue

| Code | Message serveur | Origine | Réaction de l'UI |
|---|---|---|---|
| **400** | `Date d'intervention invalide` | `scheduledAt` non parsable | Bannière, retour au sélecteur de date. |
| **400** | `Une réservation doit être posée au moins 60 minutes à l'avance` | délai minimum (interpolé) | Afficher le message serveur **tel quel** (le nombre vient du réglage), rouvrir le sélecteur. |
| **400** | `Ce prestataire ne prend pas de réservation actuellement` | `availabilityStatus == unavailable` | Écran bloquant + retour à la recherche. |
| **400** | `Vous ne pouvez pas réserver votre propre prestation` | — | À prévenir côté client (comparer avec `GET /me.providerId`). |
| **400** | `Option inconnue pour cette formule : <uuid>` | option d'une autre formule | Recharger la fiche publique (le catalogue a changé). |
| **400** | `Cette adresse n'est pas géolocalisée : elle ne peut pas servir de lieu d'intervention` | adresse sans lat/lng | Ouvrir l'édition d'adresse (§3.2). |
| **400** | `Ce prestataire n'a déclaré aucune zone d'intervention` | — | Retour à la recherche. |
| **400** | **`Cette adresse n'est pas dans la zone d'intervention du prestataire`** | contrôle haversine | ⚠️ **Erreur la plus probable en usage réel.** Proposer explicitement « Choisir une autre adresse » et afficher les `zones[]` couvertes (déjà en cache depuis la fiche publique). |
| **400** | `Le prestataire n'est pas disponible sur ce créneau` | hors agenda hebdomadaire | Rouvrir le sélecteur en surlignant les créneaux valides. |
| **400** | `Le prestataire est absent à cette date` | `upcomingUnavailabilities` | Idem. |
| **400** | `Ce créneau est déjà réservé chez ce prestataire` | collision avec une autre mission | ⚠️ **Non détectable côté client** — les missions des autres ne sont pas visibles. Message « Ce créneau vient d'être pris », rouvrir le sélecteur. |
| **400** | `Vous avez déjà une réservation en cours avec ce prestataire sur ce créneau` | anti-doublon | Proposer « Voir ma réservation ». |
| **401** | `Bearer token required` | — | Intercepteur (§2.3). |
| **404** | `Prestataire introuvable ou non disponible à la réservation` | non approuvé / compte inactif | Retour à la recherche. |
| **404** | `Formule introuvable, inactive, ou ne correspondant pas à ce prestataire` | — | Recharger la fiche publique. |
| **404** | `Adresse introuvable dans votre carnet` | — | Recharger `GET /me/addresses`. |
| **409** | `Une requête identique est déjà en cours de traitement. Réessayez dans quelques instants.` | clé en vol | **Ne pas afficher d'erreur.** Garder l'indicateur de chargement, réessayer après ~2 s (2 tentatives max), puis rafraîchir `GET /me/missions` — la mission a probablement été créée. |
| **429** | — | 10 réservations/heure | « Vous avez atteint la limite de réservations pour cette heure. » |

**États de l'écran :** le bouton « Confirmer » passe en chargement et **reste
désactivé** jusqu'à la réponse. Sur erreur 400 « corrigeable » (créneau, adresse),
revenir à l'étape concernée en conservant le reste du brouillon.

---

### 3.7 Mes missions — liste, détail, annulation, reprogrammation

#### Liste — `GET /me/missions`

Paramètres ([mobile-dto.ts:50-65](apps/api/src/modules/missions/mobile-dto.ts:50)) :

| Paramètre | Contrainte | Message |
|---|---|---|
| `status` | une valeur de `MissionStatus` | `Statut de mission inconnu` |
| `from`, `to` | date ISO (`AAAA-MM-JJ` accepté) | `« from » doit être au format AAAA-MM-JJ` |
| `page`, `limit` | ≥ 1, `limit` ≤ **100** | — |
| `sort` | `scheduledAt`, `createdAt`, `status` (± `:asc`/`:desc`) | **mode tolérant** : une valeur inconnue **ne provoque pas d'erreur**, elle retombe sur le tri par défaut |

**Tri par défaut côté client : `scheduledAt desc`** (l'historique récent
d'abord) — à l'inverse du prestataire (§4.1).

`to` est **inclusif** : le serveur ajoute un jour à la borne
([mission-booking.service.ts:484-488](apps/api/src/modules/missions/mission-booking.service.ts:484)).

```bash
curl -s "$API/me/missions?status=confirmed&page=1&limit=20" \
  -H "Authorization: Bearer $TOKEN"
```

**Capture réelle :**

```json
{
  "success": true,
  "message": "OK",
  "data": [
    {
      "id": "b86332d9-14a0-4ec8-b5d0-d0158ae1824d",
      "status": "confirmed",
      "scheduledAt": "2026-08-03T14:00:00.000Z",
      "quotedAmount": null,
      "durationMinutes": 60,
      "packTitle": "Réparation de fuite simple",
      "clientName": "Awa Client",
      "providerId": "66cb6dd8-f882-4944-91ab-b5c052e01b3d",
      "providerName": "Kofi Plomberie",
      "providerAvatarFileId": null,
      "city": "Abidjan",
      "commune": "Cocody",
      "createdAt": "2026-07-19T11:16:12.582Z"
    }
  ],
  "meta": { "page": 1, "limit": 20, "total": 1 }
}
```

⚠️ **`quotedAmount` peut être `null`** — c'est le cas sur cette mission de
démonstration créée avant l'introduction du montant figé. L'UI doit gérer
l'absence de prix (afficher « — » plutôt que « 0 XOF »).

**Onglets recommandés**, construits sur `status` :

| Onglet | Filtre |
|---|---|
| À venir | `status=pending_provider,confirmed` |
| En cours | `status=in_progress` |
| Terminées | `status=completed,closed` |
| Annulées | `status=cancelled` |

✅ **Écart n°7 clos : `status` accepte une liste séparée par des virgules.**
`?status=completed,closed` renvoie l'union exacte des deux statuts, en **un
seul appel**, avec `meta.total` qui reflète cette union — plus besoin de
fusionner plusieurs appels ni de charger une liste non filtrée pour regrouper
côté client. La forme scalaire (`?status=confirmed`) continue de fonctionner à
l'identique. **Une liste contenant un seul statut inconnu est refusée en bloc**
(400 `Statut de mission inconnu`), comme c'était déjà le cas pour une valeur
unique invalide.

```bash
curl -s "$API/me/missions?status=completed,closed&limit=20" \
  -H "Authorization: Bearer $TOKEN"
```

S'applique aussi à `GET /providers/me/missions` (§4.1), avec le même mécanisme.

**États :** `data: []` par onglet → message spécifique (« Aucune mission à
venir », avec bouton « Réserver une prestation » sur l'onglet À venir).

#### Détail — `GET /missions/:id`

Accessible **aux deux parties**. `403 Vous n'êtes pas partie à cette mission` sinon.

```bash
curl -s "$API/missions/b86332d9-14a0-4ec8-b5d0-d0158ae1824d" \
  -H "Authorization: Bearer $TOKEN"
```

**Capture réelle** (structure `data`) :

```json
{
  "id": "b86332d9-14a0-4ec8-b5d0-d0158ae1824d",
  "status": "confirmed",
  "scheduledAt": "2026-08-03T14:00:00.000Z",
  "instructions": "Fuite sous l'évier de la cuisine.",
  "quotedAmount": null,
  "createdAt": "2026-07-19T11:16:12.582Z",
  "client":   { "id": "71e88780-…", "firstName": "Awa", "lastName": "Client" },
  "provider": { "id": "66cb6dd8-…", "publicName": "Kofi Plomberie", "score": 0, "reviewsCount": 0, "avatarFileId": null },
  "pack": {
    "id": "3a07a023-…", "title": "Réparation de fuite simple", "price": 15000, "durationMinutes": 60,
    "providerService": { "title": "Dépannage plomberie à domicile", "serviceType": { "name": "Réparation de fuite" } }
  },
  "options": [],
  "address": { "id": "b7ff0e66-…", "label": "Domicile", "city": "Abidjan", "commune": "Cocody",
               "details": "Rue des Jardins, villa 12", "latitude": 5.35, "longitude": -3.98 },
  "thread":  { "id": "e6499753-…", "status": "open" },
  "cancellation": null,
  "reschedules": [],
  "reviews": [ { "id": "423c7674-…", "authorId": "71e88780-…", "rating": 2 } ]
}
```

Points d'usage :

- **`thread.id`** est la porte d'entrée de la messagerie (§3.10). Le fil existe
  **dès la création** de la mission — le prestataire peut poser une question
  avant d'accepter.
- **`reschedules[]` ne contient que les demandes `requested`** (en attente de
  réponse), pas l'historique. L'historique complet est sur
  `GET /missions/:id/reschedules`.
- **`reviews[]` est réduit à `{ id, authorId, rating }`.** Pour savoir si *moi*
  j'ai déjà noté : `reviews.any((r) => r.authorId == monUserId)`. C'est ce qui
  pilote l'affichage du bouton « Laisser un avis » (§3.9).
- **`cancellation`** (non nul si annulée) : `{ reason, details, late, createdAt }`.
  `late == true` signale une annulation tardive — l'afficher explicitement.
- Aucune coordonnée personnelle de l'autre partie (ni email, ni téléphone) n'est
  exposée : la mise en relation passe **exclusivement** par la messagerie.

#### Historique — `GET /missions/:id/history`

```json
{ "statusHistory": [ { "id":"…", "oldStatus":null, "newStatus":"pending_provider", "reason":"Réservation créée par le client", "createdAt":"…" } ],
  "reschedules":   [ { "id":"…", "oldScheduledAt":"…", "newScheduledAt":"…", "reason":"…", "createdAt":"…" } ] }
```

Alimente une frise chronologique sur le détail. Mêmes 401/403/404 que le détail.

#### Annulation — `POST /missions/:id/cancel`

Corps : `{ reason, details? }`.

| Champ | Règle | Message |
|---|---|---|
| `reason` | **obligatoire**, 3–500 caractères | `Un motif est obligatoire (au moins 3 caractères)` |
| `details` | optionnel, ≤ 1000 | — |

**Le client peut annuler depuis `pending_provider` et `confirmed`.** Depuis tout
autre statut : `400 Transition de mission invalide : <from> → cancelled`.

```bash
curl -i -X POST "$API/missions/b86332d9-14a0-4ec8-b5d0-d0158ae1824d/cancel" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reason":"Empêchement de dernière minute","details":"Je serai absent toute la journée."}'
```

**Réponse 200 :**

```json
{
  "success": true,
  "message": "Mission annulée. L'annulation est enregistrée comme tardive.",
  "data": { "missionId": "…", "previousStatus": "confirmed", "status": "cancelled", "late": true }
}
```

⚠️ **`late` est calculé, jamais bloquant.** Une annulation à moins de
**6 heures** (`mission.cancellation_notice_hours`) de l'horaire est **acceptée**
et marquée `late: true` — le backend explique pourquoi
([mission-lifecycle.service.ts:170-178](apps/api/src/modules/missions/mission-lifecycle.service.ts:170)) :
bloquer pousserait le client à ne pas prévenir du tout.

→ **L'UI doit avertir avant l'appel** (« Cette annulation sera enregistrée comme
tardive »), pas après. ✅ **Écart n°6 clos** : ce seuil se lit via
`GET /settings/public` → `missionCancellationNoticeHours`, pour l'avertissement
préalable ; le `message` serveur, affiché après coup, reste l'autorité finale.

| Code | Message | Réaction |
|---|---|---|
| 200 | `Mission annulée` **ou** `Mission annulée. L'annulation est enregistrée comme tardive.` | Afficher le message serveur. Invalider liste + détail + notifications. |
| 400 | `Un motif d'annulation est obligatoire` | Champ motif. |
| 400 | `Transition de mission invalide : completed → cancelled` | Le statut a changé. Rafraîchir le détail. |
| 403 | `Vous n'êtes pas partie à cette mission` | — |
| 404 | `Mission introuvable` | — |

#### Reprogrammation, côté client

**Proposer** — `POST /missions/:id/reschedule`, corps
`{ newDate (ISO), reason? (≤500) }`.

```bash
curl -i -X POST "$API/missions/b86332d9-14a0-4ec8-b5d0-d0158ae1824d/reschedule" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"newDate":"2026-08-06T10:00:00Z","reason":"Je ne serai pas là mercredi."}'
```

Réponse 200, message
`Demande de report envoyée. Elle doit être acceptée par l'autre partie.`,
`data: { id, newScheduledAt, reason, status: "requested", createdAt }`.

| Code | Message | Réaction |
|---|---|---|
| 400 | `Une mission au statut « completed » ne peut plus être reprogrammée` | Seuls `pending_provider` et `confirmed` sont reprogrammables. |
| 400 | `Date de report invalide` | — |
| 400 | `La nouvelle date doit être au moins 60 minutes dans le futur` | Message interpolé. |
| 400 | `La nouvelle date est identique à la date actuelle` | — |
| 400 | **`Une demande de report est déjà en attente de réponse`** | **Une seule demande en vol à la fois.** Griser le bouton quand `mission.reschedules` est non vide. |
| 400 | `Le prestataire ne travaille pas sur ce créneau` / `Le prestataire est absent à cette date` / `Le prestataire a déjà une mission sur ce créneau` | Rouvrir le sélecteur. |

**Répondre à une proposition du prestataire** —
`POST /missions/:id/reschedule/:rid/accept` (pas de corps) ou
`POST /missions/:id/reschedule/:rid/reject` (corps `{ reason }`, 3–500).

```bash
curl -i -X POST "$API/missions/<missionId>/reschedule/<rescheduleId>/accept" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Length: 0"
```

Réponse accept : `{ id, status: "accepted", scheduledAt }` — **la mission est
déplacée**. Réponse reject : `{ id, status: "rejected" }` — la date d'origine tient.

| Code | Message | Réaction |
|---|---|---|
| 400 | `Cette demande a déjà été traitée (statut « accepted »)` | Rafraîchir le détail. |
| 400 | `Le prestataire n'est plus disponible sur ce créneau` | Le créneau est **revalidé au moment de l'acceptation**. Proposer une contre-proposition. |
| 400 | `Un motif est obligatoire pour refuser un report` | Champ motif. |
| **403** | `Vous ne pouvez pas répondre à votre propre demande de report` | **Toujours masquer Accepter/Refuser sur ses propres demandes** : comparer `reschedule.createdBy` à `GET /me.id`. |
| 404 | `Demande de report introuvable` | — |

**Historique** — `GET /missions/:id/reschedules` renvoie toutes les demandes
avec `{ id, oldScheduledAt, newScheduledAt, reason, status, createdBy, decidedBy,
decidedAt, decisionReason, createdAt }`. `status` ∈ `requested`, `accepted`,
`rejected`, `applied`.

---

### 3.8 Litige — `POST /disputes`

Accessible au client comme au prestataire, sur **leur** mission.
`GET /disputes/:id` pour le suivi (les commentaires internes des agents ne sont
jamais renvoyés). Ces deux routes n'ont pas de DTO de réponse Swagger : la forme
exacte de `data` n'est pas contractualisée — l'implémenter en s'appuyant sur
`disputes.service.ts` au moment du développement de l'écran, et non sur ce
document.

---

### 3.9 Dépôt d'avis — `POST /missions/:id/review`

Corps : `{ rating (entier 1–5), comment? (≤ 1000) }`.

```bash
curl -i -X POST "$API/missions/b86332d9-14a0-4ec8-b5d0-d0158ae1824d/review" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"rating":5,"comment":"Intervention rapide et propre. Je recommande."}'
```

**Réponse 201 :** `{ id, rating, comment, status: "published", createdAt }`,
message `Merci, votre avis est publié`.

#### Les quatre règles, dans l'ordre où le serveur les applique

Source : [review-submission.service.ts:41-95](apps/api/src/modules/reviews/review-submission.service.ts:41).

1. **Mission `completed` ou `closed`** — sinon
   `400 Vous pourrez déposer un avis une fois la mission terminée`.
2. **Être partie à la mission** — sinon `403 Vous n'êtes pas partie à cette mission`.
3. **Être le client** — `403 Seul le client peut déposer un avis en V1`. Le
   prestataire **ne peut pas** noter le client. L'UI ne doit donc **jamais**
   afficher le bouton « Laisser un avis » côté prestataire.
4. **Fenêtre temporelle** — `400 La fenêtre de dépôt d'avis (14 jours) est
   dépassée`. Le décompte part de l'**entrée `completed` dans l'historique de la
   mission** (pas de `updatedAt`), et la durée vient du réglage
   `reviews.window_days`, **valeur de repli 14 jours**.
5. **Un seul avis par mission et par auteur** — `409 Vous avez déjà déposé un
   avis sur cette mission` (doublé d'une contrainte d'unicité en base).

#### Ce que l'application peut calculer elle-même

| Condition | Donnée disponible | Vérifiable côté client ? |
|---|---|---|
| Mission terminée | `mission.status` | **Oui** |
| Je suis le client | `mission.client.id == GET /me.id` | **Oui** |
| Avis déjà déposé | `mission.reviews.any((r) => r.authorId == monId)` | **Oui** |
| Fenêtre de dépôt | date de passage à `completed` via `GET /missions/:id/history` (`statusHistory` où `newStatus == "completed"`) | **Oui**, au prix d'un appel supplémentaire — la durée se lit désormais via `GET /settings/public` → `reviewsWindowDays` (écart n°6 clos), plutôt qu'une constante figée à 14 jours |

→ **Règle d'affichage du bouton « Laisser un avis » :** statut ∈
{`completed`, `closed`} **ET** je suis le client **ET** aucun avis de moi **ET**
`completedAt + 14 j > maintenant`. Afficher un compte à rebours discret
(« Vous pouvez encore noter cette prestation pendant 9 jours ») ; le serveur
reste l'autorité en cas de désaccord.

#### Mes avis — `GET /me/reviews`

Paginé, `sort` ∈ `createdAt`, `rating` (mode tolérant). **Capture réelle :**

```json
{
  "success": true, "message": "OK",
  "data": [
    {
      "id": "423c7674-bc74-4c3c-b972-077a5ea51c40",
      "rating": 2,
      "comment": "Travail correct mais retard important.",
      "status": "reported",
      "createdAt": "2026-07-19T11:16:12.606Z",
      "mission": {
        "id": "b86332d9-14a0-4ec8-b5d0-d0158ae1824d",
        "scheduledAt": "2026-08-03T14:00:00.000Z",
        "provider": { "id": "66cb6dd8-…", "publicName": "Kofi Plomberie", "avatarFileId": null }
      }
    }
  ],
  "meta": { "page": 1, "limit": 20, "total": 1 }
}
```

`status` ∈ `published`, `reported`, `hidden`, `rejected`. Un avis `reported`
**reste visible** (le signalement ne masque pas — seul un modérateur décide).
`hidden` / `rejected` : afficher une mention « Cet avis a été retiré par la
modération ». **Il n'existe pas de route pour modifier ou supprimer son propre
avis** (§7, écart n°9).

#### Signaler un avis — `POST /reviews/:id/report`

Corps `{ reason }` (3–500). Réponse 200 `{ reported: true }`, message
`Signalement enregistré. Un modérateur va l'examiner.`

| Code | Message | Réaction |
|---|---|---|
| 400 | `Vous ne pouvez pas signaler votre propre avis` | Masquer l'action sur ses propres avis. |
| 409 | `Vous avez déjà signalé cet avis` | Afficher « Déjà signalé ». |
| 429 | — | **20 signalements par jour.** |

---

### 3.10 Notifications

#### Liste — `GET /me/notifications`

Paramètres : `page`, `limit` (≤ 100), `sort`, et **`unread=true|false`**
(transformé explicitement côté serveur — `"false"` est bien interprété comme
`false`). Erreur : `« unread » doit valoir true ou false`.

```bash
curl -s "$API/me/notifications?unread=true&page=1&limit=20" \
  -H "Authorization: Bearer $TOKEN"
```

Élément : `{ id, type, title, body, data, readAt, createdAt }`.

**`data`** est l'objet structuré qui permet d'**ouvrir le bon écran**. Formes
émises par le backend (vérifiées dans les services) :

| Origine | `data` |
|---|---|
| Cycle de vie mission | `{ missionId, type: "mission" }` |
| Message de conversation | `{ missionId, threadId, type: "chat" }` |
| Demande de report | `{ missionId, rescheduleId, type: "reschedule" }` |
| Avis reçu | `{ missionId, reviewId, type: "review" }` |

→ Une seule fonction de routage (`_handleNotificationPayload`) sert **à la fois**
au tap sur une notification de la liste et au tap sur un push (§5.3) : les deux
transportent la même charge utile.

**Codes de notification existants** (`notification-events.service.ts`) :
`mission.created`, `mission.accepted`, `mission.refused`, `mission.started`,
`mission.completed`, `mission.cancelled`, `mission.expired`, `mission.reminder`,
`mission.reschedule.requested`, `mission.reschedule.accepted`, `review.received`,
`review.request`, `provider.approved`, `provider.changes_requested`,
`provider.rejected`, `dispute.opened`, `dispute.message`, `dispute.decided`,
`chat.message`.

**État vide vérifié** : sur le compte démo, `data: []` avec
`meta: { page: 1, limit: 2, total: 0 }`.

#### Badge — `GET /me/notifications/unread-count`

`{ "unread": 3 }`. Appel léger, sans charger la liste. **À rafraîchir** au
démarrage, au retour au premier plan, et à la réception d'un push.

#### Marquage lu

- `PATCH /me/notifications/:id/read` → `{ updated: 1 }`. **Idempotent** : une
  notification déjà lue, inexistante ou appartenant à un autre compte renvoie
  `{ updated: 0 }`, **jamais d'erreur**. Mise à jour optimiste sans risque.
- `POST /me/notifications/read-all` → `{ updated: n }`, message
  `n notification(s) marquée(s) lue(s)`.

Il n'existe **pas** de route de suppression d'une notification.

---

### 3.11 Conversations liées à une mission

#### Liste de mes conversations — `GET /me/threads`

Paginé (`page`, `limit`, `sort`). Conçu pour l'onglet Messagerie, afin de ne pas
interroger mission par mission. **Capture réelle :**

```json
{
  "success": true, "message": "OK",
  "data": [
    {
      "id": "e6499753-89c6-4a9f-bdc9-b3ff4508be47",
      "missionId": "b86332d9-14a0-4ec8-b5d0-d0158ae1824d",
      "missionStatus": "confirmed",
      "scheduledAt": "2026-08-03T14:00:00.000Z",
      "status": "open",
      "counterpartName": "Kofi Plomberie",
      "counterpartAvatarFileId": null,
      "lastMessage": {
        "id": "b4169c91-…",
        "message": "Bonjour, à quelle heure passez-vous ?",
        "senderId": "71e88780-d204-4145-b06d-b9e3acdbb365",
        "createdAt": "2026-07-19T11:16:12.592Z"
      },
      "unreadCount": 1,
      "createdAt": "2026-07-19T11:16:12.592Z"
    }
  ],
  "meta": { "page": 1, "limit": 20, "total": 1 }
}
```

`counterpartName` est déjà résolu **du bon côté** : la même route sert au client
et au prestataire, sans logique conditionnelle dans l'application.
`counterpartAvatarFileId` se charge via `GET /files/:id/content` — comme tout
avatar (§3.4), cette route est accessible sans jeton pour un fichier `public`
(écart n°5, clos).

**Badge messagerie :** ✅ **écart n°4 clos.** `GET /me/threads/unread-count`
existe désormais, sur le modèle exact de
`GET /me/notifications/unread-count` :

```bash
curl -s "$API/me/threads/unread-count" -H "Authorization: Bearer $TOKEN"
# { "success": true, "message": "OK", "data": { "unread": 3 } }
```

Le compte est **global, tous fils confondus**, et exclut les messages que j'ai
moi-même envoyés (seuls ceux des autres comptent comme non lus) — exactement
la même règle que `unreadCount` par fil dans `GET /me/threads`, dont ce nouveau
compteur est la somme exacte. **Il n'est plus nécessaire de sommer la première
page de `/me/threads`** : utiliser cette route pour la pastille de l'onglet
Messagerie.

#### Lire une conversation — `GET /messages/threads/:id/messages`

⚠️ **PAGINÉE depuis la rédaction initiale de ce document (décision F, écart
n°12, clos).** Cette route renvoyait auparavant **tous** les messages en un
seul tableau, sans limite de taille ni `meta` — viable pour quelques échanges,
plus du tout pour un fil qui s'étale sur des mois.

**Ancienne forme (obsolète, à ne plus développer contre) :**

```json
{ "success": true, "message": "OK", "data": [ /* TOUS les messages du fil */ ] }
```

**Forme actuelle** — mêmes paramètres que toute autre liste de l'API
(`page`, `limit`, `sort`, via `PaginationQueryDto`), pas un mécanisme propre à
la messagerie :

```json
{
  "success": true, "message": "OK",
  "data": [ /* UNE PAGE de messages */ ],
  "meta": { "page": 1, "limit": 20, "total": 47 }
}
```

Élément de `data` : `{ id, senderId, message, createdAt, readAt?, files: [ { file: { id, originalName, mimeType, size } } ] }`.
`senderId` peut être `null` (message système). `senderId == GET /me.id` distingue
« moi » de « l'autre ».

**Le tri par défaut reste `createdAt` CROISSANT** (le plus ancien d'abord) —
c'est l'ordre qu'avait déjà cette route avant sa pagination. **La page 1
correspond donc au DÉBUT de la conversation**, pas à ses messages les plus
récents : un écran qui veut afficher la fin du fil en premier doit soit
demander `?sort=-createdAt`, soit calculer la dernière page à partir de
`meta.total` et `limit`.

```bash
curl -s "$API/messages/threads/e6499753-89c6-4a9f-bdc9-b3ff4508be47/messages?page=1&limit=20" \
  -H "Authorization: Bearer $TOKEN"

# Les 20 plus récents, dans l'ordre chronologique inverse :
curl -s "$API/messages/threads/e6499753-89c6-4a9f-bdc9-b3ff4508be47/messages?limit=20&sort=-createdAt" \
  -H "Authorization: Bearer $TOKEN"
```

⚠️ **Il n'y a toujours pas de temps réel** (ni WebSocket, ni SSE). L'écran de
conversation doit reposer sur : chargement à l'ouverture, **pull-to-refresh**,
et **rafraîchissement déclenché par le push `chat.message`**. La pagination ne
change rien à ce point — elle borne la taille d'un appel, elle ne remplace pas
un canal temps réel (toujours en écart, voir §7 n°12).

#### Envoyer — `POST /messages/threads/:id/messages`

Corps : `{ message (1–4000), fileIds? }`.

| Champ | Règle | Message |
|---|---|---|
| `message` | 1–4000 | `Le message ne peut pas être vide` |
| `fileIds` | UUID, uniques, **≤ 3** | `Le même fichier est joint plusieurs fois` / `Pas plus de 3 pièces jointes par message` |

Pièces jointes : même découpage qu'en §2.2 P7 — `POST /files/upload` d'abord,
puis les `fileIds` ici.

```bash
curl -i -X POST "$API/messages/threads/e6499753-89c6-4a9f-bdc9-b3ff4508be47/messages" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message":"Bonjour, je serai là vers 14h."}'
```

Réponse 201, message `Message envoyé`, `data` = le message créé.

| Code | Message | Réaction |
|---|---|---|
| 201 | `Message envoyé` | Ajouter à la liste. **Envoi optimiste recommandé** avec état « en cours » puis confirmation. |
| **400** | `Conversation clôturée, ou pièce jointe introuvable/ne vous appartenant pas` | Si `thread.status != "open"`, **masquer le champ de saisie en amont**. |
| 403 | `Vous n'êtes pas partie à la mission de cette conversation` | — |
| 404 | `Conversation ou mission introuvable` | — |

**Notification de l'interlocuteur :** automatique, avec **regroupement des push à
un par fil et par minute** (`groupKey: thread:<id>`). Au-delà, la notification
reste in-app. Ne pas s'attendre à un push par message.

#### Marquer lu — `PATCH /messages/threads/:id/read`

Pas de corps. Réponse 200 `{ updated: n }`, message
`n message(s) marqué(s) lu(s)`. À appeler **à l'ouverture de la conversation**,
puis rafraîchir `GET /me/threads` pour remettre `unreadCount` à zéro.

#### Depuis une mission — `GET /missions/:id/thread`

`{ id, missionId, status, messageCount, createdAt }`. Utile quand on arrive
depuis le détail d'une mission sans avoir chargé `/me/threads`.
`404` si la mission n'a pas de conversation.

---

## 4. Écrans et parcours — côté PRESTATAIRE

**Préalable commun.** Toutes les routes `/providers/me/*` répondent
`403 Ce compte n'a pas de profil prestataire` si `POST /providers/me` n'a pas été
fait. Les écrans de cette section supposent
`GET /me.hasProviderProfile == true`, et — sauf mention contraire —
`providerValidationStatus == "approved"`.

Les écrans **communs aux deux rôles** (profil utilisateur, mot de passe,
notifications, messagerie, adresses) sont ceux du §3 : mêmes routes, mêmes
composants. Ils ne sont pas redécrits ici.

---

### 4.1 Tableau de bord

⚠️ **Il n'existe pas d'endpoint d'agrégation « dashboard prestataire »**
(§7, écart n°10). Le tableau de bord se **compose** à partir de routes
existantes. Trois appels suffisent.

| Bloc | Appel | Détail |
|---|---|---|
| **En attente de mon action** | `GET /providers/me/missions?status=pending_provider&limit=20` | Le bloc le plus important : ce sont les demandes à accepter ou refuser. Compteur = `meta.total`. |
| **Missions du jour** | `GET /providers/me/missions?from=2026-08-05&to=2026-08-05&status=confirmed,in_progress&limit=50` | `from` et `to` au même jour. La borne `to` est **inclusive** (le serveur ajoute un jour). `status` accepte directement une liste depuis l'écart n°7 (clos) — plus besoin de filtrer côté client. |
| **Notifications non lues** | `GET /me/notifications/unread-count` | Pastille. |
| *(optionnel)* Conversations | `GET /me/threads/unread-count` | Pastille de l'onglet Messagerie — route dédiée depuis l'écart n°4 (clos), remplace la somme manuelle des `unreadCount` de `/me/threads`. |

`GET /providers/me/missions` accepte exactement les mêmes paramètres que
`GET /me/missions` (§3.7 — `status`, `from`, `to`, `page`, `limit`, `sort`) et
renvoie **le même `MissionListItemDto`**.

**Différence essentielle : le tri par défaut est `scheduledAt` CROISSANT**
([mission-booking.service.ts:325-331](apps/api/src/modules/missions/mission-booking.service.ts:325))
— le prestataire veut voir ce qui arrive, pas son historique. C'est l'inverse du
client. Ne pas retrier côté application.

```bash
curl -s "$API/providers/me/missions?status=pending_provider&limit=20" \
  -H "Authorization: Bearer $PROVIDER_TOKEN"
```

Dans le `MissionListItemDto`, côté prestataire les champs utiles sont
`clientName`, `city`, `commune`, `packTitle`, `durationMinutes`, `quotedAmount`,
`scheduledAt` (les champs `providerName` / `providerAvatarFileId` sont
redondants — c'est lui-même).

**Interrupteur de disponibilité**, à placer en évidence sur le tableau de bord :

```bash
curl -i -X PATCH "$API/providers/me" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"availabilityStatus":"unavailable"}'
```

Valeurs : `available`, `busy`, `unavailable`
([self-dto.ts:47](apps/api/src/modules/providers/self-dto.ts:47)).

| Valeur | Effet vérifié |
|---|---|
| `available` | Visible en recherche, `availableNow: true`. |
| `busy` | **Toujours visible en recherche et réservable** — le filtre d'office exclut seulement `unavailable`. Seul `availableNow` passe à `false`. |
| `unavailable` | **Disparaît de la recherche** et `POST /missions` renvoie `400 Ce prestataire ne prend pas de réservation actuellement`. |

→ L'UI doit expliquer la différence : « Occupé » = toujours réservable,
« Indisponible » = je ne prends plus de mission. Un libellé ambigu ferait choisir
`busy` à quelqu'un qui voulait fermer son agenda.

⚠️ **`availabilityStatus` est le seul champ modifiable en `pending_review`**
(§2.2 P9). L'interrupteur doit donc rester actif même pendant l'instruction du
dossier.

**États :** chargement → squelettes par bloc ; erreur sur un bloc →
n'invalide pas les autres (trois providers Riverpod indépendants) ; tous les
blocs vides → écran d'accueil « Aucune mission pour aujourd'hui ».

---

### 4.2 Gestion du profil, services, formules, zones, disponibilités

Ces écrans réutilisent **exactement** les routes du parcours d'onboarding (§2.2),
avec deux différences : ils sont accessibles en permanence après approbation, et
ils exposent les routes de **lecture** et de **mise à jour** que l'onboarding
n'utilise pas.

#### Profil — `GET /providers/me` / `PATCH /providers/me`

`GET` : forme complète en §2.2 P8 (avec `checklist`, `score`, `reviewsCount`).
Après approbation, la checklist reste utile comme **indicateur de qualité de la
fiche** (par exemple, `documents: false` si un justificatif a expiré).

`PATCH` — champs ([self-dto.ts:49-76](apps/api/src/modules/providers/self-dto.ts:49)),
tous optionnels :

| Champ | Règle |
|---|---|
| `publicName` | 2–120 |
| `bio` | ≤ 2000 |
| `experienceYears` | entier 0–70 |
| `availabilityStatus` | `available` \| `busy` \| `unavailable` |
| `avatarFileId` | UUID d'un fichier **m'appartenant** |

**Photo de profil — parcours en deux temps :**

```bash
# 1) envoyer l'image
curl -s -X POST "$API/files/upload" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -F "file=@/chemin/photo.jpg"
# → data.id

# 2) la rattacher au profil
curl -i -X PATCH "$API/providers/me" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"avatarFileId":"<data.id>"}'
```

Effet vérifié : la visibilité du fichier passe à **`public`**
([provider-self.service.ts:102](apps/api/src/modules/providers/provider-self.service.ts:102)).
C'est une décision explicite du prestataire, à expliciter dans l'UI
(« Cette photo sera visible par tous les visiteurs »).

| Code | Message | Réaction |
|---|---|---|
| 200 | `Profil mis à jour` | — |
| **400** | `Votre dossier est en cours de vérification : il n'est plus modifiable` | Champs grisés en `pending_review` (§2.2 P9). |
| **400** | `La photo de profil doit être une image` | Filtrer côté client sur `image/*`. |
| **404** | `Fichier introuvable ou ne vous appartenant pas` | Recommencer l'upload. |

#### Services — `GET` / `POST` / `PATCH /providers/me/services`

`GET /providers/me/services` (non paginé) renvoie, pour chaque service :

```json
{
  "id": "…", "title": "…", "description": "…", "active": true, "createdAt": "…",
  "serviceType": { "id": "…", "name": "…", "category": { "id": "…", "name": "…" } },
  "packs": [ { "id": "…", "title": "…", "price": 5000, "durationMinutes": 45, "active": true } ]
}
```

Les formules sont **imbriquées** et triées par prix croissant : un seul appel
alimente l'écran « Mes prestations ».

`PATCH /providers/me/services/:id` — corps `{ title?, description?, active? }`.

⚠️ **Il n'existe pas de suppression de service ni de formule.** Le retrait passe
par `active: false`. L'UI doit dire « Désactiver », pas « Supprimer », et
signaler l'effet : un service désactivé (ou dont toutes les formules sont
désactivées) fait **disparaître le prestataire de la recherche**, puisque le
filtre d'office exige au moins un service actif avec formule active (§3.4).
Voir §7, écart n°9.

`404 Service introuvable` si l'identifiant n'est pas celui d'un service du
prestataire connecté.

#### Formules et options

| Action | Route | Corps |
|---|---|---|
| Créer une formule | `POST /providers/me/service-packs` | §2.2 P4 |
| Modifier / désactiver | `PATCH /providers/me/service-packs/:id` | `{ title?, description?, price?, durationMinutes?, active? }` |
| Lister les options | `GET /providers/me/service-packs/:packId/options` | — |
| Ajouter une option | `POST /providers/me/service-packs/:packId/options` | `{ title, price, durationMinutes? }` |
| Modifier / désactiver une option | `PATCH /providers/me/service-pack-options/:id` | `{ title?, price?, durationMinutes?, active? }` |

⚠️ Noter l'asymétrie des chemins : la **création** d'option est imbriquée sous
`/service-packs/:packId/options`, mais la **modification** est à plat sous
`/service-pack-options/:id`.

**Effet d'un changement de prix :** le montant des missions déjà créées ne bouge
pas — `quotedAmount` est figé à la réservation
([mission-booking.service.ts:138-140](apps/api/src/modules/missions/mission-booking.service.ts:138)).
À indiquer dans l'UI pour lever l'ambiguïté.

#### Zones — `GET` / `PUT /providers/me/zones`

`GET` renvoie les zones du prestataire (`{ id, name, latitude, longitude,
radiusKm, active, city }`). `PUT` remplace la liste (§2.2 P5).
Écran : cases à cocher alimentées par `GET /zones`, pré-cochées avec
`GET /providers/me/zones`, envoi de l'état complet.

#### Disponibilités

- **Agenda hebdomadaire** — `PUT /providers/me/availabilities` (§2.2 P6). Pour
  **relire** l'agenda : ✅ **`GET /providers/me/availabilities` existe
  désormais** (écart n°11, clos) — miroir exact de ce que le `PUT` accepte, sans
  passer par son propre `providerId` ni par la route publique
  `GET /providers/:id/availabilities`.

  ```bash
  curl -s "$API/providers/me/availabilities" -H "Authorization: Bearer $PROVIDER_TOKEN"
  ```
- **Absences exceptionnelles** — `POST /providers/me/unavailabilities`
  (`{ startAt, endAt, reason? }`), `DELETE /providers/me/unavailabilities/:id`,
  et relecture via `GET /providers/:id/unavailabilities`.

```bash
curl -i -X POST "$API/providers/me/unavailabilities" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"startAt":"2026-08-10T00:00:00Z","endAt":"2026-08-17T23:59:59Z","reason":"Congés"}'
```

| Code | Message documenté | Réaction |
|---|---|---|
| 201 | `Indisponibilité enregistrée` | Rafraîchir le calendrier. |
| 400 | `Date de fin avant la date de début, ou période chevauchant une absence existante` | Reproduire les deux règles côté client. |
| 404 (sur DELETE) | `Indisponibilité introuvable` | L'appartenance est vérifiée : on ne supprime pas l'absence d'un confrère. |

---

### 4.3 Portfolio

| Action | Route | Notes |
|---|---|---|
| Lister | `GET /providers/me/portfolio` | Non paginé. `{ id, title, description, displayOrder, createdAt, file: { id, originalName, mimeType, visibility } }`, trié par `displayOrder` puis date. |
| Ajouter | `POST /providers/me/portfolio` | `{ fileId, title? (≤120), description? (≤1000), displayOrder? (0–100) }` |
| Modifier | `PATCH /providers/me/portfolio/:id` | `{ title?, description?, displayOrder? }` — **pas** `fileId` : pour changer l'image, supprimer et recréer. |
| Retirer | `DELETE /providers/me/portfolio/:id` | `{ removed: true }`, message `Réalisation retirée`. |

```bash
curl -i -X POST "$API/providers/me/portfolio" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"fileId":"<id renvoyé par /files/upload>","title":"Réfection salle de bain","displayOrder":0}'
```

| Code | Message | Réaction |
|---|---|---|
| 201 | `Réalisation ajoutée` | La visibilité du fichier passe à **`public`**. |
| **400** | `Votre portfolio est limité à 20 réalisations` | `MAX_PORTFOLIO_ITEMS = 20`. Griser « Ajouter » à 20. |
| **400** | `Une réalisation doit être une image` | Filtrer sur `image/jpeg`, `image/png`, `image/webp` avant l'envoi. |
| 404 | `Fichier introuvable ou ne vous appartenant pas` | — |

À la suppression, l'image **repasse en `restricted`** : retirée de la vitrine,
elle n'a plus de raison d'être publique. Si l'application met en cache les
images du portfolio, invalider ce cache après un `DELETE`.

**Réordonnancement :** il n'existe pas de route de réordonnancement en lot. Un
glisser-déposer se traduit par **un `PATCH` par élément déplacé** avec le nouveau
`displayOrder`. Sur une liste de 20, un lot séquentiel reste acceptable ; en cas
d'échec partiel, recharger la liste (l'ordre serveur fait foi).

---

### 4.4 Mes missions — machine à états et transitions autorisées

#### La machine à états réelle

Source unique et intégralement reproduite :
[mission-status.machine.ts:5-14](apps/api/src/modules/missions/mission-status.machine.ts:5).

```
draft            → pending_provider
pending_provider → confirmed | cancelled
confirmed        → in_progress | cancelled
in_progress      → completed | disputed
completed        → closed | disputed
disputed         → completed | closed | cancelled
cancelled        → (état final)
closed           → (état final)
```

Une transition non listée est refusée par
`400 Transition de mission invalide : <from> → <to>`, **avec le même message
côté mobile et côté back-office** — c'est l'objet du service de transition unique.

`cancelled` exige **toujours** un motif :
`400 Un motif est obligatoire pour passer au statut "cancelled"`.

#### Les quatre actions du prestataire

| Action | Route | Statut de départ **exigé** | Statut d'arrivée | Corps |
|---|---|---|---|---|
| Accepter | `POST /missions/:id/accept` | **`pending_provider`** | `confirmed` | aucun |
| Refuser | `POST /missions/:id/refuse` | **`pending_provider`** | `cancelled` | `{ reason }` (3–500) |
| Démarrer | `POST /missions/:id/start` | **`confirmed`** | `in_progress` | aucun |
| Terminer | `POST /missions/:id/complete` | **`in_progress`** | `completed` | aucun |
| Annuler | `POST /missions/:id/cancel` | `confirmed` (prestataire) | `cancelled` | `{ reason, details? }` |

Chacune vérifie **d'abord** que l'appelant est bien le prestataire de la mission
(`403 Vous n'êtes pas le prestataire de cette mission`), **puis** que le statut
correspond exactement — sinon
`400 Action impossible depuis le statut « <statut actuel> »`
([mission-lifecycle.service.ts:240-244](apps/api/src/modules/missions/mission-lifecycle.service.ts:240)).

**Réponse commune** aux cinq (`MissionTransitionResultDto`) :

```json
{
  "success": true,
  "message": "Mission acceptée",
  "data": { "missionId": "…", "previousStatus": "pending_provider", "status": "confirmed", "late": false }
}
```

#### Règles à traduire dans l'UI

**1. `refuse` et `cancel` ne sont pas interchangeables.**
Avant acceptation, le prestataire **refuse** ; après, il **annule**. Appeler
`cancel` sur une mission `pending_provider` renvoie
`400 Cette mission n'est pas encore acceptée : utilisez le refus
(POST /missions/:id/refuse)`.

→ **Le bouton affiché dépend du statut** : « Refuser » si `pending_provider`,
« Annuler » si `confirmed`. Ne jamais afficher les deux.

**2. Fenêtre de démarrage.**
`start` est refusé trop tôt :
`400 Vous pourrez démarrer cette mission au plus tôt 120 minutes avant l'heure
prévue` (réglage `mission.start_window_minutes`, **défaut 120 min**, message
interpolé).

→ Griser « Démarrer » tant que `maintenant < scheduledAt − X min`, avec un
libellé explicatif (« Disponible à partir de 12h00 »). ✅ **Écart n°6 clos** :
`X` se lit via `GET /settings/public` → `missionStartWindowMinutes`, plutôt
qu'une constante à 120 min figée à la compilation ; le message serveur reste
l'autorité en cas de désaccord.

**3. Annulation tardive.**
Même mécanique que côté client (§3.7) : acceptée, marquée `late: true` sous
6 heures. Avertir avant l'appel.

**4. Il n'existe pas de route pour clore (`closed`) ni pour marquer `disputed`
depuis l'application.** `closed` est atteint par un job planifié
(`mission.auto_close_days`, **défaut 7 jours** après `completed` — lisible via
`GET /settings/public` → `missionAutoCloseDays`, écart n°6 clos) ; `disputed`
par l'ouverture d'un litige (§3.8) ou par le back-office. **Ne pas exposer de
bouton pour ces transitions.**

**5. Expiration automatique.** Une mission `pending_provider` non traitée expire
au bout de `mission.pending_expiry_hours` (**défaut 24 h**, lisible via
`GET /settings/public` → `missionPendingExpiryHours`) via un job, avec la
notification `mission.expired`. → Afficher un compte à rebours sur les demandes
en attente (« Il vous reste 6 h pour répondre »).

#### Exemples curl

```bash
# Accepter
curl -i -X POST "$API/missions/<missionId>/accept" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" -H "Content-Length: 0"

# Refuser (motif obligatoire)
curl -i -X POST "$API/missions/<missionId>/refuse" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reason":"Je suis déjà engagé sur un autre chantier ce jour-là."}'

# Démarrer
curl -i -X POST "$API/missions/<missionId>/start" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" -H "Content-Length: 0"

# Terminer
curl -i -X POST "$API/missions/<missionId>/complete" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" -H "Content-Length: 0"

# Annuler après acceptation
curl -i -X POST "$API/missions/<missionId>/cancel" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"reason":"Panne de véhicule","details":"Je préviens le client par message."}'
```

#### Tableau récapitulatif des boutons par statut (côté prestataire)

| Statut | Boutons visibles | Autres actions |
|---|---|---|
| `pending_provider` | **Accepter**, **Refuser** | Message, Proposer un report |
| `confirmed` | **Démarrer** (grisé hors fenêtre), **Annuler** | Message, Proposer un report, Répondre à un report du client |
| `in_progress` | **Terminer** | Message |
| `completed` | — | Message, Ouvrir un litige |
| `closed`, `cancelled` | — | Consultation seule (`thread.status` peut être fermé) |
| `disputed` | — | Suivi du litige |

Après chaque transition réussie : invalider le détail, la liste des missions et
le compteur de notifications. La partie adverse est notifiée automatiquement —
**l'auteur de l'action n'est jamais notifié de sa propre action**
([mission-lifecycle.service.ts:260-266](apps/api/src/modules/missions/mission-lifecycle.service.ts:260)),
donc ne pas attendre de push de confirmation.

---

### 4.5 Reprogrammation côté prestataire

Les routes sont **strictement les mêmes** que côté client (§3.7) — le backend ne
distingue pas les deux parties, sauf sur un point : **on ne peut pas répondre à
sa propre demande**.

| Action | Route | Corps |
|---|---|---|
| Proposer une nouvelle date | `POST /missions/:id/reschedule` | `{ newDate (ISO), reason? }` |
| Accepter la proposition du client | `POST /missions/:id/reschedule/:rid/accept` | aucun |
| Refuser la proposition du client | `POST /missions/:id/reschedule/:rid/reject` | `{ reason }` (3–500) |
| Historique | `GET /missions/:id/reschedules` | — |

**Règle d'affichage, identique des deux côtés :**

```dart
final estMonProprePost = reschedule.createdBy == monUserId;
final peutRepondre = reschedule.status == 'requested' && !estMonProprePost;
```

Sans ce test, l'application affiche des boutons qui échoueront en
`403 Vous ne pouvez pas répondre à votre propre demande de report`.

**Spécificité prestataire :** quand *il* propose, la validation d'agenda porte
sur **son propre** agenda
([mission-reschedule.service.ts:252-309](apps/api/src/modules/missions/mission-reschedule.service.ts:252)).
Les erreurs `Le prestataire ne travaille pas sur ce créneau`,
`Le prestataire est absent à cette date` et
`Le prestataire a déjà une mission sur ce créneau` désignent donc **lui-même** —
le libellé côté prestataire doit être reformulé (« Vous ne travaillez pas sur ce
créneau »), en n'affichant pas le message serveur brut, qui serait déroutant.
C'est l'un des rares cas où le texte serveur ne doit **pas** être repris tel quel.

À l'acceptation, le créneau est **revalidé** : entre la demande et la réponse,
une autre mission a pu être prise. D'où le
`400 Le prestataire n'est plus disponible sur ce créneau`, à traiter en
proposant une contre-proposition.

---

### 4.6 Documents de vérification — statut et re-soumission

Écran alimenté par `GET /providers/me/documents` (forme complète en §2.2 P7).

**Construction de l'écran :**

```
pour chaque type de requiredTypes :
    doc = current.firstWhereOrNull((d) => d.type == type)
    si doc == null              → ligne ROUGE   « À fournir »           [Déposer]
    sinon selon doc.status :
        "pending"               → ligne ORANGE  « En cours d'examen »   [Voir]
        "approved"              → ligne VERTE   « Validé »              [Voir]   (dépôt interdit)
        "rejected"              → ligne ROUGE   « Refusé »              [Voir] [Redéposer]
                                  + afficher doc.rejectionReason
```

`missingTypes` donne directement la liste des lignes rouges — s'en servir comme
contrôle de cohérence plutôt que de recalculer.

Chaque ligne peut ouvrir l'**historique des versions** en filtrant `documents`
sur le `type` (tableau trié par `version` décroissante), avec pour chaque version
son `status`, son `rejectionReason` et son `reviewedAt`.

**Re-soumission après `changes_requested`** — deux temps (§2.2 P7) :

```bash
# 1) envoyer le nouveau justificatif
curl -s -X POST "$API/files/upload" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -F "file=@/chemin/cni-recto-v2.jpg" \
  -F "visibility=sensitive"

# 2) le rattacher — crée la version N+1
curl -i -X POST "$API/providers/me/documents" \
  -H "Authorization: Bearer $PROVIDER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type":"id_card","fileId":"<data.id>"}'
```

**Trois comportements à traduire dans l'UI :**

1. **Un document `approved` ne se remplace pas** —
   `400 Votre justificatif « id_card » est déjà validé`. Masquer l'action
   « Redéposer » sur ces lignes.
2. **Le dépôt crée une version, il n'écrase rien.** L'agent voit l'ancienne à
   côté de la nouvelle. Le libellé doit être « Envoyer un nouveau justificatif »,
   pas « Remplacer ».
3. ⚠️ **Le dépôt en `changes_requested` renvoie le dossier en `pending_review`
   automatiquement** (`submittedAt` mis à jour, `rejectionReason` effacé) —
   [provider-documents-self.service.ts:140-145](apps/api/src/modules/documents/provider-documents-self.service.ts:140).
   → **Rafraîchir `GET /providers/me` après chaque dépôt**, afficher
   « Votre dossier est reparti en vérification », et **ne pas** proposer
   « Re-soumettre » ensuite. Ce bouton n'est utile que lorsque la correction
   portait sur autre chose que les justificatifs.

**Consultation d'un justificatif déjà déposé :** `GET /files/:id/content`
(avec `Bearer`). Le fichier est en visibilité `sensitive` — seul son
propriétaire et le back-office y accèdent.

Il n'existe **pas** de route pour supprimer un justificatif déposé (§7, écart n°9).

---

## 5. Gestion transverse

### 5.1 Format d'enveloppe unifié — **un seul modèle Dart pour toute l'app**

Le contrat est posé à deux endroits et **jamais contourné** :
[api-response.ts](apps/api/src/common/contracts/api-response.ts) pour les succès,
[http-exception.filter.ts](apps/api/src/common/filters/http-exception.filter.ts)
— un filtre **global** (`@Catch()` sans argument) — pour **toutes** les erreurs,
y compris les erreurs non prévues.

```ts
{ success: boolean, message?: string, data?: T, errors?: ApiErrorDetail[], meta?: ApiMeta }
ApiErrorDetail = { field?: string, code: string, message: string }
ApiMeta        = { page?: number, limit?: number, total?: number, correlationId?: string }
```

**Exemples réels capturés :**

```json
// succès non paginé
{ "success": true, "message": "OK", "data": { … } }

// succès paginé
{ "success": true, "message": "OK", "data": [ … ], "meta": { "page": 1, "limit": 20, "total": 1 } }

// erreur d'authentification
{ "success": false, "message": "Bearer token required", "errors": [],
  "meta": { "correlationId": "7c6b34a2-c0ad-43ac-bccc-a0badd80febb" } }

// erreur de validation (ValidationPipe)
{ "success": false, "message": "Adresse email invalide",
  "errors": [
    { "code": "validation_error", "message": "Adresse email invalide" },
    { "code": "validation_error", "message": "Le mot de passe doit contenir au moins 8 caractères, dont une lettre et un chiffre" }
  ],
  "meta": { "correlationId": "92682576-f5fe-41b2-9b3f-7c8d807d90ab" } }

// erreur métier avec `field` (SEUL cas du périmètre : POST /providers/me/submit)
{ "success": false, "message": "Votre dossier n'est pas complet",
  "errors": [ { "field": "documents", "code": "checklist_incomplete",
                "message": "Fournissez tous les justificatifs obligatoires" } ],
  "meta": { "correlationId": "…" } }
```

Trois observations décisives pour l'implémentation :

1. **`message` est toujours présent en cas d'erreur** et est **rédigé en
   français, à destination de l'utilisateur final** dans la quasi-totalité des
   cas métier. Il est **affichable tel quel**, sauf les exceptions signalées dans
   ce document (`Invalid credentials`, `Account is not active`,
   `Bearer token required`, `Invalid access token`, et les messages de
   reprogrammation côté prestataire — §4.5).
2. **`errors[]` du `ValidationPipe` n'a pas de `field`** — vérifié en appel réel.
   Le mapping automatique champ→message est donc impossible (§1.4). `message`
   reprend d'ailleurs le **premier** élément du tableau.
3. **`meta.correlationId` est présent sur toutes les erreurs.** Le **journaliser
   systématiquement** côté client (Sentry / Crashlytics) : c'est la clé qui relie
   un incident utilisateur à la trace serveur.

#### Modèle Dart unique

```dart
// core/api/api_envelope.dart
class ApiEnvelope<T> {
  const ApiEnvelope({
    required this.success, this.message, this.data,
    this.errors = const [], this.meta,
  });

  final bool success;
  final String? message;
  final T? data;
  final List<ApiErrorDetail> errors;
  final ApiMeta? meta;

  factory ApiEnvelope.fromJson(
    Map<String, dynamic> json,
    T Function(Object? raw) parseData,
  ) => ApiEnvelope<T>(
        success: json['success'] as bool? ?? false,
        message: json['message'] as String?,
        data: json.containsKey('data') && json['data'] != null
            ? parseData(json['data'])
            : null,
        errors: (json['errors'] as List?)
                ?.map((e) => ApiErrorDetail.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        meta: json['meta'] == null
            ? null
            : ApiMeta.fromJson(json['meta'] as Map<String, dynamic>),
      );
}

class ApiErrorDetail {
  const ApiErrorDetail({this.field, required this.code, required this.message});
  final String? field;      // renseigné UNIQUEMENT par POST /providers/me/submit
  final String code;        // "validation_error", "checklist_incomplete", "error"
  final String message;

  factory ApiErrorDetail.fromJson(Map<String, dynamic> j) => ApiErrorDetail(
        field: j['field'] as String?,
        code: j['code'] as String? ?? 'error',
        message: j['message'] as String? ?? '',
      );
}

class ApiMeta {
  const ApiMeta({this.page, this.limit, this.total, this.correlationId});
  final int? page, limit, total;
  final String? correlationId;

  bool get hasMore =>
      page != null && limit != null && total != null && page! * limit! < total!;

  factory ApiMeta.fromJson(Map<String, dynamic> j) => ApiMeta(
        page: j['page'] as int?,
        limit: j['limit'] as int?,
        total: j['total'] as int?,
        correlationId: j['correlationId'] as String?,
      );
}
```

#### Exception unique, levée par un intercepteur unique

```dart
// core/api/api_exception.dart
class ApiException implements Exception {
  const ApiException({
    required this.statusCode, required this.message,
    this.errors = const [], this.correlationId,
  });

  final int statusCode;
  final String message;
  final List<ApiErrorDetail> errors;
  final String? correlationId;

  /// Erreur corrigeable par l'utilisateur (formulaire, choix de créneau…).
  bool get isUserFixable => statusCode == 400 || statusCode == 409;
  bool get isAuth        => statusCode == 401;
  bool get isForbidden   => statusCode == 403;
  bool get isNotFound    => statusCode == 404;
  bool get isRateLimited => statusCode == 429;
  bool get isServer      => statusCode >= 500;

  /// Message d'erreur d'un champ de la checklist prestataire.
  String? messageForField(String field) =>
      errors.where((e) => e.field == field).map((e) => e.message).firstOrNull;
}
```

```dart
// core/api/envelope_interceptor.dart — un seul point de conversion
class EnvelopeInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final body = err.response?.data;
    final status = err.response?.statusCode ?? 0;

    if (body is Map<String, dynamic>) {
      final envelope = ApiEnvelope<void>.fromJson(body, (_) {});
      return handler.reject(DioException(
        requestOptions: err.requestOptions,
        response: err.response,
        error: ApiException(
          statusCode: status,
          message: envelope.message ?? _fallback(status),
          errors: envelope.errors,
          correlationId: envelope.meta?.correlationId,
        ),
      ));
    }

    // Pas de corps JSON : coupure réseau, timeout, 502 d'un proxy.
    return handler.reject(DioException(
      requestOptions: err.requestOptions,
      response: err.response,
      error: ApiException(statusCode: status, message: _fallback(status)),
    ));
  }

  String _fallback(int status) => switch (status) {
        0    => 'Connexion impossible. Vérifiez votre réseau.',
        429  => 'Trop de tentatives. Réessayez dans un instant.',
        >= 500 => 'Le service est momentanément indisponible.',
        _    => 'Une erreur est survenue.',
      };
}
```

**Règle d'équipe :** aucun écran, aucun repository ne lit `response.data['data']`
ni ne teste un code HTTP à la main. Tout passe par `ApiEnvelope` et
`ApiException`. Une seule fonction générique côté client HTTP :

```dart
Future<T> getData<T>(String path, T Function(Object?) parse, {Map<String, dynamic>? query}) async {
  final res = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
  return ApiEnvelope<T>.fromJson(res.data!, parse).data as T;
}
```

⚠️ **Trois formes de `data` coexistent** — le `parse` doit être choisi en
conséquence :
- **objet** (`GET /me`, `GET /missions/:id`, `GET /providers/me`…) ;
- **tableau** (`GET /me/addresses`, `GET /me/missions`, `GET /providers/search`…) ;
- **objet contenant un tableau**, avec `meta` de pagination :
  `GET /providers/:id/reviews` → `data.reviews` (§3.5). Seul cas du périmètre.

### 5.2 Retry et idempotence sur les écritures sensibles

#### Politique de rejeu par type de requête

| Type | Rejeu automatique | Justification |
|---|---|---|
| **Lectures `GET`** | ✅ 2 tentatives, backoff 500 ms / 1,5 s, sur erreur réseau et `502/503/504` uniquement | Sans effet de bord. |
| **`POST /missions`** | ✅ mais **uniquement avec `Idempotency-Key`** | Voir ci-dessous. |
| **Écritures idempotentes par construction** (`PUT /providers/me/zones`, `PUT /providers/me/availabilities`, `POST /me/favorites/:id`, `DELETE /me/favorites/:id`, `PATCH /me/notifications/:id/read`, `POST /me/devices`) | ✅ 1 tentative | Le résultat final ne dépend pas du nombre d'appels. |
| **Transitions de mission** (`accept`, `refuse`, `start`, `complete`, `cancel`) | ❌ **jamais** | Un rejeu après succès non reçu renvoie `400 Action impossible depuis le statut « confirmed »`, message incompréhensible. **Rafraîchir le détail** et laisser l'utilisateur décider. |
| **`POST /missions/:id/review`** | ❌ | Un rejeu renvoie `409 Vous avez déjà déposé un avis`. Traiter ce 409 comme un **succès** et afficher l'avis. |
| **`POST /messages/threads/:id/messages`** | ❌ automatique | Créerait des doublons (pas de clé d'idempotence sur cette route). Bulle en état « échec » + bouton « Renvoyer » manuel. |
| **`POST /files/upload`** | ❌ automatique | `FormData` à usage unique (§2.3). Reprise explicite. |
| **`POST /auth/*`** | ❌ | Débits serrés (5–10/minute). Un rejeu déclencherait le `429`. |

**Le seul rejeu automatique d'écriture non idempotente est `POST /missions`**, et
il n'est sûr que grâce à `Idempotency-Key` (§3.6). Sans l'en-tête, la protection
n'existe pas.

#### Séquence exacte de rejeu pour `POST /missions`

```
1. Générer la clé une fois, à l'affichage du récapitulatif.
2. Envoyer avec `Idempotency-Key: <clé>`.
3. Timeout / coupure réseau ?
     → réessayer AVEC LA MÊME CLÉ (2 tentatives max, backoff 1 s puis 3 s)
     → 201 « Réservation créée »          : succès
     → 200 « Réservation déjà enregistrée » : succès — la 1re requête était passée
     → 409 « … déjà en cours de traitement » : attendre 2 s, réessayer (2 fois max),
            puis rafraîchir GET /me/missions — la mission existe probablement
4. 400 métier (créneau, adresse, zone) ?
     → NE PAS réessayer. La clé est libérée côté serveur ; corriger et repartir
       de l'étape 1 avec une NOUVELLE clé (le contenu a changé).
5. 429 ?
     → NE PAS réessayer. Message « limite atteinte », bouton désactivé.
```

Rappel des durées : la clé vit **10 minutes**, plafond **10 réservations/heure**.

#### Cohérence après écriture

Après toute écriture réussie, invalider les providers Riverpod concernés :

| Écriture | À invalider |
|---|---|
| `POST /missions` | `myMissionsProvider`, `unreadCountProvider`, `myThreadsProvider` |
| transitions de mission | `missionDetailProvider(id)`, listes des missions, `unreadCountProvider` |
| `POST /missions/:id/review` | `missionDetailProvider(id)`, `myReviewsProvider` |
| profil prestataire / services / zones / dispos / documents | `providerOverviewProvider` (la **checklist** en dépend) |
| `PATCH /me` | `meProvider` |

### 5.3 Notifications push — cycle de vie du jeton

Le canal `push` est déjà en place côté backend (transport FCM, variables
`FCM_PROJECT_ID` / `FCM_CLIENT_EMAIL` / `FCM_PRIVATE_KEY`), avec désactivation
automatique des jetons refusés par le fournisseur et purge des jetons inactifs
depuis 90 jours.

#### Enregistrement — `POST /me/devices`

Corps : `{ platform, token }`.

| Champ | Règle | Message |
|---|---|---|
| `platform` | **`android`** \| **`ios`** \| **`web`** | `Plateforme acceptée : android, ios, web` |
| `token` | **10 à 512 caractères** | `Jeton d'appareil invalide` |

```bash
curl -i -X POST "$API/me/devices" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"platform":"android","token":"fcm-token-exemple-abcdefghijklmnopqrstuvwxyz0123456789"}'
```

Réponse 200 (**pas 201**), message `Appareil enregistré`,
`data: { id, platform, active, lastSeenAt }`. **Le jeton lui-même n'est jamais
renvoyé** — c'est un secret d'envoi.

**Idempotent** : réappeler avec le même jeton met simplement à jour
(`upsert` sur `token`). **Débit : 30 par jour** → `429`.

⚠️ **Réaffectation entre comptes.** Le jeton FCM identifie une *installation*,
pas un compte. Sur un téléphone prêté, le même jeton peut se présenter avec un
autre compte : le backend **écrase `userId`** pour éviter que l'ancien
propriétaire reçoive les notifications du nouveau
([devices.service.ts:8-17](apps/api/src/modules/notifications/devices.service.ts:8)).
→ L'application **doit** enregistrer le jeton **à chaque connexion**, pas
seulement à la première installation.

#### Désenregistrement — `DELETE /me/devices/:token`

Le jeton passe **dans le chemin d'URL** → l'encoder (`Uri.encodeComponent`).
**Idempotent** : un jeton absent ou appartenant à un autre compte renvoie
`{ unregistered: false }`, jamais d'erreur.

```bash
curl -i -X DELETE "$API/me/devices/fcm-token-exemple-abcdefghijklmnopqrstuvwxyz0123456789" \
  -H "Authorization: Bearer $TOKEN"
```

#### Cycle de vie complet à implémenter

| Moment | Action |
|---|---|
| **Après chaque `POST /auth/login` réussi** | Demander la permission (iOS/Android 13+), lire `FirebaseMessaging.instance.getToken()`, `POST /me/devices`. Mémoriser le jeton localement. |
| **Au démarrage, session restaurée** | Relire le jeton, `POST /me/devices` (idempotent — coût nul, garantit la réaffectation après réinstallation ou changement de compte). |
| **Sur `onTokenRefresh`** | `DELETE` l'ancien jeton mémorisé, puis `POST` le nouveau. |
| **Avant `POST /auth/logout`** | `DELETE /me/devices/:token` — **impérativement avant**, la route exige un `Bearer` valide. |
| **`DELETE /me` (désactivation)** | Rien à faire : le backend désactive **tous** les jetons du compte. Purger la mémoire locale. |

```dart
// core/push/push_service.dart (esquisse)
class PushService {
  Future<void> registerForCurrentSession() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    await _api.post('/me/devices', data: {
      'platform': Platform.isIOS ? 'ios' : 'android',
      'token': token,
    });
    await _local.saveDeviceToken(token);
  }

  Future<void> unregisterBeforeLogout() async {
    final token = await _local.readDeviceToken();
    if (token == null) return;
    try {
      await _api.delete('/me/devices/${Uri.encodeComponent(token)}');
    } on ApiException {
      // best-effort : ne jamais bloquer une déconnexion sur le réseau
    }
    await _local.clearDeviceToken();
  }
}
```

**Refus de la permission :** l'application reste **entièrement fonctionnelle** —
les notifications in-app (`GET /me/notifications`) sont le canal par défaut, le
push n'est qu'un complément. Ne jamais bloquer un parcours sur la permission.
Prévoir en revanche un rappel dans les réglages de l'application.

**Routage au tap :** la charge utile du push transporte le même objet `data` que
la notification in-app (§3.10). Une **seule** fonction de routage sert les deux :

```dart
void handleNotificationData(Map<String, dynamic> data, GoRouter router) {
  switch (data['type'] as String?) {
    case 'chat':       router.push('/threads/${data['threadId']}');            break;
    case 'reschedule': router.push('/missions/${data['missionId']}?tab=reschedule'); break;
    case 'review':     router.push('/missions/${data['missionId']}?tab=review');     break;
    case 'mission':    router.push('/missions/${data['missionId']}');          break;
    default:           router.push('/notifications');
  }
}
```

Prévoir les trois points d'entrée Firebase : `onMessage` (premier plan →
bannière interne + rafraîchissement du badge), `onMessageOpenedApp` (arrière-plan
→ routage), et `getInitialMessage()` (application tuée → routage après le
démarrage du routeur).

**Groupement :** un seul push par fil de discussion et par minute
(`groupKey: thread:<id>`). Au-delà, seule la notification in-app est créée.
L'écran de messagerie ne doit donc **pas** dépendre du push pour être à jour :
rafraîchir aussi au retour au premier plan.

### 5.4 Gestion hors-ligne

#### Périmètre V1 — décision explicite

> **La V1 ne couvre PAS le mode hors-ligne complet.** Il n'y a **ni file
> d'attente d'actions différées, ni synchronisation en arrière-plan, ni écriture
> hors ligne.** Toute action d'écriture exige une connexion active.

Justification, tirée des contraintes réelles du backend :

- **Les écritures sont fortement contextuelles.** Un créneau libre à 9 h ne l'est
  plus à 10 h : rejouer une réservation différée produirait massivement des
  `400 Ce créneau est déjà réservé`. Une file d'attente donnerait l'illusion
  d'une réservation acquise, ce qui est pire que l'échec immédiat.
- **Les transitions dépendent du statut courant.** Un `accept` différé
  échouerait en `400 Action impossible depuis le statut « cancelled »` si le
  client a annulé entre-temps.
- **Le jeton d'accès vit 15 minutes.** Une action différée de plusieurs heures
  impose de toute façon un refresh, donc du réseau.
- **`Idempotency-Key` vit 10 minutes**, ce qui borne la fenêtre de rejeu sûr.

#### Ce qui **est** couvert en V1 : cache de lecture

Un cache **en lecture seule**, avec âge affiché, suffit à rendre l'application
utilisable dans le métro ou en zone blanche.

| Donnée | Cache | Durée de vie | Motif |
|---|---|---|---|
| `GET /me` | ✅ persistant | jusqu'à invalidation | Pilote le routage au démarrage : sans lui, l'application ne sait pas quel espace ouvrir hors ligne. |
| `GET /categories` | ✅ persistant | 24 h | Quasi statique. |
| `GET /zones` | ✅ persistant | 24 h | Quasi statique. |
| `GET /me/addresses` | ✅ persistant | jusqu'à invalidation | Peu volumineux, très consulté. |
| `GET /me/missions`, `GET /providers/me/missions` | ✅ persistant (1re page) | affiché avec « Mis à jour il y a N min » | Consultation de l'agenda du jour hors ligne. |
| `GET /missions/:id` | ✅ persistant | idem | Adresse, instructions, horaire — utiles sur place, réseau faible. |
| `GET /messages/threads/:id/messages` | ✅ persistant | idem | Relire un fil hors ligne. |
| `GET /providers/search`, `/providers/:id/public` | ⚠️ mémoire seulement | session | Résultats fortement dépendants de la position et de l'heure : les servir depuis le disque afficherait des créneaux périmés. |
| `GET /me/notifications`, `unread-count` | ⚠️ mémoire seulement | session | — |

**Implémentation recommandée :** Riverpod + une couche de persistance simple
(`hive` ou `drift`), avec le motif « **stale-while-revalidate** » — servir le
cache immédiatement, lancer la requête, remplacer à l'arrivée.

**Règles d'interface non négociables :**

1. **Bannière hors ligne persistante** en haut de l'écran
   (`connectivity_plus`), avec le texte « Mode hors ligne — données du
   <horodatage> ».
2. **Tous les boutons d'écriture sont désactivés hors ligne**, avec un
   `Tooltip` / `SnackBar` explicatif. Ne **jamais** accepter une action pour la
   rejouer plus tard.
3. **Reprise à la reconnexion** : invalider les providers de la page courante.
4. **Aucune donnée `sensitive` en cache disque** : ne pas mettre en cache le
   contenu de `GET /files/:id/content` pour les justificatifs. Les avatars et le
   portfolio (visibilité `public`) peuvent l'être.

#### Ce qui pourrait être ajouté en V2

À évaluer, hors périmètre V1 : brouillon de message hors ligne avec envoi manuel
à la reconnexion (le seul cas où une file serait défendable, car un message
n'a pas de contrainte de créneau), et pré-chargement de l'agenda de la journée
au réveil de l'application.

---

## 6. Annexe — Catalogue complet des endpoints consommés

**Source :** document OpenAPI live (`GET /api/docs-json`) d'un serveur démarré le
29 juillet 2026, **mis à jour le même jour** après une session de correction des
écarts détectés — **158 opérations au total**, dont **68 sous `/admin/*`** et
**90 hors `/admin/*`** (+3 par rapport à la version initiale de ce document :
`GET /settings/public`, `GET /me/threads/unread-count`,
`GET /providers/me/availabilities` — voir §7). Le tableau ci-dessous reprend
ces **90 opérations, sans exception**. La colonne « Auth » reflète la présence
effective de `security` dans le document généré.

Tous les chemins sont préfixés par `/api/v1`.

| # | Méthode | Chemin | Écran(s) | Auth | Pagination |
|---|---|---|---|---|---|
| **Authentification (§2)** |
| 1 | POST | `/auth/register` | C3 Inscription | non | — |
| 2 | POST | `/auth/otp/send` | C4 Vérification OTP ; §3.1 changement email/tél ; connexion par téléphone (§2.3) | non | — |
| 3 | POST | `/auth/otp/verify` | C4 Vérification OTP ; **connexion par téléphone si `purpose=login`** (§2.3) | non | — |
| 4 | POST | `/auth/login` | Connexion ; C5 | non | — |
| 5 | POST | `/auth/refresh` | Intercepteur dio (§2.3) | non | — |
| 6 | POST | `/auth/logout` | Déconnexion | non\* | — |
| 7 | POST | `/auth/forgot-password` | Mot de passe oublié | non | — |
| 8 | POST | `/auth/reset-password` | Réinitialisation | non | — |
| **Profil et compte (§3.1, §2.4)** |
| 9 | GET | `/me` | Démarrage, routage, Profil | **oui** | — |
| 10 | PATCH | `/me` | Profil — édition | **oui** | — |
| 11 | POST | `/me/password` | Changer mon mot de passe | **oui** | — |
| 12 | DELETE | `/me` | Désactiver mon compte | **oui** | — |
| **Adresses (§3.2)** |
| 13 | GET | `/me/addresses` | Carnet d'adresses ; sélecteur de réservation | **oui** | non |
| 14 | POST | `/me/addresses` | Ajouter une adresse | **oui** | — |
| 15 | PATCH | `/me/addresses/{id}` | Modifier une adresse | **oui** | — |
| 16 | DELETE | `/me/addresses/{id}` | Supprimer une adresse | **oui** | — |
| 17 | POST | `/me/addresses/{id}/default` | Définir par défaut | **oui** | — |
| **Favoris (§3.3)** |
| 18 | GET | `/me/favorites` | Mes favoris | **oui** | non |
| 19 | POST | `/me/favorites/{providerId}` | Fiche prestataire, résultats de recherche | **oui** | — |
| 20 | DELETE | `/me/favorites/{providerId}` | Mes favoris, fiche prestataire | **oui** | — |
| **Réglages (§8)** |
| 21 | GET | `/settings/public` | Aucun écran dédié — pilote des seuils affichés dans §3.6, §3.7, §3.9, §4.4 | non | non |
| **Catalogue et recherche (§3.4, §3.5)** |
| 22 | GET | `/categories` | Filtres de recherche ; P3 déclaration de service | non | non |
| 23 | GET | `/zones` | P5 zones ; « Où intervenons-nous ? » | non | non |
| 24 | GET | `/zones/nearby` | Sélection de zone par position | non | non |
| 25 | GET | `/providers/search` | **Accueil / recherche** | non | **oui** |
| 26 | GET | `/providers/{id}/public` | **Fiche prestataire** | non | — |
| 27 | GET | `/providers/{id}/service-packs` | *(redondant avec la fiche publique — non consommé)* | non | non |
| 28 | GET | `/providers/{id}/availabilities` | Fiche publique (agenda affiché) ; ne sert plus à relire son PROPRE agenda depuis l'ajout de la route n°79 | non | non |
| 29 | GET | `/providers/{id}/unavailabilities` | Relecture de **mes** absences (§4.2) | non | non |
| 30 | GET | `/providers/{id}/reviews` | Fiche prestataire — tous les avis | non | **oui** (forme alignée sur l'enveloppe standard depuis la correction de l'écart n°15 : `data` est un tableau) |
| **Réservation et missions (§3.6, §3.7, §4.4)** |
| 31 | POST | `/missions` | Confirmation de réservation | **oui** | — |
| 32 | GET | `/me/missions` | Mes missions (client) | **oui** | **oui** |
| 33 | GET | `/providers/me/missions` | Tableau de bord et planning (prestataire) | **oui** | **oui** |
| 34 | GET | `/missions/{id}` | Détail de mission (2 rôles) | **oui** | — |
| 35 | GET | `/missions/{id}/history` | Frise chronologique | **oui** | non |
| 36 | POST | `/missions/{id}/accept` | Détail — prestataire | **oui** | — |
| 37 | POST | `/missions/{id}/refuse` | Détail — prestataire | **oui** | — |
| 38 | POST | `/missions/{id}/start` | Détail — prestataire | **oui** | — |
| 39 | POST | `/missions/{id}/complete` | Détail — prestataire | **oui** | — |
| 40 | POST | `/missions/{id}/cancel` | Détail — **2 rôles** | **oui** | — |
| **Reprogrammation (§3.7, §4.5)** |
| 41 | GET | `/missions/{id}/reschedules` | Détail — onglet Reports | **oui** | non |
| 42 | POST | `/missions/{id}/reschedule` | Proposer un report — 2 rôles | **oui** | — |
| 43 | POST | `/missions/{id}/reschedule/{rid}/accept` | Répondre à un report — 2 rôles | **oui** | — |
| 44 | POST | `/missions/{id}/reschedule/{rid}/reject` | Répondre à un report — 2 rôles | **oui** | — |
| **Avis (§3.9)** |
| 45 | POST | `/missions/{id}/review` | Dépôt d'avis (**client seul**) | **oui** | — |
| 46 | GET | `/me/reviews` | Mes avis | **oui** | **oui** |
| 47 | POST | `/reviews/{id}/report` | Signaler un avis | **oui** | — |
| **Messagerie (§3.11)** |
| 48 | GET | `/me/threads` | Onglet Messagerie | **oui** | **oui** |
| 49 | GET | `/me/threads/unread-count` | Badge de l'onglet Messagerie | **oui** | — |
| 50 | GET | `/missions/{id}/thread` | Détail de mission → conversation | **oui** | — |
| 51 | GET | `/messages/threads/{id}/messages` | Conversation | **oui** | **oui** (paginée depuis la correction de l'écart n°12 — voir la note « ancien vs nouveau format » en §3.11) |
| 52 | POST | `/messages/threads/{id}/messages` | Conversation — envoi | **oui** | — |
| 53 | PATCH | `/messages/threads/{id}/read` | Conversation — ouverture | **oui** | — |
| **Notifications et appareils (§3.10, §5.3)** |
| 54 | GET | `/me/notifications` | Centre de notifications | **oui** | **oui** |
| 55 | GET | `/me/notifications/unread-count` | Badge (accueil, onglets) | **oui** | — |
| 56 | PATCH | `/me/notifications/{id}/read` | Centre de notifications | **oui** | — |
| 57 | POST | `/me/notifications/read-all` | Centre de notifications | **oui** | — |
| 58 | GET | `/me/devices` | Réglages — appareils connectés | **oui** | non |
| 59 | POST | `/me/devices` | Démarrage, connexion, `onTokenRefresh` | **oui** | — |
| 60 | DELETE | `/me/devices/{token}` | Avant déconnexion, `onTokenRefresh` | **oui** | — |
| **Fichiers (§2.2 P7, §3.11, §4.2, §4.3)** |
| 61 | POST | `/files/upload` | Justificatifs, avatar, portfolio, pièces jointes | **oui** | — |
| 62 | GET | `/files/{id}` | Métadonnées (taille, type) | **oui** | — |
| 63 | GET | `/files/{id}/content` | Affichage image / aperçu justificatif | **non si `visibility=public`, oui sinon** (écart n°5 clos) | — |
| 64 | DELETE | `/files/{id}` | Retirer un fichier envoyé par erreur | **oui** | — |
| **Espace prestataire — profil et dossier (§2.2, §4.2)** |
| 65 | POST | `/providers/me` | P2 Création du profil prestataire | **oui** | — |
| 66 | GET | `/providers/me` | P8 Checklist ; P9 Suivi ; Profil prestataire | **oui** | — |
| 67 | PATCH | `/providers/me` | Profil prestataire ; interrupteur de disponibilité | **oui** | — |
| 68 | POST | `/providers/me/submit` | P8 Soumettre le dossier — désormais accessible aussi depuis `rejected` si `resubmissionBlocked` est faux (écart n°8 clos) | **oui** | — |
| **Espace prestataire — offre (§2.2 P3/P4, §4.2)** |
| 69 | GET | `/providers/me/services` | Mes prestations | **oui** | non |
| 70 | POST | `/providers/me/services` | P3 Déclarer un service | **oui** | — |
| 71 | PATCH | `/providers/me/services/{id}` | Modifier / désactiver un service | **oui** | — |
| 72 | POST | `/providers/me/service-packs` | P4 Créer une formule | **oui** | — |
| 73 | PATCH | `/providers/me/service-packs/{id}` | Modifier / désactiver une formule | **oui** | — |
| 74 | GET | `/providers/me/service-packs/{packId}/options` | Options d'une formule | **oui** | non |
| 75 | POST | `/providers/me/service-packs/{packId}/options` | P4b Ajouter une option | **oui** | — |
| 76 | PATCH | `/providers/me/service-pack-options/{id}` | Modifier / désactiver une option | **oui** | — |
| **Espace prestataire — zones et agenda (§2.2 P5/P6, §4.2)** |
| 77 | GET | `/providers/me/zones` | Mes zones | **oui** | non |
| 78 | PUT | `/providers/me/zones` | P5 Zones d'intervention | **oui** | — |
| 79 | GET | `/providers/me/availabilities` | Relecture de mon agenda hebdomadaire (§4.2) — route ajoutée, écart n°11 clos | **oui** | non |
| 80 | PUT | `/providers/me/availabilities` | P6 Disponibilités hebdomadaires | **oui** | — |
| 81 | POST | `/providers/me/unavailabilities` | Déclarer une absence | **oui** | — |
| 82 | DELETE | `/providers/me/unavailabilities/{id}` | Supprimer une absence | **oui** | — |
| **Espace prestataire — justificatifs (§2.2 P7, §4.6)** |
| 83 | GET | `/providers/me/documents` | P7 / Documents de vérification | **oui** | — |
| 84 | POST | `/providers/me/documents` | P7 Déposer / redéposer un justificatif | **oui** | — |
| **Espace prestataire — portfolio (§4.3)** |
| 85 | GET | `/providers/me/portfolio` | Mon portfolio | **oui** | non |
| 86 | POST | `/providers/me/portfolio` | Ajouter une réalisation | **oui** | — |
| 87 | PATCH | `/providers/me/portfolio/{id}` | Modifier une réalisation | **oui** | — |
| 88 | DELETE | `/providers/me/portfolio/{id}` | Retirer une réalisation | **oui** | — |
| **Litiges (§3.8)** |
| 89 | POST | `/disputes` | Ouvrir un litige — 2 rôles | **oui** | — |
| 90 | GET | `/disputes/{id}` | Suivi du litige — 2 rôles | **oui** | — |

\* **`POST /auth/logout`** est déclaré `@Public()` (le décorateur porte sur tout
le contrôleur `auth`), donc sans `security` dans OpenAPI. Il **lit néanmoins**
l'en-tête `Authorization` s'il est fourni. **Envoyer le `Bearer` et le
`refreshToken`** pour que la bonne session soit fermée (§2.4).

**Vérification du décompte :** les 90 lignes numérotées ci-dessus couvrent
l'intégralité des opérations non-`/admin/*` du document OpenAPI, régénéré et
comparé exhaustivement au code après la session de correction des écarts.
Une seule est listée sans être consommée par l'application (**n°27**,
`GET /providers/{id}/service-packs`, redondante avec la fiche publique) — elle
figure dans le tableau par exhaustivité.

**Routes non consommées par le mobile :** les **68 opérations sous `/admin/*`**
(back-office : validation des prestataires, modération, exports, réglages,
rôles, audit, supervision des missions et des litiges) — **inchangées** par la
session de correction : aucun écart traité ne portait sur le périmètre admin.

### Endpoints par rôle — synthèse qualitative

| Portée | Routes concernées |
|---|---|
| **Client seul** | `POST /missions`, `GET /me/missions`, `POST /missions/:id/review`, `/me/favorites/*`, `/me/addresses/*` (le carnet ne sert qu'à la réservation) |
| **Prestataire seul** | tout `/providers/me/*` (y compris désormais `GET /providers/me/availabilities`), plus `POST /missions/:id/accept`, `/refuse`, `/start`, `/complete` |
| **Les deux rôles** | `/auth/*` (y compris la connexion par téléphone), `GET`/`PATCH`/`DELETE /me`, `POST /me/password`, `/me/notifications/*`, `/me/devices/*`, `/me/threads/*`, `/messages/*`, `GET /missions/:id` et `/history`, `POST /missions/:id/cancel`, toutes les routes de reprogrammation, `/disputes/*`, `/files/*`, la recherche publique, et `/settings/public` |

Cette répartition explique le découpage de dossiers du §1.2 : le tiers « les deux
rôles » constitue le socle partagé (`core/` + `features/auth` +
`features/profile` + messagerie + notifications).

---

## 7. Écarts détectés — endpoints manquants ou comportements à arbitrer

Chaque écart ci-dessous a été **constaté dans le code ou par appel réel**, et
concerne un besoin d'écran mobile identifié dans ce document. Aucun n'a été
comblé par une invention d'API.

**Mise à jour du 29 juillet 2026 (session de correction) :** 12 des 16 écarts
sont désormais **CLOS**, 1 est **VOLONTAIREMENT NON CORRIGÉ** par décision
produit explicite (n°14, devise), 2 restent des limitations de conception
assumées avec un contournement jugé suffisant (n°9 partiellement, n°10), et
1 reste **À REPORTER** faute d'une information qui ne dépend pas du code
(n°3, nom de domaine). Le statut de chacun est indiqué entre crochets dans
son titre ; les routes ajoutées ou corrigées ont été vérifiées par un test
automatisé et par un appel réel avant la clôture.

---

**Écart n°1 — `hasClientProfile` est inexploitable : aucune route mobile ne crée
de `ClientProfile`.** **[CLOS]**

Constat d'origine : `GET /me` expose `hasClientProfile`, mais une recherche
exhaustive (`grep clientProfile`) montrait que seules `clients.service.ts` et
`users.service.ts` — **routes d'administration** — créaient la ligne, par
`upsert`. Ni `POST /auth/register` ni aucune route `/me` ne le faisait.
**Vérifié en appel réel à l'époque :** `hasClientProfile == false` pour
`client.demo@prestgo.test` **et** pour `provider.ready@prestgo.test`.

**Correction appliquée :** `POST /auth/register` crée désormais le
`ClientProfile` **dans la même écriture** que le compte (nested create
Prisma). Tout compte inscrit via cette route a `hasClientProfile: true` dès son
activation. Vérifié par un test de bout en bout (inscription → OTP →
connexion → `GET /me`) et par appel réel.

⚠️ **Point d'attention qui subsiste, pas un écart :** les comptes créés
**avant** cette correction (tous les comptes de démonstration du seed compris)
gardent `hasClientProfile: false` — rien ne les rattrape rétroactivement.
**Règle applicable, voir §1.3 : `hasClientProfile` reste ignoré pour
l'aiguillage** ; c'est `status == "active"` qui conditionne l'accès à l'espace
client, pour rester valable sur les comptes historiques comme sur les
nouveaux.

---

**Écart n°2 — connexion par téléphone impossible, alors que l'inscription par
téléphone seul est autorisée.** **[CLOS]**

Constat d'origine : `RegisterBodyDto` acceptait un compte avec `phone` seul et
sans `email`. Mais `LoginBodyDto.email` est décoré `@IsEmail()` et
`AuthService.login` cherchait par `where: { email }` : un compte créé avec un
téléphone seul ne pouvait jamais se connecter. Le motif OTP `login` existait
pourtant dans `OTP_PURPOSES` — l'intention était là, la route non.

**Correction appliquée, décision produit :** implémentée via l'OTP existant
(pas en ajoutant le téléphone à `LoginBodyDto`). Voir §2.3 pour le parcours
complet : `POST /auth/otp/send` avec `purpose: "login"`, puis
`POST /auth/otp/verify` avec le même `purpose` renvoie directement un couple
de jetons — la forme exacte de `POST /auth/login` — sans mot de passe. Un code
valide sans compte actif correspondant renvoie `401 Account is not active`
(ce n'est pas une fuite : le code déjà vérifié prouve la maîtrise du
téléphone). Testé de bout en bout par appel réel et par suite automatisée.

---

**Écart n°3 — pas de lien profond pour la réinitialisation de mot de passe.**
**[À REPORTER — décision produit en attente]**

Constat, inchangé : `forgotPassword` envoie un email contenant le jeton **en
clair dans le texte**, sans URL construite. Aucun `APP_DEEP_LINK_BASE` ni
équivalent dans la configuration.

**Pourquoi ce n'est pas corrigé :** construire un lien profond exige un nom de
domaine et une configuration App Links (Android, fichier
`assetlinks.json`) / Universal Links (iOS, fichier
`apple-app-site-association`) **arrêtés**, ce qui n'est pas encore le cas au
29 juillet 2026. Coder une URL provisoire serait pire que le contournement
actuel : un lien qui pointe vers un domaine qui changera cassera silencieusement
au premier redéploiement.

Contournement actuel, INCHANGÉ (§2.3) : écran de **saisie / collage manuel** du
jeton (64 caractères hexadécimaux). Prévoir un champ large et un bouton
« Coller ».

**Ce qu'il faudra faire dès que le domaine sera choisi** (à charge du backend,
consigné ici pour ne pas le perdre) :
1. Construire l'URL envoyée dans l'email de `forgotPassword` sous la forme
   `https://<domaine-choisi>/reset?token=<token>` (le jeton hexadécimal actuel,
   inchangé).
2. Déclarer `assetlinks.json` / `apple-app-site-association` sur ce domaine,
   pointant vers l'application.
3. Câbler la route `go_router` correspondante côté Flutter pour intercepter ce
   lien et pré-remplir l'écran de réinitialisation avec le `token` extrait de
   l'URL — l'écran de saisie manuelle resterait un repli valable (lien non
   cliqué, copié à la main) plutôt que d'être retiré.

---

**Écart n°4 — pas de compteur global de messages non lus.** **[CLOS]**

Constat d'origine : `GET /me/notifications/unread-count` existait pour les
notifications ; il n'y avait pas d'équivalent pour la messagerie. Le seul
compteur était `unreadCount` **par fil**, dans `GET /me/threads`.

**Correction appliquée :** `GET /me/threads/unread-count` existe désormais, sur
le modèle exact de celui des notifications — `{ unread: number }`, compteur
global tous fils confondus, excluant mes propres messages. Vérifié par test
automatisé (coïncide exactement avec la somme des `unreadCount` par fil) et par
appel réel. Voir §3.11 et §4.1.

---

**Écart n°5 — les avatars ne sont pas affichables sur l'accueil non connecté.**
**[CLOS]**

Constat d'origine : `GET /providers/search` et `GET /providers/:id/public` sont
**publics** et renvoient `avatarFileId`. Mais `GET /files/:id/content` était
**protégée par `Bearer`** — la politique d'accès `canAccessFile` autorisait
bien la visibilité `public`, mais la garde d'authentification s'appliquait
**avant** elle.

**Correction appliquée :** `GET /files/:id/content` est désormais accessible
**sans jeton** pour un fichier `public` (avatar, portfolio) ; un fichier
`restricted`/`sensitive` reste refusé en 403, avec ou sans jeton — la politique
d'accès reste seule juge, seule la garde en amont a été ouverte. Un jeton
invalide ou expiré est traité comme anonyme (pas de 401), pour ne pas casser
l'affichage d'un avatar en cours de défilement. `GET /files/:id` (métadonnées)
reste protégée. Vérifié par test automatisé et par appel réel. Voir §3.4,
§3.11.

---

**Écart n°6 — les réglages métier ne sont lisibles par aucune route mobile.**
**[CLOS]**

Constat d'origine : six valeurs pilotant des règles visibles par l'utilisateur
n'étaient lisibles que par `/admin/settings` :

| Réglage | Défaut | Où l'utilisateur le ressent |
|---|---|---|
| `mission.min_lead_time_minutes` | 60 | Délai minimum de réservation (§3.6) |
| `mission.cancellation_notice_hours` | 6 | Seuil d'annulation tardive (§3.7) |
| `mission.start_window_minutes` | 120 | Fenêtre de démarrage (§4.4) |
| `mission.pending_expiry_hours` | 24 | Expiration d'une demande (§4.4) |
| `mission.auto_close_days` | 7 | Clôture automatique |
| `reviews.window_days` | 14 | Fenêtre de dépôt d'avis (§3.9) |

**Correction appliquée :** `GET /settings/public` (route publique, sans jeton)
expose exactement ces six clés — une liste FERMÉE, pas un miroir de la table
complète des réglages. Une modification faite dans le back-office ressort
immédiatement (le cache serveur est invalidé à l'écriture). Vérifié par test
automatisé et par appel réel. Voir §8 pour la recommandation d'usage côté
Flutter (appel au démarrage, cache, constantes en repli).

---

**Écart n°7 — `status` n'accepte qu'une seule valeur sur les listes de
missions.** **[CLOS]**

Constat d'origine : `MyMissionsQueryDto.status` était un
`@IsEnum(MissionStatus)` scalaire. Un onglet « Terminées » couvrant
`completed` **et** `closed` ne pouvait pas s'exprimer en un appel.

**Correction appliquée :** `?status=completed,closed` (liste séparée par des
virgules) construit un filtre `IN` et renvoie l'union exacte, en un seul
appel, avec `meta.total` qui reflète cette union. La forme scalaire
(`?status=confirmed`) continue de fonctionner à l'identique. Une liste
contenant un seul statut inconnu est refusée en bloc, comme avant pour une
valeur unique invalide. S'applique à `GET /me/missions` **et**
`GET /providers/me/missions`. Vérifié par test automatisé (comparaison contre
l'union de deux appels simples) et par appel réel.

---

**Écart n°8 — un dossier `rejected` ne peut pas être re-soumis, alors que l'UI
suggère le contraire.** **[CLOS]**

Constat d'origine : `POST /providers/me/submit` n'autorisait que
`profile_incomplete` et `changes_requested`. Un dossier `rejected` avec
`resubmissionBlocked == false` renvoyait `400 … il n'y a rien à soumettre` —
alors que `resubmissionBlocked: false` laissait entendre le contraire.

**Correction appliquée, décision produit :** `rejected` rejoint
`profile_incomplete` et `changes_requested` dans les statuts soumissibles.
C'est fidèle à la garde déjà existante, pas une nouvelle règle : seul
`resubmissionBlocked` doit fermer la porte, jamais le statut `rejected`
lui-même. Testé de bout en bout : dossier complet rejeté avec
`resubmissionBlocked: false` → `canSubmit: true`, re-soumission acceptée
(retour à `pending_review`) ; même dossier avec `resubmissionBlocked: true` →
`canSubmit: false`, re-soumission refusée (403, message inchangé). Voir §2.2 P9.

---

**Écart n°9 — pas de suppression pour plusieurs ressources créées par
l'utilisateur.** **[VOLONTAIRE / PARTIELLEMENT CLOS]**

| Ressource | Suppression | Statut |
|---|---|---|
| Service prestataire | ❌ | Limitation assumée — `PATCH … { active: false }` |
| Formule | ❌ | Limitation assumée — `PATCH … { active: false }` |
| Option de formule | ❌ | Limitation assumée — `PATCH … { active: false }` |
| Justificatif déposé | ❌ | Limitation assumée — redéposer une nouvelle version |
| Avis déposé | ❌ | **Décision produit confirmée : NE PAS ouvrir de route de modification** |
| Notification | ❌ | Limitation assumée — marquage lu seulement |

**Décision produit sur la modification d'un avis (partie la plus concrète de
cet écart) : NON, aucune route n'est ajoutée.** Vérification technique faite en
conséquence : **aucune route ne supprime jamais réellement un avis**, ni côté
prestataire ni côté back-office — `PATCH /admin/reviews/:id/status` change
seulement le `status` (`hidden`/`rejected`), il ne retire jamais la ligne. La
question « la contrainte unique `(missionId, authorId)` empêcherait-elle un
redépôt après une suppression admin » est donc **sans objet** : ce chemin
n'existe pas dans le code, il n'y a rien à débloquer.

Pour le reste (services, formules, options, justificatifs, notifications) :
limitation de conception assumée, contournement déjà suffisant. Le vocabulaire
de l'interface doit dire « Désactiver », jamais « Supprimer », et prévenir
l'effet de bord (§4.2 : désactiver toutes ses formules fait disparaître le
prestataire de la recherche).

---

**Écart n°10 — pas d'endpoint d'agrégation pour le tableau de bord
prestataire.** **[VOLONTAIRE — non traité cette session]**

Aucune décision transmise sur ce point ; reste une limitation de conception
assumée, avec un contournement jugé suffisant pour la V1.

Contournement (§4.1) : 3 à 4 appels parallèles au lieu d'un. Coût acceptable en
V1, mais c'est l'écran ouvert le plus souvent par un prestataire — le premier
candidat à l'optimisation si la latence se dégrade en usage réel.

Demande backend, si ce point est rouvert : `GET /providers/me/dashboard`
renvoyant `{ pendingCount, todayMissions[], unreadNotifications,
unreadMessages }`.

---

**Écart n°11 — asymétrie de nommage sur la lecture de l'agenda prestataire.**
**[CLOS]**

Constat d'origine : l'écriture se faisait sur
`PUT /providers/me/availabilities`, mais il n'existait pas de
`GET /providers/me/availabilities`. La relecture passait par la route
**publique** `GET /providers/:id/availabilities` avec son propre `providerId`.

**Correction appliquée :** `GET /providers/me/availabilities` existe
désormais, sur le modèle exact de `GET /providers/me/zones` — miroir EXACT de
ce que le `PUT` accepte (contrairement à ce qu'affirmait la première version de
ce document, la route publique ne filtrait déjà pas sur `active` : le seul
écart réel était bien le nommage). Vérifié par test automatisé et par appel
réel. Voir §4.2.

---

**Écart n°12 — pas de temps réel sur la messagerie.** **[PARTIELLEMENT CLOS]**

Constat d'origine, en deux volets : (a) aucun WebSocket, aucun SSE ; (b)
`GET /messages/threads/:id/messages` n'était en outre **pas paginée** — elle
renvoyait l'intégralité du fil.

**Volet (b), pagination — CLOS, décision produit :** corrigé maintenant, avant
que Flutter n'attaque ce module. Voir §3.11 pour le détail complet
« ancien format / nouveau format » — **c'est un changement de contrat** :
`data` était un tableau simple sans `meta`, c'est désormais une PAGE avec
`meta: { page, limit, total }`, sur le même mécanisme `page`/`limit`/`sort`
que toute autre liste de l'API (pas un schéma propre à la messagerie, pas de
curseur `?before=<id>`). Tri par défaut inchangé : `createdAt` croissant.

**Volet (a), temps réel — reste un écart, non traité cette session.** Aucun
WebSocket ni SSE n'existe. Contournement inchangé (§3.11) : chargement à
l'ouverture, pull-to-refresh, rafraîchissement déclenché par le push
`chat.message`. **Pas de polling** malgré la pagination : ce serait now
possible sans rapatrier tout le fil, mais reste déconseillé — le push fait
déjà ce travail pour un coût réseau bien moindre.

---

**Écart n°13 — `errors[]` sans `field` sur les erreurs de validation.**
**[CLOS]**

Constat d'origine, vérifié en appel réel (§5.1) : le `ValidationPipe`
produisait des entrées `{ code: "validation_error", message }` sans `field`.
Seul `POST /providers/me/submit` renseignait `field`.

**Correction appliquée :** l'`exceptionFactory` du `ValidationPipe` global
reconstruit désormais le chemin complet du champ fautif dans `field`, y
compris pour un élément d'un tableau imbriqué (`slots.1.startTime`, pas
seulement `startTime`). **Le filtre d'exception global n'a nécessité AUCUNE
modification** : il lisait déjà `field` dès que le corps portait un tableau
`errors` — confirmé dans le code avant de coder quoi que ce soit. Testé sur
`/auth/register`, `/me/addresses`, `/missions` et le cas imbriqué de
`/providers/me/availabilities`. Le message de tête (`message`) reste,
inchangé, le premier message de la liste. Voir §1.4, §5.1.

---

**Écart n°14 — la devise n'est portée par aucun champ d'API.**
**[VOLONTAIRE — décision produit confirmée : ne rien coder]**

Constat, inchangé : `price`, `quotedAmount` et `startingPrice` sont des nombres
nus, sur 9 champs répartis dans 6 DTO alimentés par 7 services.

**Décision produit confirmée :** ne pas ajouter de champ `currency`. Un ajout
de ce type serait bon marché et non cassant techniquement, mais un
`currency: "XOF"` constant ne préparerait rien de réel pour une expansion
multi-devise hypothétique et non planifiée — le vrai travail (montants en
plus petite unité, taux, devise par prestataire) resterait entier, et ce champ
donnerait seulement l'illusion qu'il est amorcé.

Contournement, inchangé côté application : constante `XOF`, formateur unique
(`intl`, locale `fr_CI`), centralisé pour faciliter une évolution future si la
plateforme sort un jour de la zone franc.

---

**Écart n°15 — `GET /providers/:id/reviews` a une forme de `data` atypique.**
**[CLOS]**

Constat d'origine, vérifié en appel réel (§3.5) : `data` était un **objet**
`{ averageRating, totalReviews, reviews[] }` alors que `meta` portait une
pagination — la seule route paginée du périmètre dont `data` n'était pas un
tableau.

**Correction appliquée :** `data` est désormais un tableau des avis, la
pagination reste dans `meta: { page, limit, total }` — le même modèle que
toute autre liste. Les deux agrégats retirés faisaient doublon, vérification
faite dans le code : `totalReviews` valait exactement `meta.total` (même
clause `where`), et `averageRating` refaisait le calcul de
`provider_profiles.score` (même agrégat que `ProviderRatingService.recompute`),
déjà exposé par `GET /providers/:id/public` avec `ratingDistribution` — c'est
l'écran d'où l'on ouvre cette liste. **Changement de forme de réponse** —
aucun développement Flutter n'avait commencé au moment de la correction, donc
aucun risque de casse réelle, mais à savoir si ce document a déjà circulé.
Le DTO de réponse Swagger manquant (écart n°16) a été ajouté dans la foulée.

---

**Écart n°16 — routes sans DTO de réponse Swagger.** **[CLOS]**

Constat d'origine : `POST /disputes`, `GET /disputes/:id`, `GET /categories`,
`GET /zones`, `GET /zones/nearby`, `GET /providers/:id/service-packs`,
`GET /providers/:id/availabilities`, `GET /providers/:id/unavailabilities`,
`GET /providers/:id/reviews`, et les trois routes `/files/*` ne déclaraient
aucun `@ApiEnvelopeResponse`. Leur forme de réponse n'était pas
contractualisée.

**Correction appliquée, dans l'ordre de priorité prévu :** `/disputes/*`
d'abord (c'était la route dont ce document disait que « la forme n'a pas été
capturée, à établir au moment du développement » — ce n'est plus le cas),
puis le catalogue public, puis les routes provider publiques, puis `/files/*`.
Chaque DTO reflète ce que le service renvoie RÉELLEMENT (relu ligne à ligne
dans le code, rien de réinventé) : `/providers/:id/service-packs` aplatit sa
relation en `serviceId`/`serviceTitle`/`serviceType`, `/zones` n'expose pas
`active` (elle ne liste que l'actif), `DisputeMessage.internalOnly` est
toujours `false` sur la route des parties. Un test verrouille désormais le jeu
exact de clés de chacune de ces routes. Voir §6 pour le tableau à jour.

---

## 8. Récapitulatif des constantes à figer côté Flutter

Valeurs vérifiées dans le code, à centraliser dans un seul fichier
(`core/constants.dart`) plutôt que dispersées.

✅ **Écart n°6 clos pour le bloc « Règles métier » ci-dessous** :
`GET /settings/public` (route publique, sans jeton) expose désormais ces six
valeurs en direct — voir §3.6/§3.7/§3.9/§4.4 pour le détail de chacune.
**Recommandation :** appeler cette route **une fois au démarrage**, mettre le
résultat en cache mémoire (`ref.read(publicSettingsProvider)` côté Riverpod),
et **garder les constantes ci-dessous comme valeur de repli** si l'appel
échoue (hors ligne, cache froid) — jamais comme source de vérité une fois la
route jointe. C'est le même principe que `expiresInMinutes` renvoyé par
`POST /auth/otp/send` (§2.1) : une valeur lue au bon moment prime toujours sur
une constante figée à la compilation.

```dart
// Authentification
const kAccessTokenTtl        = Duration(minutes: 15);
const kRefreshTokenTtl       = Duration(days: 7);
const kOtpLength             = 6;
const kOtpTtl                = Duration(minutes: 10);   // confirmé par l'API
const kOtpMaxAttempts        = 5;
const kResetTokenTtl         = Duration(minutes: 30);
const kPasswordMinLength     = 8;
const kPasswordMaxLength     = 128;
final  kPasswordPattern      = RegExp(r'^(?=.*[A-Za-z])(?=.*\d).+$');
final  kPhonePattern         = RegExp(r'^\+?[0-9\s-]{8,20}$');

// Plafonds de saisie
const kMaxAddresses          = 10;
const kMaxProviderZones      = 15;
const kMaxPortfolioItems     = 20;
const kMaxWeeklySlots        = 50;
const kMaxMissionOptions     = 10;
const kMaxMessageAttachments = 3;
const kMaxMessageLength      = 4000;
const kMaxInstructionsLength = 500;
const kMaxUploadBytes        = 10 * 1024 * 1024;
const kAllowedUploadMimes    = ['image/jpeg','image/png','image/webp',
                                'application/pdf','text/plain','text/csv'];

// Règles métier — désormais lisibles via GET /settings/public (écart n°6
// clos). Ces valeurs restent ici comme REPLI si l'appel échoue, pas comme
// source de vérité : préférer settings.missionMinLeadTimeMinutes, etc.
const kMissionMinLeadTime       = Duration(minutes: 60);
const kCancellationNoticeHours  = Duration(hours: 6);
const kMissionStartWindow       = Duration(minutes: 120);
const kMissionPendingExpiry     = Duration(hours: 24);
const kMissionAutoCloseDays     = 7;
const kReviewWindowDays         = 14;

// Idempotence et débits
const kIdempotencyTtl        = Duration(minutes: 10);
const kMaxBookingsPerHour    = 10;
const kMaxDeviceRegPerDay    = 30;
const kMaxReviewReportsPerDay = 20;

// Pagination
const kDefaultPageSize       = 20;
const kMaxPageSize           = 100;   // 50 sur /providers/search
const kSearchMaxPageSize     = 50;
const kSearchDefaultRadiusKm = 10;
const kSearchMaxRadiusKm     = 50;

// Divers
const kCurrency              = 'XOF';
const kWeekdaySundayIsZero   = true;  // 0 = dimanche, 6 = samedi
```

---

## 9. Ordre de développement recommandé

| Lot | Contenu | Dépendances |
|---|---|---|
| **L0 — Socle** | `ApiEnvelope`, `ApiException`, `EnvelopeInterceptor`, `AuthInterceptor` (§2.3, §5.1), stockage sécurisé, `go_router` + redirection, états vides/erreur/chargement partagés | — |
| **L1 — Auth** | §2.1, §2.3, §2.4 — inscription, OTP, connexion, mot de passe oublié, déconnexion | L0 |
| **L2 — Client cœur** | §3.4, §3.5, §3.2, §3.6 — recherche, fiche, adresses, **réservation** | L1 |
| **L3 — Suivi client** | §3.7, §3.10, §3.11 — mes missions, annulation, report, notifications, messagerie | L2 |
| **L4 — Push** | §5.3 — cycle du jeton, routage au tap | L1 (+ L3 pour le routage) |
| **L5 — Onboarding prestataire** | §2.2 — P1 à P9, y compris upload de fichiers | L1 |
| **L6 — Espace prestataire** | §4.1, §4.2, §4.4, §4.5, §4.6 — tableau de bord, gestion, transitions, reports, documents | L5, L3 |
| **L7 — Compléments** | §3.3 favoris, §3.9 avis, §4.3 portfolio, §3.8 litiges | L3, L6 |
| **L8 — Hors-ligne** | §5.4 — cache de lecture, bannière, désactivation des écritures | L2, L3 |

L2 est le **chemin critique** : c'est la boucle de valeur (chercher → réserver).
L5 peut être mené en parallèle par un second développeur dès la fin de L1 — les
deux surfaces ne partagent que le socle.

---

## 10. Ce que ce document n'établit pas

Par honnêteté sur les limites de la vérification menée :

- **Valeurs réelles des réponses de `/disputes/*`** — la STRUCTURE est
  désormais contractualisée (DTO Swagger ajoutés, écart n°16 clos, jeu de clés
  verrouillé par un test automatisé), mais aucune capture manuelle par `curl`
  n'a été faite pour ce module en particulier : les exemples éventuels à
  ajouter ici restent à produire au moment du développement de l'écran.
- **Messages d'erreur exacts du service de disponibilité** (chevauchement de
  créneaux, `endTime < startTime`) — la description Swagger les regroupe, les
  textes précis levés par `availability.service.ts` n'ont pas été capturés par
  appel réel. Les règles, elles, sont certaines : les reproduire côté client.
- **Comportement de `mission.expired` et `mission.auto_close`** — produits par
  des jobs planifiés, non déclenchables à la demande, donc non observés en appel
  réel. Les codes de notification et les réglages associés sont en revanche
  vérifiés dans le code.
- **Contenu réel d'un push FCM** — aucun fournisseur n'est configuré sur
  l'environnement de développement (`FCM_*` commentées). La charge utile `data`
  est établie à partir des appels `events.notify(...)` du code, tous relevés
  en §3.10.
- **Charge `errors[]` de `POST /providers/me/submit` en conditions réelles** —
  la forme est lue dans `checklistErrors()` et le filtre d'exception ; elle n'a
  pas été déclenchée par un appel, le compte démo étant déjà approuvé.
- **Ergonomie, design, maquettes** — hors périmètre. Ce document décrit le
  contrat de données et les règles métier, pas l'interface.

---

*Fin du document. Toute évolution du backend touchant une route listée en §6 doit
donner lieu à une mise à jour de la section correspondante — et, si un écart de
§7 est comblé, à la suppression de l'entrée et de son contournement.*

