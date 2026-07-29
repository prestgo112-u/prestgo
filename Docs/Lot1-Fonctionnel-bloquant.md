# Lot 1 — Correctifs fonctionnels bloquants

**Date :** 19 juillet 2026
**Périmètre :** `apps/api` + `apps/admin`
**Origine :** audit de conformité au cahier des charges v1.2
**Prérequis :** [Lot 0](Lot0-Securite-socle.md)

---

## 1. Pourquoi ce lot

Le Lot 0 a fermé les failles de sécurité. Le Lot 1 s'attaque à ce qui empêchait
le back-office d'être **réellement utilisable** :

- un agent devait approuver ou rejeter un justificatif **sans pouvoir l'ouvrir** ;
- une mission n'avait ni prestation, ni prix, ni adresse d'intervention ;
- les exports produisaient un fichier **vide** (0 octet) et non téléchargeable ;
- aucune donnée envoyée à l'API n'était validée.

---

## 2. Ce qui a été fait

### 2.1 Les missions sont enfin reliées au catalogue et à un lieu

Le modèle `Mission` a reçu deux liens qui manquaient (`prisma/schema.prisma`) :

| Champ | Pointe vers | Ce que ça apporte |
|---|---|---|
| `packId` | `ServicePack` | le titre de la prestation, son **prix** et sa **durée** |
| `addressId` | `Address` | le **lieu d'intervention** |

Trois index ont aussi été ajoutés : `packId`, `addressId` et **`scheduledAt`**
(ce dernier parce que le back-office filtre les missions par période — sans
index, chaque filtre de date parcourait toute la table).

Le détail mission renvoie désormais ces informations, et la fiche les affiche.
Quand le lien est absent, l'écran l'indique en rouge plutôt que de faire comme
si de rien n'était.

### 2.2 Les fichiers existent vraiment

**Avant :** `POST /files/upload` n'enregistrait que des *métadonnées*. Aucun
octet n'était jamais écrit nulle part. Il n'existait aucune route pour relire un
contenu.

**Après :** un service de stockage (`FileStorageService`) écrit et relit les
fichiers sur le disque, sous un dossier racine configurable par la variable
`FILE_STORAGE_DIR` (par défaut `storage/`).

| Route | Rôle |
|---|---|
| `POST /files/upload` | envoi réel en `multipart/form-data` (champ `file`) |
| `GET /files/:id` | métadonnées |
| **`GET /files/:id/content`** | **contenu réel du fichier** |
| `DELETE /files/:id` | désactivation (on ne supprime pas : le CDC veut l'historique) |

Garde-fous appliqués :
- taille maximale **10 Mo** ;
- types acceptés : JPEG, PNG, WebP, PDF, texte, CSV — tout le reste est refusé ;
- la clé de stockage reste calculée par le serveur (règle du Lot 0) ;
- le service refuse toute clé qui sortirait du dossier racine (deuxième barrière
  contre les `../../`).

### 2.3 Un agent peut enfin consulter un justificatif

C'était le défaut le plus gênant du back-office.

Nouvelle route `POST /admin/verifications/documents/:id/file` : elle rattache un
justificatif (scan, photo, PDF) à un document de vérification. Le fichier est
enregistré en visibilité **`sensitive`** et **appartient au prestataire**, donc
seul lui ou un agent porteur de `files.sensitive.read` peut l'ouvrir.

Un nouveau justificatif **remet automatiquement le document en attente de
revue** : la décision précédente ne portait plus sur le bon fichier.

Côté interface (`ProviderDetailPage`), la table des documents gagne :
- une colonne **Justificatif** avec un bouton **Consulter** qui ouvre le document
  dans une fenêtre d'aperçu (composant `FilePreview`) — image, PDF ou texte ;
- un bouton **Joindre / Remplacer** ;
- et surtout : **Approuver et Rejeter sont désactivés tant qu'aucun fichier n'est
  joint**. On ne peut plus décider à l'aveugle.

> Détail technique : un fichier protégé ne peut pas être mis dans un `<img src>`
> ou un `<a href>`, car le navigateur n'y joindrait pas le token. Le client API a
> donc reçu `fetchBlobUrl()`, qui télécharge le contenu avec le token puis en
> fait une URL temporaire locale.

Le rôle **agent_validation** a reçu la permission `files.sensitive.read` dans le
seed — sans elle, il n'aurait pas pu ouvrir les pièces qu'il doit justement examiner.

### 2.4 Les exports génèrent un vrai CSV

**Avant :** `exports.service.ts` créait une ligne `File` avec `size: 0` et
marquait le job « completed ». Aucun contenu n'était produit.

**Après :** le CSV est construit à partir des vraies données, écrit sur le
disque, et sa taille réelle est enregistrée. Cinq types sont couverts :
`users`, `providers`, `missions`, `disputes`, `reviews`.

Deux choix pour qu'Excel français ouvre le fichier correctement (module `csv.ts`) :
- séparateur **point-virgule** (Excel FR n'attend pas la virgule) ;
- **BOM UTF-8** en tête, sinon les accents s'affichent mal.

Les valeurs contenant un séparateur, un guillemet ou un saut de ligne sont
échappées correctement (8 tests unitaires dans `tests/unit/csv.spec.ts`).

Si la génération échoue, le job passe en `failed` au lieu de rester bloqué en
`pending` pour toujours.

Côté interface, la colonne « prêt (accès restreint) » est remplacée par un
bouton **Télécharger le CSV**.

### 2.5 La validation des entrées fonctionne enfin

**Le problème de fond, découvert en cours de route :** le projet avait
`class-validator` **0.15.1** installé. Cette version cible les décorateurs
standard TC39, alors que NestJS 10 utilise les décorateurs « legacy ». Tout
décorateur de validation plantait donc au chargement (`Cannot read properties of
undefined`). C'est très probablement **pourquoi aucun DTO n'avait jamais été
écrit**. Le projet est repassé en **0.14.1**, la version que NestJS attend
(l'avertissement de peer dependency le disait déjà).

> Note pour plus tard : un test de validation lancé via `tsx` ou `vitest`
> échouera quand même, car esbuild compile en décorateurs standard. Seule la
> chaîne `tsc` (celle du vrai build) applique le bon mode.

**17 classes de DTO** ont été créées, couvrant toutes les routes d'écriture et
toutes les listes :

| Module | DTO |
|---|---|
| commun | `PaginationQueryDto` (page, limit ≤ 100, sort) |
| auth | `LoginBodyDto`, `RefreshBodyDto` |
| users | `UserListQueryDto`, `UpdateUserStatusBodyDto` |
| providers | `ProviderListQueryDto`, `ProviderStatusChangeBodyDto`, `ProviderUpdateBodyDto` |
| missions | `MissionListQueryDto`, `MissionStatusChangeBodyDto`, `MissionRescheduleBodyDto`, `MissionCancelBodyDto` |
| disputes | `DisputeListQueryDto`, `OpenDisputeBodyDto`, `AssignDisputeBodyDto`, `DisputeStatusChangeBodyDto`, `DisputeMessageBodyDto` |
| catalog | `CreateCategoryBodyDto`, `UpdateCategoryBodyDto`, `CreateServiceTypeBodyDto`, `UpdateServiceTypeBodyDto`, `AttachProviderServiceBodyDto` |
| zones | `CreateZoneBodyDto`, `UpdateZoneBodyDto` |
| availability | `CreateAvailabilityBodyDto` |
| reviews | `ReviewListQueryDto`, `ReviewStatusChangeBodyDto` |
| roles | `CreateRoleBodyDto`, `UpdateRoleBodyDto`, `AssignPermissionsBodyDto` |
| documents | `RejectDocumentBodyDto` |
| administration | `UpdateSettingBodyDto`, `SendNotificationBodyDto`, `CreateExportBodyDto` |
| audit | `AuditListQueryDto` |

Les messages d'erreur sont **en français** et renvoyés dans le tableau `errors`
du format standard, exploitable directement par le front.

Point important sur les paramètres d'URL : `?page=2` arrive toujours sous forme
de **texte**. Le décorateur `@Type(() => Number)` le convertit avant vérification
— sans lui, `@IsInt` échouerait systématiquement.

### 2.6 Seed enrichi

- Un **vrai justificatif de démonstration** est écrit sur le disque et rattaché
  à chaque document des prestataires de démo. Sans ça, l'écran afficherait
  « aucun fichier » et les boutons resteraient inactifs.
- Le catalogue est désormais créé **avant** la mission de démo, qui est reliée à
  une prestation (« Réparation de fuite simple », 15 000 F CFA, 60 min) et à une
  adresse (Cocody, Abidjan).
- Nouvelle permission `files.any.read` (déjà introduite au Lot 0) et
  `files.sensitive.read` accordée au rôle `agent_validation`.

### 2.7 Un `.gitignore` a été créé

Le dépôt n'en avait **aucun**. C'était sans conséquence tant qu'aucun fichier
n'était stocké — mais maintenant que `storage/` contient des **pièces d'identité**
et des **extractions de données personnelles**, il fallait absolument les exclure.
Le fichier couvre aussi `node_modules/`, `dist/` et `.env` (qui contient le mot de
passe de la base).

---

## 3. Vérifications effectuées

`typecheck` API ✅ · `build` API ✅ · `typecheck` front ✅ · `build` front ✅
· `vitest` : **96 tests passent** (88 + 8 nouveaux sur le CSV) ✅

L'API a été démarrée réellement et les scénarios suivants exécutés :

| # | Scénario | Attendu | Obtenu |
|---|---|---|---|
| 1 | Login avec email malformé | 400 + détail par champ | ✅ 2 erreurs listées |
| 2 | Zone avec `latitude: 999` | 400 | ✅ « La latitude doit être comprise entre -90 et 90 » |
| 3 | `?limit=5000` | 400 | ✅ « limit ne peut pas dépasser 100 » |
| 4 | Statut de mission inventé | 400 | ✅ « Statut de mission inconnu » |
| 5 | Export `providers` | CSV rempli | ✅ en-têtes + 2 lignes réelles |
| 6 | Téléchargement du CSV | contenu | ✅ BOM + `;` + données |
| 7 | Type d'export inconnu | 400 | ✅ liste des valeurs acceptées |
| 8 | Upload multipart d'un `.txt` | 200 | ✅ 55 octets, clé serveur |
| 9 | Upload d'un `.exe` | 400 | ✅ « Type de fichier non autorisé » |
| 10 | Rattacher un justificatif à un document | 200 | ✅ document repassé en `pending` |

**Le seed a été vérifié sur une base jetable** (`prestgo_seedcheck`, créée puis
supprimée) afin de ne pas toucher à la base de développement :

```
documents: 3 | avec fichier joint: 3
   - identity  -> identity-demo.txt  (243 octets, sensitive)
   - insurance -> insurance-demo.txt (244 octets, sensitive)
   - identity  -> identity-demo.txt  (246 octets, sensitive)
mission -> prestation: Réparation de fuite simple | 15000 F CFA | 60 min
mission -> adresse   : Domicile, Cocody, Abidjan
permission files.any.read presente: true
agent_validation peut lire les fichiers sensibles: true
```

Le détail mission et le contenu d'un justificatif ont ensuite été relus par
l'API sur cette base propre, dans la forme exacte attendue par le front.

---

## 4. À faire de ton côté

Ta base de développement contient encore les anciennes données (documents sans
fichier, mission sans prestation ni adresse). Le seed est protégé contre les
doublons, donc **il ne remplira pas ces manques tout seul**. Pour voir les
nouvelles fonctionnalités sur les données de démo, il faut recréer la base :

```bash
cd apps/api
corepack pnpm exec prisma db push --force-reset   # ⚠️ efface toutes les données
corepack pnpm db:seed
```

Si tu préfères **garder tes données**, lance simplement le seed : il ajoutera la
permission manquante et le catalogue, mais les anciens documents resteront sans
justificatif. Tu pourras alors en joindre un depuis l'interface, bouton
**Joindre** — ce qui revient à tester la fonctionnalité pour de vrai.

---

## 5. Ce que le Lot 1 ne règle PAS

- **`sort`** : le paramètre est maintenant *validé*, mais toujours pas
  *appliqué* — tous les tris restent figés sur `createdAt desc`.
- **Format de réponse** : toujours appliqué à la main via `ok()` dans chaque
  contrôleur, sans interceptor pour le garantir.
- **Hashage** : scrypt sans paramètres de coût explicites (voir Lot 0).
- **Tests** : les 13 anciens fichiers restent factices ; seuls les 8 tests du CSV
  et ceux de la politique d'accès aux fichiers testent vraiment quelque chose.
  → **Lot 5**
- **Écrans manquants** : Clients, Vérifications, Rôles & permissions. → **Lot 2**
- **Graphiques du tableau de bord** : toujours absents. → **Lot 2**
- **Stockage** : le disque local convient au développement. Pour la production,
  il faudra remplacer `FileStorageService` par un stockage objet (S3 ou
  équivalent) — l'interface a été conçue pour que seul ce fichier change.
