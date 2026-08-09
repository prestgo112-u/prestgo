# Contrat — Routes de navigation et gardiens

**Portée** : `lib/app/router.dart`, `lib/app/routes.dart`.

Un **unique** `redirect` porte le gardien d'authentification et l'aiguillage par
rôle. Aucun écran ne réimplémente de contrôle d'accès.

## 1. Table des routes

### Publiques (accessibles sans session)

| Chemin | Écran | Notes |
|---|---|---|
| `/` | Accueil / recherche | consultable sans compte |
| `/search` | Résultats et filtres | paramètres de requête portés par l'URL |
| `/providers/:id` | Fiche prestataire publique | un seul chargement |
| `/providers/:id/reviews` | Tous les avis | paginé |
| `/login` | Connexion (email ou téléphone) | — |
| `/login/phone` | Connexion par code | motif `login` obligatoire |
| `/register` | Inscription (canal → identité → mot de passe) | — |
| `/verify?target=&purpose=` | Saisie du code à 6 chiffres | sert l'activation **et** la vérification d'un contact modifié |
| `/forgot-password` | Demande de réinitialisation | message neutre systématique |
| `/reset-password` | Saisie / collage du jeton + nouveau mot de passe | pas de lien profond (écart n°3) |

### Espace client (session requise)

| Chemin | Écran |
|---|---|
| `/home` | Accueil connecté |
| `/booking/new?providerId=&packId=` | Brouillon de réservation (formule, options) |
| `/booking/schedule` | Choix de la date et de l'heure |
| `/booking/summary` | Récapitulatif — **génération de la clé d'idempotence** |
| `/missions` | Mes missions (onglets par statut) |
| `/missions/:id` | Détail de mission (2 rôles) |
| `/missions/:id?tab=reschedule` | Détail, onglet Reports |
| `/missions/:id?tab=review` | Détail, dépôt d'avis |
| `/missions/:id/history` | Frise chronologique |
| `/missions/:id/dispute` | Ouverture de litige |
| `/favorites` | Mes favoris |
| `/reviews` | Mes avis |

### Commun aux deux rôles (session requise)

| Chemin | Écran |
|---|---|
| `/threads` | Onglet Messagerie |
| `/threads/:id` | Conversation |
| `/notifications` | Centre de notifications |
| `/profile` | Mon profil |
| `/profile/edit` | Édition du profil |
| `/profile/password` | Changer mon mot de passe |
| `/profile/addresses` | Carnet d'adresses |
| `/profile/addresses/new`, `/profile/addresses/:id` | Adresse (avec sélecteur de position) |
| `/profile/devices` | Appareils connectés |
| `/profile/deactivate` | Désactivation du compte (double confirmation) |

### Onboarding prestataire (session requise)

| Chemin | Écran |
|---|---|
| `/provider/onboarding` | Présentation du parcours (P1) |
| `/provider/onboarding/profile` | Création du profil public (P2) |
| `/provider/onboarding/checklist` | **Hub** de complétude (P8) |
| `/provider/onboarding/status` | Suivi du dossier (P9) |

### Espace prestataire (session requise, dossier approuvé)

| Chemin | Écran |
|---|---|
| `/provider` | Tableau de bord |
| `/provider/missions` | Planning et demandes |
| `/provider/profile` | Profil prestataire et disponibilité |
| `/provider/services` | Mes prestations (formules et options imbriquées) |
| `/provider/zones` | Zones d'intervention |
| `/provider/availabilities` | Agenda hebdomadaire |
| `/provider/unavailabilities` | Absences exceptionnelles |
| `/provider/documents` | Justificatifs |
| `/provider/portfolio` | Réalisations |

## 2. Gardien unique — logique de redirection

Entrées : état de session (jetons présents), profil courant (`Me`, servi par le
cache au démarrage), route demandée.

```
1. Route publique              → laisser passer, quelle que soit la session.
2. Route protégée sans session → /login, en MÉMORISANT la route demandée
                                 (retour après authentification, FR-028).
3. Session présente, profil non chargé → écran de démarrage, puis réévaluation.
4. Session présente :
     hasProviderProfile == false                → routes client ; /provider/** → /home
     validationStatus == profile_incomplete     → /provider/onboarding/checklist
     validationStatus == pending_review         → /provider/onboarding/status
                                                  (espace client accessible)
     validationStatus == changes_requested      → /provider/onboarding/status
     validationStatus == rejected               → /provider/onboarding/status
     validationStatus == suspended              → /provider/onboarding/status
     validationStatus == approved               → /provider/** autorisé
5. Compte non actif → /login avec purge.
```

Règles associées :
- Le champ `roles` (rôles d'administration, vide pour les comptes ordinaires) n'entre
  **jamais** dans cette décision.
- L'accès à l'espace client dépend uniquement de `status == active`, jamais de
  `hasClientProfile`.
- Un compte à double casquette bascule entre les deux espaces **sans reconnexion**
  (entrée de menu explicite) ; les deux espaces ne sont jamais affichés en même temps.
- Le retour après authentification restaure la route mémorisée, y compris ses
  paramètres (typiquement la fiche prestataire d'où « Réserver » a été appuyé).

## 3. Points d'entrée externes

| Origine | Comportement |
|---|---|
| Appui sur une notification poussée | routage par charge utile, cf. [push-payloads.md](./push-payloads.md) ; si la session est absente, mémoriser la destination et passer par `/login` |
| Application tuée puis ouverte par une notification | même routage, appliqué **après** l'initialisation du routeur |
| Appui sur une notification interne | **même fonction** de routage |
| Lien profond de réinitialisation | **non disponible** (aucun lien construit côté service) : l'écran `/reset-password` reste alimenté par saisie ou collage. La route est prête à recevoir un paramètre `token` le jour où un domaine sera arrêté |

## 4. Purge et changement de compte

À la déconnexion et à la désactivation : purge du stockage sécurisé, purge de la base
locale, recréation du conteneur d'état, puis `/login`. Aucune donnée du compte
précédent ne doit rester affichable (SC-012).
