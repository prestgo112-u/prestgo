# PRESTGO — Back-office & API

Sommaire de la documentation et guide de démarrage.

---

## 1. Ce qu'est ce projet

Le **backend** (API) et le **back-office** (interface d'administration) de la
plateforme PRESTGO. Les applications client et prestataire ne sont pas dans ce
dépôt, mais l'API expose déjà les routes qu'elles consommeront.

| Dossier | Contenu | Technologie |
|---|---|---|
| `apps/api` | l'API et la base de données | NestJS + Prisma + PostgreSQL |
| `apps/admin` | l'interface d'administration | React + Vite |
| `Docs` | cette documentation | — |

---

## 2. Démarrer (première fois)

### Prérequis

- **Node.js 22** ou plus récent — vérifie avec `node --version`
- **PostgreSQL 17** installé et démarré
- **corepack** (fourni avec Node) — active-le une fois : `corepack enable`

### Étapes

```bash
# 1. Installer les dépendances (depuis la racine du projet)
corepack pnpm install

# 2. Créer le fichier de configuration
cp apps/api/.env.example apps/api/.env
```

Ouvre ensuite `apps/api/.env` et remplace `TON_MOT_DE_PASSE` par le mot de passe
de l'utilisateur `postgres` (celui choisi à l'installation de PostgreSQL).

```bash
# 3. Créer les tables et les données de démonstration
cd apps/api
corepack pnpm exec prisma db push
corepack pnpm db:seed
cd ../..
```

> `db push` crée la base `prestgo` si elle n'existe pas. Le seed est
> **rejouable** : le relancer ne crée pas de doublons.

---

## 3. Lancer au quotidien

Deux terminaux, l'un pour l'API, l'autre pour l'interface :

```bash
# Terminal 1 — l'API
corepack pnpm --filter @prestgo/api dev
```
```bash
# Terminal 2 — le back-office
corepack pnpm --filter @prestgo/admin dev
```

| Adresse | Quoi |
|---|---|
| http://localhost:5173 | **le back-office** — c'est là que tu vas |
| http://localhost:3000/api/v1 | l'API |
| http://localhost:3000/api/docs | la documentation interactive de l'API (Swagger) |

**Connexion :** `admin@prestgo.test` / `prestgo123!`

> Compte de démonstration : à ne jamais utiliser tel quel en production.

---

## 4. Que tester ? Un parcours en 10 minutes

Une fois connecté, voici de quoi voir concrètement ce qui a été construit.

### 4.1 Vérifications — *le manque le plus criant, corrigé*

Menu **Vérifications** → clique **Consulter** sur une ligne.

Le justificatif s'ouvre dans une fenêtre. Remarque que **Approuver** et
**Rejeter** sont grisés tant qu'aucun fichier n'est joint : c'est volontaire, on
ne décide jamais à l'aveugle. Avant, on validait des pièces d'identité sans
pouvoir les regarder.

Le bouton **Joindre** permet d'attacher un nouveau justificatif — le document
repasse alors automatiquement « en attente », puisque la décision précédente ne
portait plus sur le bon fichier.

### 4.2 Rôles & permissions — *un critère du cahier des charges*

Menu **Rôles & permissions**.

1. Crée un rôle : code `agent_test`, nom `Agent de test`
2. Sélectionne-le, coche **une seule** permission (par exemple `admin.clients.read`)
3. Va dans **Utilisateurs** → ouvre un compte → affecte-lui ce rôle

Ce compte n'aura plus accès qu'à l'écran Clients. Les autres entrées du menu
disparaissent, et taper l'URL directement affiche « Accès refusé ».

### 4.3 Exports — *ils étaient vides*

Menu **Exports** → choisis `missions` → **Demander un export** → **Télécharger le CSV**.

Ouvre le fichier : il contient les vraies données, avec la prestation, le prix
et la ville. Il s'ouvre correctement dans Excel français (accents et colonnes).

### 4.4 Tableau de bord

8 cartes chiffrées et 4 graphiques, avec un sélecteur de période (7/30/90 jours).
Chaque carte est cliquable vers l'écran correspondant.

### 4.5 Missions et Litiges

Menu **Missions** : filtres par statut, période, et recherche. Ouvre une mission
→ tu vois la prestation, le prix, l'adresse, et tu peux la **reprogrammer**.

Menu **Litiges** : ouvre-en un → tu peux **affecter un agent** et écrire un
message. La case *commentaire interne* n'existe pas encore côté interface, mais
la séparation fonctionne côté API (voir §6).

### 4.6 L'API publique (sans connexion)

Ouvre simplement dans ton navigateur :

- http://localhost:3000/api/v1/categories
- http://localhost:3000/api/v1/zones
- http://localhost:3000/api/v1/zones/nearby?latitude=5.325&longitude=-4.022&radiusKm=10

La dernière trouve les zones dans un rayon donné et affiche la distance.

---

## 4.7 Tester l'API en ligne de commande

> ⚠️ **Piège Windows :** dans PowerShell, `curl` n'est **pas** le vrai curl,
> c'est un alias vers `Invoke-WebRequest` qui n'accepte pas la même syntaxe.
> Utilise `Invoke-RestMethod` (ci-dessous), ou écris `curl.exe` en toutes
> lettres pour appeler le vrai curl.

L'API doit tourner (`corepack pnpm --filter @prestgo/api dev`).

### Se connecter et garder le jeton

Toutes les commandes suivantes réutilisent `$headers`. Lance ce bloc **en
premier**, dans le même terminal PowerShell :

```powershell
$base = "http://localhost:3000/api/v1"
$login = Invoke-RestMethod -Method Post -Uri "$base/auth/login" `
  -ContentType "application/json" `
  -Body '{"email":"admin@prestgo.test","password":"prestgo123!"}'
$headers = @{ Authorization = "Bearer $($login.data.accessToken)" }
"Connecté."
```

### Lire des données

```powershell
# Tableau de bord
$dash = Invoke-RestMethod -Uri "$base/admin/dashboard/summary" -Headers $headers
"Prestataires en attente : $($dash.data.pendingProviders)"
"Litiges ouverts        : $($dash.data.openDisputes)"

# Liste des prestataires, en tableau lisible
(Invoke-RestMethod -Uri "$base/admin/providers?limit=5" -Headers $headers).data |
  Select-Object publicName, validationStatus, score | Format-Table -AutoSize

# File de vérification
$verif = Invoke-RestMethod -Uri "$base/admin/verifications/providers" -Headers $headers
"$($verif.meta.total) document(s) à examiner"

# Journal d'audit : qui a fait quoi
(Invoke-RestMethod -Uri "$base/admin/audit-logs?limit=5" -Headers $headers).data |
  Select-Object action, entity, createdAt | Format-Table -AutoSize
```

### Créer un export et le télécharger

```powershell
$job = Invoke-RestMethod -Method Post -Uri "$base/admin/exports" -Headers $headers `
  -ContentType "application/json" -Body '{"type":"providers"}'
"Statut : $($job.data.status)"

# Récupérer le contenu du CSV
$csv = Invoke-RestMethod -Uri "$base/files/$($job.data.fileId)/content" -Headers $headers
($csv -split "`r`n")[0..2]

# Ou l'enregistrer sur le Bureau
Invoke-RestMethod -Uri "$base/files/$($job.data.fileId)/content" -Headers $headers `
  -OutFile "$env:USERPROFILE\Desktop\export.csv"
```

> Les accents peuvent s'afficher bizarrement **dans la console** (`Ã‰lectricitÃ©`) :
> c'est l'encodage de l'affichage PowerShell, pas le fichier. Ouvert dans Excel,
> le CSV est correct.

### Routes publiques — aucun jeton nécessaire

```powershell
# Catalogue
(Invoke-RestMethod -Uri "$base/categories").data | Select-Object name, slug

# Zones dans un rayon de 10 km autour du Plateau
$z = Invoke-RestMethod -Uri "$base/zones/nearby?latitude=5.325&longitude=-4.022&radiusKm=10"
"$($z.data[0].name) est à $($z.data[0].distanceKm) km"

# Avec un rayon de 3 km : la liste est vide (Cocody est à 5,42 km)
(Invoke-RestMethod -Uri "$base/zones/nearby?latitude=5.325&longitude=-4.022&radiusKm=3").data.Count
```

### Voir le format d'erreur standard

```powershell
try { Invoke-RestMethod -Uri "$base/admin/users" } catch {
  $err = $_.ErrorDetails.Message | ConvertFrom-Json
  "message        : $($err.message)"
  "correlationId  : $($err.meta.correlationId)"
}
```

L'`correlationId` est l'identifiant unique de la requête : c'est lui qui permet
de retrouver la ligne correspondante dans les journaux du serveur.

### Tester le contrôle d'accès

```powershell
# Connexion en tant que client (pas administrateur)
$c = Invoke-RestMethod -Method Post -Uri "$base/auth/login" -ContentType "application/json" `
  -Body '{"email":"client.demo@prestgo.test","password":"prestgo123!"}'
$clientHeaders = @{ Authorization = "Bearer $($c.data.accessToken)" }

# Il n'a pas le droit d'accéder aux réglages -> 403 attendu
try { Invoke-RestMethod -Uri "$base/admin/settings" -Headers $clientHeaders }
catch { "Refusé : $($_.Exception.Response.StatusCode.value__)" }
```

### Si tu préfères Git Bash

La syntaxe curl habituelle fonctionne sans surprise :

```bash
BASE=http://localhost:3000/api/v1
TOKEN=$(curl -s -X POST $BASE/auth/login -H "Content-Type: application/json" \
  -d '{"email":"admin@prestgo.test","password":"prestgo123!"}' \
  | sed -n 's/.*"accessToken":"\([^"]*\)".*/\1/p')

curl -s "$BASE/admin/dashboard/summary" -H "Authorization: Bearer $TOKEN"
curl -s "$BASE/categories"
```

### Ou sans rien installer : Swagger

http://localhost:3000/api/docs — toutes les routes y sont listées avec un bouton
**Try it out** pour les essayer directement dans le navigateur. Clique d'abord
sur **Authorize** en haut à droite et colle ton jeton.

---

## 5. Vérifier que tout fonctionne

```bash
corepack pnpm --filter @prestgo/api test
```

**91 tests** démarrent la vraie API et l'interrogent. Si un test passe au rouge,
tu as cassé quelque chose — et le message te dit quoi.

Ils utilisent leur **propre base** (`prestgo_test`), créée automatiquement. Ta
base de développement n'est jamais touchée.

| Commande | Usage |
|---|---|
| `pnpm --filter @prestgo/api test` | tout (≈ 40 s) |
| `pnpm --filter @prestgo/api test:unit` | uniquement les tests rapides, sans base |
| `pnpm --filter @prestgo/api test:watch` | en continu pendant que tu codes |
| `pnpm typecheck` | vérifie les types, sans lancer l'application |

---

## 6. Tester les parcours qui ont besoin d'un email ou d'un SMS

Aucun email ni SMS n'est réellement envoyé pour l'instant. Pour tester
l'inscription, le code de vérification ou le mot de passe oublié, ajoute cette
ligne à `apps/api/.env` :

```
AUTH_EXPOSE_DEV_CODES=true
```

Le code est alors renvoyé dans la réponse de l'API, sous la clé `devCode`
(ou `devToken` pour le mot de passe oublié). Redémarre l'API après modification.

> ⚠️ Ce réglage est **absent par défaut**. En production, le code n'apparaît
> jamais dans une réponse — uniquement dans les journaux du serveur.

Les notifications envoyées sont consultables dans
`apps/api/storage/outbox/email.log`.

---

## 7. Les documents détaillés

Chaque lot a son document, avec le pourquoi, le comment et les vérifications
effectuées.

| Document | Contenu |
|---|---|
| [Lot 0 — Sécurité du socle](Lot0-Securite-socle.md) | gardes globales, fuites d'erreurs, faille sur les fichiers, limitation d'appels |
| [Lot 1 — Fonctionnel bloquant](Lot1-Fonctionnel-bloquant.md) | consultation des justificatifs, exports CSV réels, missions complètes, validation des données |
| [Lot 2 — Écrans manquants](Lot2-Ecrans-manquants.md) | Clients, Vérifications, Rôles & permissions, tableau de bord |
| [Lot 3 — API complète](Lot3-API-complete.md) | inscription, mot de passe oublié, OTP, routes publiques |
| [Lot 4 — Modèle de données](Lot4-Modele-de-donnees.md) | 7 tables, clés étrangères, commentaire interne, recherche géographique |
| [Lot 5 — Fiabilité](Lot5-Fiabilite.md) | 91 tests réels, notifications acheminées, entretien automatique |
| [Lots 6 et 7 — Surface mobile et production](Lot6-7-Surface-mobile-et-production.md) | réservation, recherche, espace prestataire, avis, migrations versionnées, Redis, push et SMS |
| [Checklist infrastructure](INFRA-CHECKLIST.md) | mise en service Redis/BullMQ, SMS, push |
| [Données de démonstration](SEED-DATA.md) | comptes de test (dont un prestataire déjà approuvé, prêt pour réserver) |

Le cahier des charges d'origine :
[Cahier des charges v1.2](Cahier_des_charges_PRESTGO_Backoffice_Backend_API_v1.2.md)

Les documents des cinq user stories initiales (US1 à US5) décrivent l'état
antérieur du projet.

---

## 8. Où en est le projet

| Axe du cahier des charges | Avant l'audit | Maintenant |
|---|---|---|
| Endpoints (§8) | 48 / 77 | **155 opérations** |
| Modèle de données (§7) | 32 / 40 tables | **47 tables** |
| Écrans du back-office (§4) | 13 / 15 menus | **16 entrées** |
| Sécurité et exigences non fonctionnelles | 1 / 15 | **15 / 15** |
| Tests | 0 réel | **163 réels** |

Le backend expose désormais la **surface mobile complète** : un client peut
chercher un prestataire, réserver, suivre et noter ; un prestataire construit
seul son dossier, le soumet, puis accepte, démarre et termine ses missions.

---

## 9. Ce qui reste à faire

**Avant une mise en production :**

Les trois points bloquants — migrations versionnées, file persistante, format du
hash de mot de passe — ont été traités par le
[Lot 7](Lot6-7-Surface-mobile-et-production.md). Il reste à **configurer les
comptes fournisseurs** : le code FCM (push) et Termii / Africa's Talking (SMS)
est écrit et branché, mais sans identifiants les messages partent dans le
journal fichier. C'est une opération de configuration, sans changement de code.

**Côté fonctionnel :**

- aucun test sur le back-office (seule l'API est couverte) ;
- les nouveautés du Lot 4 fonctionnent côté API mais n'ont pas encore d'écran :
  preuves attachées à un litige, case « commentaire interne », indisponibilités
  exceptionnelles d'un prestataire ;
- **PostGIS** reste une dette assumée : la recherche géographique utilise un
  pré-filtre rectangle indexé + haversine, au résultat identique pour la
  volumétrie d'Abidjan au lancement ;
- **WebSocket** pour le chat en direct : optionnel, le chat fonctionne en REST.

---

## 10. Problèmes courants

| Symptôme | Cause probable | Solution |
|---|---|---|
| `Can't reach database server` | PostgreSQL n'est pas démarré, ou le mot de passe du `.env` est faux | vérifie le service PostgreSQL et `DATABASE_URL` |
| `address already in use :::3000` | l'API tourne déjà dans un autre terminal | ferme l'autre terminal, ou change `API_PORT` |
| Page blanche sur le back-office | l'API n'est pas démarrée | lance le terminal 1 |
| `429 Trop de tentatives` | plus de 10 connexions en une minute | attends une minute |
| Le seed semble ne rien faire | il est rejouable et saute ce qui existe déjà | c'est le comportement attendu |
