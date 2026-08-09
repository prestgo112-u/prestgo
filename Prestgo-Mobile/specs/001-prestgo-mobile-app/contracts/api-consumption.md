# Contrat — Consommation de l'API : 90 opérations → dépôts et écrans

**Portée** : `lib/features/*/data/`. Chaque ligne est **une** méthode de dépôt.
Aucune opération ne doit être appelée depuis un écran ou un provider de présentation.

Base configurée : `https://<hôte>/api/v1` — **le préfixe est déjà dans la base**,
aucun chemin ne le répète. « Auth » = jeton requis.

Colonne « Lot » : lot de livraison du §9 du cahier des charges (L0 socle, L1 auth,
L2 client cœur, L3 suivi client, L4 push, L5 onboarding prestataire, L6 espace
prestataire, L7 compléments, L8 hors ligne).

---

## `auth_repository` — `features/auth/data` (L1)

| # | Méthode | Chemin | Auth | Écran | Exigences |
|---|---|---|---|---|---|
| 1 | POST | `/auth/register` | non | C3 Mot de passe | FR-001 |
| 2 | POST | `/auth/otp/send` | non | C4 Code ; changement de contact ; connexion par téléphone | FR-002 |
| 3 | POST | `/auth/otp/verify` | non | C4 Code ; **connexion par téléphone si `purpose=login`** | FR-003, FR-004, FR-005 |
| 4 | POST | `/auth/login` | non | Connexion | FR-005, FR-006 |
| 5 | POST | `/auth/refresh` | non | Intercepteur (socle L0) | FR-008 |
| 6 | POST | `/auth/logout` | non* | Déconnexion | FR-011 |
| 7 | POST | `/auth/forgot-password` | non | Mot de passe oublié | FR-010 |
| 8 | POST | `/auth/reset-password` | non | Réinitialisation | FR-010 |

\* déclarée publique, mais **envoyer quand même** l'en-tête d'autorisation **et** le
jeton de renouvellement dans le corps, pour fermer la bonne session.

Formes de réponse à ne pas confondre : `otp/verify` renvoie
`{ verified, activated }` pour `phone_verification` / `email_verification`, mais
**un couple de jetons** pour `purpose: "login"`.

---

## `me_repository` — `features/profile/data` (L1)

| # | Méthode | Chemin | Écran | Exigences |
|---|---|---|---|---|
| 9 | GET | `/me` | Démarrage, aiguillage, Profil | FR-013, FR-016 |
| 10 | PATCH | `/me` | Profil — édition (déclenche un code si contact modifié) | FR-017 |
| 11 | POST | `/me/password` | Changer mon mot de passe (session conservée) | FR-018 |
| 12 | DELETE | `/me` | Désactiver mon compte (corps `{ password }`) | FR-012 |

## `address_repository` — `features/profile/data` (L2)

| # | Méthode | Chemin | Pagination | Exigences |
|---|---|---|---|---|
| 13 | GET | `/me/addresses` | non | FR-019 |
| 14 | POST | `/me/addresses` | — | FR-019, FR-020 |
| 15 | PATCH | `/me/addresses/{id}` | — | FR-019 |
| 16 | DELETE | `/me/addresses/{id}` | — | FR-019 |
| 17 | POST | `/me/addresses/{id}/default` | — | FR-020 |

`DELETE` renvoie soit `{ removed: true }`, soit `{ removed: false, archived: true, reason }` :
les deux sont des succès, le message diffère.
`POST .../default` renvoie **la liste complète à jour** (économie d'un appel).

## `favorites_repository` — `features/profile/data` (L7)

| # | Méthode | Chemin | Notes | Exigences |
|---|---|---|---|---|
| 18 | GET | `/me/favorites` | non paginé | FR-021 |
| 19 | POST | `/me/favorites/{providerId}` | idempotent | FR-021 |
| 20 | DELETE | `/me/favorites/{providerId}` | idempotent, jamais d'erreur métier | FR-021 |

## `settings_repository` — `features/../core/settings` (L0)

| # | Méthode | Chemin | Notes | Exigences |
|---|---|---|---|---|
| 21 | GET | `/settings/public` | public, appelé une fois au démarrage | FR-094 |

---

## `catalog_repository` / `search_repository` — `features/search/data` (L2)

| # | Méthode | Chemin | Auth | Pagination | Exigences |
|---|---|---|---|---|---|
| 22 | GET | `/categories` | non | non | FR-023 |
| 23 | GET | `/zones` | non | non | FR-023, FR-054 |
| 24 | GET | `/zones/nearby` | non | non | FR-023 |
| 25 | GET | `/providers/search` | non | **oui** (limit ≤ 50) | FR-022 à FR-026 |
| 26 | GET | `/providers/{id}/public` | non | — | FR-027 |
| 27 | GET | `/providers/{id}/service-packs` | non | non | *non consommé* (redondant avec la fiche) |
| 28 | GET | `/providers/{id}/availabilities` | non | non | fiche publique |
| 29 | GET | `/providers/{id}/unavailabilities` | non | non | relecture de **mes** absences (L6) |
| 30 | GET | `/providers/{id}/reviews` | non | **oui** (`data` = tableau) | FR-027 |

---

## `booking_repository` / `mission_repository` — `features/booking`, `features/missions` (L2, L3, L6)

| # | Méthode | Chemin | Rôle | Exigences |
|---|---|---|---|---|
| 31 | POST | `/missions` | client — **`Idempotency-Key` obligatoire** | FR-029 à FR-035 |
| 32 | GET | `/me/missions` | client, paginé, `status` accepte une liste | FR-037 |
| 33 | GET | `/providers/me/missions` | prestataire, paginé, tri croissant | FR-038, FR-065 |
| 34 | GET | `/missions/{id}` | 2 rôles | FR-039, FR-040 |
| 35 | GET | `/missions/{id}/history` | 2 rôles, non paginé | FR-039, FR-070 |
| 36 | POST | `/missions/{id}/accept` | prestataire (`pending_provider`) | FR-041, FR-046 |
| 37 | POST | `/missions/{id}/refuse` | prestataire (`pending_provider`), motif | FR-041, FR-044 |
| 38 | POST | `/missions/{id}/start` | prestataire (`confirmed`), fenêtre | FR-042 |
| 39 | POST | `/missions/{id}/complete` | prestataire (`in_progress`) | FR-041 |
| 40 | POST | `/missions/{id}/cancel` | 2 rôles, motif | FR-044, FR-045 |

`status` accepte une **liste séparée par des virgules** (`?status=completed,closed`)
sur les opérations 32 et 33 : les onglets se construisent en un seul appel. Une liste
contenant un statut inconnu est refusée en bloc.

## `reschedule_repository` — `features/missions/data` (L3, L6)

| # | Méthode | Chemin | Notes | Exigences |
|---|---|---|---|---|
| 41 | GET | `/missions/{id}/reschedules` | historique complet, non paginé | FR-047 |
| 42 | POST | `/missions/{id}/reschedule` | `{ newDate (UTC), reason? }` | FR-047 |
| 43 | POST | `/missions/{id}/reschedule/{rid}/accept` | créneau **revalidé** à l'acceptation | FR-048 |
| 44 | POST | `/missions/{id}/reschedule/{rid}/reject` | `{ reason }` 3 à 500 | FR-044 |

## `review_repository` — `features/reviews/data` (L7)

| # | Méthode | Chemin | Notes | Exigences |
|---|---|---|---|---|
| 45 | POST | `/missions/{id}/review` | **client seul**, 409 = succès fonctionnel | FR-070, FR-071 |
| 46 | GET | `/me/reviews` | paginé | FR-072 |
| 47 | POST | `/reviews/{id}/report` | 20 par jour | FR-073 |

## `messaging_repository` — `features/messaging/data` (L3)

| # | Méthode | Chemin | Pagination | Exigences |
|---|---|---|---|---|
| 48 | GET | `/me/threads` | **oui** | FR-074 |
| 49 | GET | `/me/threads/unread-count` | — | FR-074 |
| 50 | GET | `/missions/{id}/thread` | — | FR-039 |
| 51 | GET | `/messages/threads/{id}/messages` | **oui**, tri croissant par défaut | FR-075 |
| 52 | POST | `/messages/threads/{id}/messages` | — | FR-076, FR-077 |
| 53 | PATCH | `/messages/threads/{id}/read` | — | FR-079 |

## `notification_repository` / `device_repository` — `features/notifications/data`, `core/push` (L3, L4)

| # | Méthode | Chemin | Pagination | Exigences |
|---|---|---|---|---|
| 54 | GET | `/me/notifications` | **oui** (`unread=true|false`) | FR-081 |
| 55 | GET | `/me/notifications/unread-count` | — | FR-082 |
| 56 | PATCH | `/me/notifications/{id}/read` | — idempotent | FR-081 |
| 57 | POST | `/me/notifications/read-all` | — | FR-081 |
| 58 | GET | `/me/devices` | non | Réglages — appareils |
| 59 | POST | `/me/devices` | — idempotent, 30/jour | FR-084 |
| 60 | DELETE | `/me/devices/{token}` | — jeton **encodé** dans l'URL | FR-084 |

## `file_repository` — `core/files` (L0, utilisé par L3, L5, L6)

| # | Méthode | Chemin | Auth | Exigences |
|---|---|---|---|---|
| 61 | POST | `/files/upload` | oui — champ multipart **`file`**, jamais rejoué | FR-058, FR-076 |
| 62 | GET | `/files/{id}` | oui | métadonnées |
| 63 | GET | `/files/{id}/content` | **non si `public`**, oui sinon | FR-022, FR-098 |
| 64 | DELETE | `/files/{id}` | oui | retrait d'un envoi erroné |

---

## `provider_self_repository` — `features/provider_onboarding`, `features/provider_space` (L5, L6)

### Dossier

| # | Méthode | Chemin | Notes | Exigences |
|---|---|---|---|---|
| 65 | POST | `/providers/me` | 409 = profil existant → **traiter comme un succès** | FR-052 |
| 66 | GET | `/providers/me` | source unique de la checklist et du suivi | FR-051, FR-060 |
| 67 | PATCH | `/providers/me` | verrou en `pending_review` sauf `availabilityStatus` | FR-062, FR-066 |
| 68 | POST | `/providers/me/submit` | piloté par `canSubmit` ; `errors[].field` = lignes rouges | FR-060, FR-061, FR-063 |

### Offre

| # | Méthode | Chemin | Notes | Exigences |
|---|---|---|---|---|
| 69 | GET | `/providers/me/services` | non paginé, formules imbriquées | FR-067 |
| 70 | POST | `/providers/me/services` | retenir `data.id` pour la formule | FR-053 |
| 71 | PATCH | `/providers/me/services/{id}` | `active: false` = désactivation | FR-067 |
| 72 | POST | `/providers/me/service-packs` | exige `providerServiceId` | FR-053 |
| 73 | PATCH | `/providers/me/service-packs/{id}` | — | FR-067 |
| 74 | GET | `/providers/me/service-packs/{packId}/options` | non paginé | FR-067 |
| 75 | POST | `/providers/me/service-packs/{packId}/options` | chemin imbriqué | FR-067 |
| 76 | PATCH | `/providers/me/service-pack-options/{id}` | ⚠️ chemin **à plat** | FR-067 |

### Zones et agenda

| # | Méthode | Chemin | Notes | Exigences |
|---|---|---|---|---|
| 77 | GET | `/providers/me/zones` | non paginé — pré-cochage | FR-054 |
| 78 | PUT | `/providers/me/zones` | **remplacement intégral**, ≤ 15, contrôle atomique | FR-054 |
| 79 | GET | `/providers/me/availabilities` | miroir exact du PUT | FR-055 |
| 80 | PUT | `/providers/me/availabilities` | **remplacement intégral**, ≤ 50 créneaux | FR-055 |
| 81 | POST | `/providers/me/unavailabilities` | `{ startAt, endAt, reason? }` | FR-056 |
| 82 | DELETE | `/providers/me/unavailabilities/{id}` | appartenance vérifiée | FR-056 |

### Justificatifs et portfolio

| # | Méthode | Chemin | Notes | Exigences |
|---|---|---|---|---|
| 83 | GET | `/providers/me/documents` | `requiredTypes`, `missingTypes`, `current`, `documents` | FR-057 |
| 84 | POST | `/providers/me/documents` | ⚠️ repasse le dossier en vérification | FR-058, FR-059 |
| 85 | GET | `/providers/me/portfolio` | non paginé, trié par ordre d'affichage | FR-068 |
| 86 | POST | `/providers/me/portfolio` | ≤ 20, images seules, fichier → `public` | FR-068, FR-069 |
| 87 | PATCH | `/providers/me/portfolio/{id}` | pas de changement d'image | FR-068 |
| 88 | DELETE | `/providers/me/portfolio/{id}` | fichier ramené en `restricted` | FR-068 |

⚠️ Toutes les routes `/providers/me/*` répondent **403** tant que le profil
prestataire n'existe pas → renvoyer vers la création de profil.

## `dispute_repository` — `features/disputes/data` (L7)

| # | Méthode | Chemin | Notes | Exigences |
|---|---|---|---|---|
| 89 | POST | `/disputes` | 2 rôles, sur **leur** mission | FR-100 |
| 90 | GET | `/disputes/{id}` | commentaires internes jamais renvoyés | FR-100 |

---

## Invalidations après écriture (FR-050)

| Écriture | À invalider |
|---|---|
| `POST /missions` | missions du client, compteur de notifications, fils de discussion |
| Transitions de mission | détail de la mission, listes de missions, compteur de notifications |
| `POST /missions/{id}/review` | détail de la mission, mes avis |
| Profil / services / zones / agenda / documents prestataire | aperçu du dossier (la checklist en dépend) |
| `PATCH /me` | profil courant (et écran de vérification si un contact a changé) |
| `PATCH /messages/threads/{id}/read` | liste des fils, compteur global de messages |
