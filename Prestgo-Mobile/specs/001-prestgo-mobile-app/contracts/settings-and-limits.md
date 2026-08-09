# Contrat — Réglages serveur et plafonds applicatifs

**Portée** : `lib/core/settings/`.

## 1. Réglages lus à l'exécution — `GET /settings/public`

Route **publique**, appelée **une fois au démarrage**, résultat conservé en mémoire
pour la session. Elle expose exactement six clés (liste fermée) :

| Clé | Repli | Où l'utilisateur la ressent | Exigence |
|---|---|---|---|
| `missionMinLeadTimeMinutes` | 60 min | délai minimum de réservation | FR-032 |
| `missionCancellationNoticeHours` | 6 h | avertissement d'annulation tardive | FR-045 |
| `missionStartWindowMinutes` | 120 min | activation du bouton « Démarrer » | FR-042 |
| `missionPendingExpiryHours` | 24 h | compte à rebours d'une demande en attente | FR-043 |
| `missionAutoCloseDays` | 7 j | information de clôture automatique | — |
| `reviewsWindowDays` | 14 j | fenêtre de dépôt d'avis | FR-070 |

**Règles (porte G3)** :
1. Les valeurs de repli ne servent **que** si l'appel échoue (hors ligne, cache
   froid). Elles ne sont jamais la source de vérité une fois la route jointe.
2. Le service reste l'autorité finale : son message d'erreur est interpolé avec la
   valeur réellement en vigueur et prime sur l'affichage local.
3. Une modification faite au back-office ressort au prochain démarrage : ne pas
   figer la valeur dans un cache persistant longue durée.

Même principe pour `expiresInMinutes` renvoyé par l'envoi d'un code de
vérification : le compte à rebours utilise la valeur reçue, pas une constante.

## 2. Plafonds de saisie (constantes applicatives)

Vérifiés dans le code du service, centralisés dans `core/settings/app_constants.dart`.

### Authentification

| Constante | Valeur |
|---|---|
| Durée du jeton d'accès | 15 min |
| Durée du jeton de renouvellement | 7 j |
| Longueur du code de vérification | 6 chiffres exactement |
| Durée de vie d'un code | 10 min (valeur reçue prioritaire) |
| Tentatives maximales par code | 5 |
| Durée du jeton de réinitialisation | 30 min |
| Longueur du mot de passe | 8 à 128, au moins une lettre et un chiffre |
| Format de téléphone | `^\+?[0-9\s-]{8,20}$` |
| Longueur du jeton de réinitialisation | ≥ 10 caractères (64 en pratique) |

### Plafonds de contenu

| Constante | Valeur |
|---|---|
| Adresses par compte | 10 |
| Zones par prestataire | 15 |
| Réalisations de portfolio | 20 |
| Créneaux hebdomadaires | 50 |
| Options par réservation | 10 |
| Pièces jointes par message | 3 |
| Longueur d'un message | 1 à 4000 |
| Instructions de réservation | ≤ 500 |
| Commentaire d'avis | ≤ 1000 |
| Motif (refus, annulation, signalement) | 3 à 500 |
| Présentation prestataire (`bio`) | ≤ 2000 |
| Nom public | 2 à 120 |
| Titre de service | 3 à 150 |
| Titre de formule / option | 2 à 150 |
| Durée d'une formule | 5 à 1440 min |
| Durée d'une option | 0 à 1440 min |
| Années d'expérience | 0 à 70 |
| Taille de fichier | 10 Mo |
| Types de fichier acceptés | `image/jpeg`, `image/png`, `image/webp`, `application/pdf`, `text/plain`, `text/csv` |

### Pagination et recherche

| Constante | Valeur |
|---|---|
| Taille de page par défaut | 20 |
| Taille de page maximale | 100 (50 sur la recherche) |
| Rayon de recherche par défaut | 10 km |
| Rayon de recherche maximal | 50 km (minimum 1 km) |
| Note minimale | 0 à 5 |

### Idempotence et débits

| Constante | Valeur |
|---|---|
| Durée de vie d'une clé d'idempotence | 10 min |
| Réservations par heure | 10 |
| Enregistrements d'appareil par jour | 30 |
| Signalements d'avis par jour | 20 |
| Connexions par minute | 10 |
| Inscription / envoi de code / mot de passe oublié | 5 par minute |
| Renouvellement / vérification de code / changement de mot de passe | 30 par minute |

### Divers

| Constante | Valeur |
|---|---|
| Devise | `XOF`, formateur unique, locale `fr_CI`, sans décimale |
| Premier jour de la semaine | 0 = dimanche, 6 = samedi |
| Heures d'agenda | chaînes `HH:MM`, **sans conversion de fuseau** |
| Dates d'intervention | envoyées en **UTC** (ISO 8601) |

## 3. Usage attendu

- Chaque plafond ci-dessus est appliqué **avant l'envoi** (FR-090, SC-013) : action
  d'ajout indisponible au plafond avec motif affiché, plutôt qu'un échec après saisie.
- Aucun de ces plafonds n'est dupliqué dans un écran : ils sont lus depuis les
  constantes centralisées.
- Les six réglages du §1 ne sont **jamais** copiés dans une constante d'écran.
