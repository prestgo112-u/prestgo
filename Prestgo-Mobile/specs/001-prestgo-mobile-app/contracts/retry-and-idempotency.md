# Contrat — Politique de rejeu et idempotence

**Portée** : `lib/core/api/retry_policy.dart`, `lib/core/api/idempotency.dart`.

## 1. Politique par type de requête (porte G4)

| Type | Rejeu automatique | Justification |
|---|---|---|
| Lectures `GET` | ✅ 2 tentatives, attente 500 ms puis 1,5 s, **uniquement** sur erreur réseau et 502/503/504 | sans effet de bord |
| `POST /missions` | ✅ **uniquement avec `Idempotency-Key`** | protection serveur, cf. §2 |
| Écritures idempotentes par construction (`PUT /providers/me/zones`, `PUT /providers/me/availabilities`, `POST`/`DELETE /me/favorites/{id}`, `PATCH /me/notifications/{id}/read`, `POST /me/devices`) | ✅ 1 tentative | résultat indépendant du nombre d'appels |
| Transitions de mission (`accept`, `refuse`, `start`, `complete`, `cancel`) | ❌ **jamais** | un rejeu après succès non reçu renvoie « Action impossible depuis le statut … », incompréhensible pour l'utilisateur |
| `POST /missions/{id}/review` | ❌ | un rejeu renvoie 409 « avis déjà déposé » → **traiter ce 409 comme un succès** et afficher l'avis |
| `POST /messages/threads/{id}/messages` | ❌ | créerait des doublons (aucune clé d'idempotence) → bulle en échec + renvoi manuel |
| `POST /files/upload` | ❌ | corps multipart à usage unique ; un rejeu enverrait un corps vide |
| `POST /auth/*` | ❌ | débits serrés (5 à 10 par minute) : un rejeu déclencherait un 429 |
| Toute réponse **429** | ❌ | message d'attente + désactivation temporaire de l'action |

**Après une transition dont la réponse n'est pas parvenue** : recharger le détail de
la mission et laisser l'utilisateur décider (FR-046). Ne jamais présumer du résultat.

## 2. `Idempotency-Key` sur `POST /missions`

Mécanique côté service :
- En-tête **facultatif** — sans lui, aucune protection : un rejeu crée une seconde
  mission. **L'envoyer systématiquement.**
- Clé portée par le triplet (utilisateur, opération, clé), durée de vie **10 minutes**.
- Rejeu d'une clé **terminée** → réponse d'origine, message « Réservation déjà
  enregistrée ». Rien n'est recréé.
- Rejeu d'une clé **encore en vol** → **409** « Une requête identique est déjà en
  cours de traitement ».
- En cas d'échec **métier**, la clé est **libérée** : l'utilisateur peut corriger et
  réessayer.

Règle applicative :

> La clé est un UUID v4 généré **une seule fois, à l'affichage du récapitulatif**, et
> conservée dans l'état de l'écran. Toutes les confirmations — y compris les rejeux
> après coupure réseau — réutilisent **cette même clé**. Une nouvelle clé n'est
> générée que si l'utilisateur **modifie le contenu** de la réservation (formule,
> options, date, adresse) ou repart d'un nouveau brouillon.

⚠️ Ne jamais générer la clé dans une méthode de construction de widget : chaque
reconstruction produirait une clé neuve et annulerait la protection.

## 3. Séquence exacte de confirmation d'une réservation

```
1. Générer la clé une fois, à l'affichage du récapitulatif.
2. Envoyer avec l'en-tête Idempotency-Key.
3. Coupure réseau ou délai dépassé ?
     → réessayer AVEC LA MÊME CLÉ (2 tentatives, attente 1 s puis 3 s)
       • 201 « Réservation créée »            → succès
       • 200 « Réservation déjà enregistrée » → succès (le premier appel était passé)
       • 409 « déjà en cours de traitement »  → attendre 2 s, réessayer (2 fois max),
                                                puis recharger mes missions —
                                                la mission existe probablement
4. Erreur métier 400 (créneau, adresse, zone, option) ?
     → NE PAS réessayer. Corriger, puis repartir avec une NOUVELLE clé
       (le contenu a changé).
5. 429 ?
     → NE PAS réessayer. Message « limite atteinte », bouton désactivé.
```

Le 409 « déjà en cours de traitement » ne doit **jamais** être présenté comme une
erreur : l'indicateur de chargement reste affiché.

## 4. Renouvellement de session et rejeu

- Un seul renouvellement en vol ; les requêtes concurrentes attendent le même
  résultat.
- Une requête n'est rejouée **qu'une fois** après renouvellement (marqueur porté par
  la requête) : un second 401 met fin à la session.
- Les routes d'authentification sont exclues du renouvellement et du rejeu.
- L'appel de renouvellement passe par une instance HTTP **sans** l'intercepteur
  d'authentification (sinon récursion infinie).
- Échec du renouvellement → purge du stockage sécurisé et de la base locale, retour
  à l'écran de connexion.
- Les envois de fichiers ne passent pas par le rejeu automatique : leur 401 remonte à
  l'écran, qui propose une reprise explicite.

## 5. Mode hors ligne

- Aucune écriture n'est acceptée hors ligne, **aucune** action n'est mise en file
  pour être rejouée plus tard (FR-097).
- Les lectures servent le cache avec l'âge affiché.
- Au retour du réseau, les données de l'écran courant sont rechargées (FR-099).
