# Lot 4 — Compléter le modèle de données

**Date :** 19 juillet 2026
**Périmètre :** `apps/api` (schéma Prisma + API)
**Origine :** audit de conformité au cahier des charges v1.2 (§7 Modèle de données, §10 Recherche)
**Prérequis :** Lots [0](Lot0-Securite-socle.md) · [1](Lot1-Fonctionnel-bloquant.md) · [2](Lot2-Ecrans-manquants.md) · [3](Lot3-API-complete.md)

---

## 1. Pourquoi ce lot

L'audit avait relevé sur le schéma :

- **8 tables absentes** du CDC §7 (une, `client_profiles`, a été créée au Lot 2) ;
- **5 champs manquants**, dont un explicitement demandé : distinguer un
  commentaire interne d'un message visible dans un litige ;
- **15 colonnes orphelines** : des identifiants d'utilisateur stockés en texte
  libre, sans aucune contrainte — rien n'empêchait d'y écrire n'importe quoi ;
- des **index manquants** sur des critères de recherche que le CDC cite
  nommément ;
- la recherche géographique par zone, non couverte.

**Résultat : la base passe de 35 à 42 tables et de 46 à 60 clés étrangères.**

---

## 2. Les 7 tables ajoutées

| Table | Rôle |
|---|---|
| `City` | ville de couverture — voir §3 |
| `AdminProfile` | poste et service d'un membre des équipes internes |
| `ProviderUnavailability` | absence exceptionnelle (congés), complète l'agenda hebdomadaire |
| `ServicePackOption` | option payante ajoutable à une formule |
| `ProviderPortfolioItem` | réalisations présentées par un prestataire |
| `ChatMessageFile` | pièce jointe d'un message |
| `DisputeFile` | preuve attachée à un litige |

---

## 3. Le cas `Zone.cityId`

C'était la seule donnée réellement incohérente. La colonne contenait le texte
`"abidjan"` — pas un identifiant, juste une étiquette. Aucune table `cities`
n'existait en face.

Poser la clé étrangère telle quelle aurait fait échouer la migration. La
séquence appliquée a donc été :

1. remise à `NULL` de la valeur (1 ligne concernée) ;
2. création de la table `City` et de la contrainte ;
3. le seed crée Abidjan et Yamoussoukro, puis **rattache les zones orphelines**
   à Abidjan.

Vérifié sur ta base : `Cocody -> Abidjan`.

---

## 4. Les champs ajoutés

| Champ | Pourquoi |
|---|---|
| `DisputeMessage.internalOnly` | **le plus important** — voir §5 |
| `ReviewReport.status` | sans lui, impossible de savoir si un signalement a été traité |
| `MissionReschedule.status` | le CDC prévoit un workflow demande → acceptation ; défaut `applied` pour les reports faits directement par un admin |
| `MissionCancellation.details` | le motif court d'un côté, les circonstances de l'autre |
| `CatalogCategory.iconFileId` | icône affichée dans l'application publique |

Deux nouveaux enums accompagnent ces champs : `ReportStatus` et
`RescheduleStatus`.

---

## 5. Commentaire interne vs message visible

Le CDC §4.5 demande deux choses distinctes dans un litige : « ajouter un
message » (vu des parties) et « commentaires internes » (vu du back-office
seul). Sans le champ `internalOnly`, **les notes des agents étaient visibles du
client et du prestataire**.

Le paramètre `includeInternal` de `findById` vaut **`false` par défaut** : si un
appelant oublie de le préciser, on montre le moins de choses possible, jamais
l'inverse.

Détail dans `disputes.controller.ts` : le litige est chargé **sans** les
commentaires internes *avant* la vérification d'accès. Même si ce contrôle
échouait, aucune note d'agent n'aurait été lue depuis la base.

Vérifié sur le même litige :

```
Back-office : "Bonjour, nous analysons votre dossier."
              "NOTE INTERNE : client déjà en litige le mois dernier."

Client      : "Bonjour, nous analysons votre dossier."
```

---

## 6. Les 15 colonnes orphelines

Ces colonnes stockaient un identifiant sans contrainte : `Review.authorId`,
`ChatMessage.senderId`, `Dispute.assignedTo`, `Notification.userId`,
`SystemSetting.updatedBy`, `ExportJob.fileId`…

**Contrôle préalable :** les 14 colonnes pointant vers `User` ou `File` ont été
auditées avant migration — **0 valeur invalide**. Les contraintes ont donc pu
être posées sans perte.

Toutes utilisent `onDelete: SetNull` (sauf `Notification`, en `Cascade`). Le
choix est délibéré : si un compte est supprimé, **l'historique doit survivre**.
Une ligne d'audit ou un changement de statut ne doit pas disparaître parce que
son auteur n'existe plus.

Vérifié :

```
Avis vers un utilisateur inexistant    → refusé par la base
Litige assigné à un agent inexistant   → refusé par la base
Zone vers une ville inexistante        → refusé par la base

Utilisateur supprimé → ligne d'historique conservée, auteur remis à NULL
```

---

## 7. Recherche géographique

### Le constat : PostGIS n'est pas disponible

```sql
SELECT * FROM pg_available_extensions WHERE name = 'postgis';  -- 0 ligne
```

L'extension n'est **pas installée** sur ton PostgreSQL — elle n'est même pas
disponible à l'installation. Le `CREATE EXTENSION` du fichier de migration
`000001_init_postgis` n'a donc jamais pu s'exécuter.

### La solution retenue

Plutôt que d'imposer une dépendance système, la recherche procède en deux temps
(`zones.service.ts`) :

1. **pré-filtre par rectangle**, que PostgreSQL résout avec le nouvel index
   `(latitude, longitude)` — c'est lui qui évite de parcourir toute la table ;
2. **distance exacte** par la formule de haversine sur les quelques lignes
   restantes, pour couper les coins du rectangle.

Le résultat est **identique** à celui de PostGIS ; seule la montée en charge
diffère (PostGIS resterait préférable sur des millions de zones). Le jour où
l'extension sera disponible, seule cette méthode change.

Nouvelle route publique : `GET /zones/nearby?latitude=…&longitude=…&radiusKm=…`,
triée de la plus proche à la plus lointaine.

Vérifié — Cocody est à 5,42 km du Plateau :

```
rayon 3 km  depuis le Plateau → aucune zone
rayon 10 km depuis le Plateau → Cocody, 5.42 km
latitude 999                  → refusée
```

Cinq tests unitaires (`tests/unit/geo.spec.ts`) valident la formule contre des
distances réelles, dont un qui vérifie que **le rectangle de pré-filtre englobe
bien le cercle** — s'il était trop petit, des zones valides disparaîtraient
silencieusement des résultats.

---

## 8. Index ajoutés

| Index | Requête concernée |
|---|---|
| `Review.targetId` | avis publics d'un prestataire |
| `Notification.userId` | notifications d'un utilisateur |
| `Dispute.assignedTo` | litiges d'un agent (CDC §4.5) |
| `ExportJob.requestedBy` | exports d'un demandeur |
| `ChatMessage.createdAt` | pagination d'une conversation |
| `ProviderProfile.availabilityStatus` et `score` | critères cités au CDC §4.3 |
| `Zone.cityId` et `(latitude, longitude)` | recherche par ville et par rayon |
| `ReviewReport.status`, `DisputeMessage.internalOnly` | nouveaux filtres |

---

## 9. Nouvelles routes

| Route | Rôle |
|---|---|
| `GET /zones/nearby` | recherche par rayon (public) |
| `POST /admin/disputes/:id/files` | rattacher une preuve à un litige |
| `POST /providers/me/unavailabilities` | déclarer une absence |
| `DELETE /providers/me/unavailabilities/:id` | annuler une absence |
| `GET /providers/:id/unavailabilities` | absences annoncées (public) |

`POST /admin/disputes/:id/messages` accepte désormais `internalOnly`.

**96 routes** au total (contre 91 après le Lot 3).

---

## 10. Vérifications effectuées

`typecheck` API ✅ · `build` API ✅ · `typecheck` front ✅
· `vitest` : **107 tests passent** (102 + 5 nouveaux sur la géo) ✅

Base jetable `prestgo_lot4` (créée puis supprimée) : **42 tables, 60 clés
étrangères, 116 index**.

| # | Scénario | Résultat |
|---|---|---|
| 1 | Recherche par rayon | ✅ 3 km exclut, 10 km inclut à 5,42 km, latitude invalide refusée |
| 2 | `Zone.city` est une vraie relation | ✅ Cocody → Abidjan |
| 3 | Litige vu du back-office | ✅ message + note interne |
| 4 | Même litige vu du client | ✅ **message seul** |
| 5 | Preuve rattachée à un litige | ✅ rejouable sans doublon |
| 6 | Indisponibilités | ✅ chevauchement et dates incohérentes refusés, visible en public |
| 7 | Références fantômes | ✅ **les 3 refusées par la base** |
| 8 | Suppression d'un utilisateur | ✅ historique conservé, auteur à `NULL` |

---

## 11. Ce qui a été fait sur ta base

Tout est déjà appliqué :

- schéma synchronisé (`prisma db push`) et client Prisma régénéré ;
- `Zone.cityId` nettoyé puis rebranché sur la ville Abidjan ;
- seed relancé : Abidjan et Yamoussoukro créées.

**Ta base : 42 tables, 60 clés étrangères.** Rien à faire de ton côté.

---

## 12. Ce que le Lot 4 ne règle PAS

- **PostGIS** : indisponible sur cette instance. Pour l'activer un jour, il
  faudra installer l'extension côté PostgreSQL, puis remplacer `searchNearby`.
- **Recherche textuelle** : `ILIKE '%…%'` sur les noms n'est toujours pas
  indexable. Il faudrait l'extension `pg_trgm`, à vérifier comme pour PostGIS.
- **Migrations versionnées** : le projet applique le schéma par `db push`, sans
  historique de migrations. Acceptable en développement, **à reprendre avant
  toute mise en production**.
- **Interfaces** des nouveautés : le back-office n'affiche pas encore les
  preuves de litige, la case « commentaire interne » ni les indisponibilités.
  L'API est prête, l'écran reste à faire.
- **`sort`** : toujours validé mais pas appliqué.
- **Tests** : la majorité des anciens fichiers restent factices. → **Lot 5**
