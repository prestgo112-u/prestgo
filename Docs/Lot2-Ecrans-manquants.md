# Lot 2 — Écrans manquants et compléments du back-office

**Date :** 19 juillet 2026
**Périmètre :** `apps/api` + `apps/admin`
**Origine :** audit de conformité au cahier des charges v1.2 (§4 Back-office, §11 Critères d'acceptation)
**Prérequis :** [Lot 0](Lot0-Securite-socle.md) · [Lot 1](Lot1-Fonctionnel-bloquant.md)

---

## 1. Pourquoi ce lot

L'audit avait relevé **3 écrans totalement absents** et **8 écrans partiels**.
Le menu comptait 13 entrées sur les 15 attendues, le tableau de bord affichait
3 cartes sur 8 sans aucun graphique, et un critère d'acceptation explicite du
CDC n'était pas satisfait :

> « Un super admin peut créer des rôles, affecter des permissions et gérer les
> utilisateurs internes. »

Le backend savait déjà le faire. Aucune interface ne l'appelait.

---

## 2. Les trois écrans qui manquaient

### 2.1 Rôles & permissions

Écran en deux colonnes : la liste des rôles à gauche, leurs permissions
regroupées par module à droite. On peut créer un rôle et cocher/décocher ses
permissions.

**C'était un manque purement front** : les cinq routes existaient déjà
(`GET /admin/roles`, `GET /admin/permissions`, `POST /admin/roles`,
`PATCH /admin/roles/:id`, `PATCH /admin/roles/:id/permissions`) mais aucune
n'était appelée par le back-office.

Il manquait toutefois une pièce côté API : **rien ne permettait d'affecter un
rôle à un utilisateur**. Nouvelle route `PATCH /admin/users/:id/roles`, avec
son formulaire sur la fiche utilisateur. Le remplacement se fait d'un bloc,
dans une transaction, pour ne jamais laisser un compte à moitié modifié.

### 2.2 Clients

Nouveau modèle `ClientProfile` (prévu au CDC §7) et nouveau module API avec
quatre routes : liste filtrable, fiche, historique des missions, note interne.

**Comment on reconnaît un client ?** C'est un utilisateur qui n'a ni profil
prestataire, ni aucun rôle interne. On ne se base pas sur l'existence d'un
`ClientProfile` : quelqu'un peut commander une mission sans qu'un profil ait été
créé. Le profil sert à porter les informations internes (la note du support),
et il est créé au premier besoin.

Cette définition a un effet visible et voulu : dès qu'on donne un rôle à un
compte, il quitte la liste des clients pour devenir un compte interne.

Les notes s'empilent en gardant leur date — on n'écrase jamais ce qu'un collègue
a écrit avant.

### 2.3 Vérifications

File d'attente **transverse** : tous les documents à examiner, tous prestataires
confondus, du plus ancien au plus récent. Avant, il fallait ouvrir chaque
prestataire un par un pour découvrir s'il avait quelque chose en attente.

Nouvelle route `GET /admin/verifications/providers`. Comme au Lot 1, les boutons
Approuver et Rejeter restent **désactivés tant qu'aucun justificatif n'est
consultable** : on ne décide jamais à l'aveugle.

> Note technique : le contrôleur de vérification a changé de préfixe
> (`admin/verifications/documents` → `admin/verifications`) pour héberger la
> nouvelle route. Les chemins publics des routes existantes sont inchangés.

---

## 3. Tableau de bord : de 3 cartes à 8 cartes + 4 graphiques

### 3.1 Un compteur qui mentait

L'ancienne carte « Prestataires en attente » comptait en réalité les
**utilisateurs** au statut `pending` :

```ts
// Avant — commentaire d'origine laissé depuis l'US1 :
// « Le modèle Provider arrive en US2 ; en attendant on compte les comptes
//   "en attente" comme approximation »
this.prisma.user.count({ where: { status: "pending" } })
```

Ce raccourci n'a jamais été retiré une fois le modèle `ProviderProfile` créé.
La carte affichait donc un chiffre sans rapport avec le nombre de dossiers à
valider. Elle compte maintenant les vrais profils en `pending_review`.

### 3.2 Les 8 cartes du CDC §4.2

Utilisateurs total · Utilisateurs actifs · Prestataires validés · Prestataires
en attente · Missions du jour · Missions en cours · Litiges ouverts · Avis à
modérer. Chaque carte est **cliquable** vers l'écran correspondant.

### 3.3 Les graphiques

Nouvelle route `GET /admin/dashboard/charts?days=30` qui renvoie :

| Série | Contenu |
|---|---|
| `signupsByDay` | inscriptions par jour, **cases à zéro incluses** (sinon la courbe aurait des trous) |
| `missionsByCategory` | missions par type de service |
| `missionsByCity` | missions par ville d'intervention |
| `missionsByStatus` | répartition par statut |
| `cancellationRate` | taux d'annulation en % |
| `averageValidationHours` | délai moyen entre dépôt et revue d'un document |

Côté interface : une courbe et trois graphiques en barres, **dessinés en SVG
sans aucune librairie**. Le back-office n'a que React et React Router comme
dépendances ; ajouter une librairie de graphiques pour quatre visuels simples
aurait alourdi le paquet livré au navigateur sans bénéfice réel.

Un sélecteur 7 / 30 / 90 jours recharge les séries.

Les **listes rapides** du CDC sont également là : derniers prestataires
inscrits, documents à vérifier, derniers litiges.

---

## 4. Le trou de sécurité du routage front

L'audit avait noté que masquer une entrée du menu ne protégeait rien : il
suffisait de **taper l'URL** pour ouvrir l'écran. Seule l'API refusait ensuite
les appels, ce qui donnait une page cassée plutôt qu'un refus clair.

Chaque URL est désormais associée à la permission qui la protège
(`permissionForPath`), y compris les pages de détail. Un utilisateur sans le
droit voit un message « Accès refusé » nommant la permission manquante.

Deuxième correction : après connexion, la redirection allait toujours vers
`/dashboard`. Un compte sans `admin.dashboard.read` atterrissait donc sur une
page interdite. Elle pointe maintenant vers **la première page autorisée**.

---

## 5. Écrans partiels complétés

| Écran | Ce qui a été ajouté |
|---|---|
| **Prestataires** | recherche par nom, **email et téléphone** (le backend ne cherchait que dans le nom public), pagination, colonnes disponibilité et score |
| **Prestataires (fiche)** | **notes internes** — le modèle existait en base mais aucune route n'écrivait dedans, les notes affichées étaient donc toujours vides |
| **Missions** | filtres période (du/au), recherche client/prestataire/ville, pagination, colonnes prestation et ville |
| **Missions (détail)** | **reprogrammation** — la route existait, aucun bouton ne l'appelait ; l'historique des reports est affiché |
| **Litiges** | filtres statut et recherche, pagination, colonnes client/prestataire enrichies |
| **Litiges (détail)** | **affectation à un agent** — `assignedTo` était déclaré mais jamais modifiable ; la liste des agents vient des comptes portant au moins un rôle |
| **Utilisateurs** | recherche et filtre par statut, **affectation de rôles** sur la fiche |

---

## 6. Un bug de validation découvert pendant les tests

En vérifiant la recherche prestataire, la requête `?search=ama&validationStatus=`
était refusée avec « Statut de validation inconnu ».

**Cause :** un filtre laissé vide dans un formulaire part sous la forme
`?status=`. Or `@IsOptional()` ne saute la validation que pour `null` et
`undefined` — **pas pour la chaîne vide**. La requête « tous les statuts » était
donc rejetée.

**Correction :** un décorateur `@EmptyToUndefined()`
([transforms.ts](apps/api/src/common/dto/transforms.ts)) appliqué à tous les
filtres facultatifs des 8 DTO de requête. Un statut réellement invalide est
toujours refusé — c'est vérifié par un test.

Ce piège aurait touché n'importe quel écran avec un filtre « Tous ».

---

## 7. Vérifications effectuées

`typecheck` API ✅ · `build` API ✅ · `typecheck` front ✅ · `build` front ✅
· `vitest` : **102 tests passent** (96 + 6 nouveaux sur les filtres) ✅

L'API a été lancée sur une **base jetable** (`prestgo_lot2`, créée puis
supprimée) pour ne pas toucher à la base de développement. 16 scénarios joués :

| # | Scénario | Résultat |
|---|---|---|
| 1 | Les 8 cartes du tableau de bord | ✅ `pendingProviders: 2` — le vrai compte, plus l'approximation |
| 2 | Graphiques sur 7 jours | ✅ catégorie « Réparation de fuite », ville « Abidjan », statut « confirmed » |
| 3 | Liste des clients | ✅ 1 client, 1 mission |
| 4 | Historique des missions d'un client | ✅ prestation + prestataire + prix |
| 5 | Note interne client | ✅ horodatée `[2026-07-19]` |
| 6 | File de vérification transverse | ✅ 3 documents, 2 prestataires différents |
| 7 | Filtres missions par période | ✅ août = 1, septembre = 0 |
| 8 | Filtres litiges + enrichissement | ✅ client et prestataire affichés |
| 9 | Recherche prestataire par email | ✅ (après correction du bug §6) |
| 10 | Filtre vide `?status=` | ✅ accepté ; statut invalide toujours refusé |
| 11 | Créer un rôle + lui donner une permission | ✅ |
| 12 | Affecter ce rôle à un utilisateur | ✅ `roles: ["agent_test"]`, `permissions: ["admin.clients.read"]` |
| 13 | Ce compte n'accède qu'à ce qui est permis | ✅ `/admin/clients` → 200, `/admin/users` → 403, `/admin/settings` → 403 |
| 14 | Note interne prestataire | ✅ écrite puis relue dans la fiche |
| 15 | Cohérence clients/internes | ✅ le compte ayant reçu un rôle sort de la liste clients |
| 16 | Traçabilité | ✅ `admin.users.roles.update` et `admin.providers.note.add` dans l'audit |

Le scénario 13 est le plus important : il prouve que **toute la chaîne RBAC
fonctionne de bout en bout**, de la création du rôle jusqu'au refus effectif.

---

## 8. État du menu

**16 entrées** (les 15 du CDC + Rôles & permissions) :

Tableau de bord · Utilisateurs · Clients · Prestataires · Vérifications ·
Catalogue · Zones · Missions · Messages · Avis · Litiges · Notifications ·
Rôles & permissions · Réglages · Audit · Exports

---

## 9. À faire de ton côté

**Relancer le seed** pour créer les deux nouvelles permissions
(`admin.clients.read`, `admin.clients.notes`) :

```bash
cd apps/api
corepack pnpm exec prisma db push   # ajoute la table ClientProfile
corepack pnpm db:seed
```

Ces deux commandes sont sans risque pour tes données : `db push` ajoute une
table sans toucher aux autres, et les permissions passent par `upsert`.

---

## 10. Ce que le Lot 2 ne règle PAS

- **`sort`** : toujours validé mais pas appliqué (tris figés sur `createdAt desc`).
- **Écran Messages** : toujours sans filtre ni recherche, et sans modération des
  conversations signalées.
- **Notifications** : canal toujours figé à `in_app`, pas de ciblage d'audience.
- **Pièces jointes de litige** : le CDC prévoit une table `dispute_files`, elle
  n'existe pas encore — impossible d'attacher une preuve à un litige.
- **Commentaire interne vs message visible** dans un litige : il manque le champ
  `internalOnly` sur `DisputeMessage`. → **Lot 4**
- **Routes non-admin** (`/categories`, `/zones`, `/providers/me/*`…) et
  **authentification complète** (register, mot de passe oublié, OTP). → **Lot 3**
- **Tests** : la majorité des anciens fichiers restent factices. → **Lot 5**
