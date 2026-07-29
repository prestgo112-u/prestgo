# US4 — Gérer le catalogue, les zones et les disponibilités

> Documentation de l'implémentation de l'US4. Objectif : les admins gèrent les **catégories** et
> **types de service**, les **zones** géographiques couvertes, et les **disponibilités** des
> prestataires.

**Statut : ✅ Terminée et testée en vrai** (backend + back-office, tâches T068 → T077).

---

## 1. Ce qui a été implémenté

### Backend (`apps/api`, module `catalog/catalog.module.ts`)
| Domaine | Service | Contrôleur |
|---|---|---|
| Catalogue (catégories, types de service) | `catalog/catalog.service.ts` | `catalog/admin-catalog.controller.ts` |
| Zones | `zones/zones.service.ts` | `zones/admin-zones.controller.ts` |
| Disponibilités | `availability/availability.service.ts` | `availability/admin-availability.controller.ts` |

Nouveaux modèles : `CatalogCategory`, `ServiceType`, `ProviderService`, `ServicePack`, `Zone`,
`ProviderZone`, `Address`, `ProviderAvailability`.

### Back-office (`apps/admin`)
| Écran | Fichier |
|---|---|
| Catalogue (catégories + types) | `features/catalog/CatalogPage.tsx`, `ServiceTypeEditor.tsx` |
| Zones | `features/zones/ZonesPage.tsx`, `ZoneEditor.tsx` |
| Disponibilités d'un prestataire | `features/providers/ProviderAvailabilityPanel.tsx` (intégré à la page détail prestataire) |

---

## 2. Explication des parties importantes

### 2.1 Désactiver plutôt que supprimer

Dans le catalogue, on ne **supprime** pas une catégorie ou un type de service : on les **désactive**
(`active = false`). Ainsi ils disparaissent des choix pour les nouveaux usages, mais restent visibles
dans l'historique (missions passées, etc.). C'est le champ `active` qui pilote ça.

### 2.2 Validation d'une zone active — `zones.service.ts`

Règle métier : une zone **active** doit avoir des coordonnées et un rayon positif (sinon elle ne
sert à rien géographiquement). Une zone **inactive** peut rester incomplète.

```ts
private validate(active, latitude, longitude, radiusKm) {
  if (!active) return;
  if (latitude == null || longitude == null || radiusKm == null || radiusKm <= 0) {
    throw new BadRequestException("Une zone active exige latitude, longitude et un rayon positif");
  }
}
```

> **PostGIS n'est pas nécessaire ici** : on stocke latitude/longitude/rayon comme de simples
> nombres. PostGIS ne servirait qu'à la *recherche* géographique (trouver les prestataires dans un
> rayon), qui n'est pas au programme de cette US.

### 2.3 Pas de chevauchement de créneaux — `availability.service.ts`

Un prestataire ne peut pas avoir deux créneaux qui se chevauchent le même jour. Comme les heures
sont au format `"HH:MM"` (deux chiffres), on peut les comparer comme du texte :

```ts
// deux créneaux se chevauchent si l'un commence avant que l'autre finisse
const overlaps = sameDay.some((slot) => dto.startTime < slot.endTime && slot.startTime < dto.endTime);
```

On vérifie aussi que l'heure de fin est après l'heure de début. Deux créneaux **adjacents**
(ex. 09:00–12:00 puis 12:00–14:00) sont autorisés.

### 2.4 Rattacher au prestataire

Le modèle `ProviderService` relie un prestataire à un type de service (il « propose » ce service),
et `ProviderZone` relie un prestataire à une zone (relation plusieurs-à-plusieurs). Les
disponibilités (`ProviderAvailability`) appartiennent directement au prestataire.

---

## 3. Données de démonstration

Le seed crée :
- une catégorie **Plomberie** avec le type **Réparation de fuite** ;
- une zone active **Cocody** (Abidjan, rayon 5 km) ;
- un créneau de disponibilité pour **Kofi** (lundi 09:00–12:00).

---

## 4. Comment tester dans le navigateur

Connexion `admin@prestgo.test` / `prestgo123!`, puis :
- **Catalogue** → ajouter une catégorie, ajouter un type de service, désactiver/réactiver.
- **Zones** → ajouter une zone (essaie une zone active sans coordonnées : refusée), désactiver.
- **Prestataires** → Examiner un prestataire → section **Disponibilités** en bas : ajouter un
  créneau (essaie un chevauchement : refusé), supprimer.

---

## 5. Limites connues

- Les **packs de service** (`ServicePack`) et les **adresses** (`Address`) ont leurs modèles en base
  mais pas encore d'écran dédié (pourront être ajoutés au besoin).
- Pas de recherche géographique (nécessiterait PostGIS — hors périmètre US4).
- `T068`, `T070` sont des placeholders ; `T069` teste réellement les règles (validation zone,
  chevauchement de créneaux).
