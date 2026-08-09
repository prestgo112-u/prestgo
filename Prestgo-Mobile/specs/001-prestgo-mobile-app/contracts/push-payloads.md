# Contrat — Notifications : charges utiles et routage

**Portée** : `lib/core/push/`. La charge utile `data` d'un push est **identique** à
celle d'une notification interne : une seule fonction de routage sert les deux
(FR-083).

## 1. Formes de charge utile

| Origine | Charge utile `data` | Destination |
|---|---|---|
| Cycle de vie d'une mission | `{ missionId, type: "mission" }` | `/missions/:missionId` |
| Message de conversation | `{ missionId, threadId, type: "chat" }` | `/threads/:threadId` |
| Demande de report | `{ missionId, rescheduleId, type: "reschedule" }` | `/missions/:missionId?tab=reschedule` |
| Avis reçu | `{ missionId, reviewId, type: "review" }` | `/missions/:missionId?tab=review` |
| Type inconnu ou absent | — | `/notifications` |

Le routage doit **tolérer** un type inconnu (nouveau code émis par le service) et
retomber sur le centre de notifications plutôt que d'échouer.

## 2. Codes d'évènement émis par le service

`mission.created`, `mission.accepted`, `mission.refused`, `mission.started`,
`mission.completed`, `mission.cancelled`, `mission.expired`, `mission.reminder`,
`mission.reschedule.requested`, `mission.reschedule.accepted`, `review.received`,
`review.request`, `provider.approved`, `provider.changes_requested`,
`provider.rejected`, `dispute.opened`, `dispute.message`, `dispute.decided`,
`chat.message`.

Les trois codes `provider.*` sont le **bon signal** pour recharger le dossier
prestataire (aucun flux temps réel n'existe sur son état).

## 3. Trois points d'entrée à câbler

| Situation | Comportement attendu |
|---|---|
| Application au **premier plan** | bannière interne (notification locale sur Android) + rafraîchissement des compteurs et de l'écran concerné s'il est affiché ; **pas** de navigation forcée |
| Application en **arrière-plan**, notification touchée | routage immédiat |
| Application **tuée**, ouverte par la notification | routage **après** initialisation du routeur (message initial) |

## 4. Cycle de vie du jeton d'appareil

| Moment | Action |
|---|---|
| Après chaque connexion réussie | demander l'autorisation, lire le jeton, l'enregistrer, le mémoriser localement |
| Au démarrage sur session restaurée | ré-enregistrer (idempotent — garantit la réaffectation après réinstallation ou changement de compte) |
| Sur changement de jeton | désenregistrer l'ancien, enregistrer le nouveau |
| **Avant** la déconnexion | désenregistrer — l'opération exige une session valide |
| Après désactivation du compte | rien à faire côté service (tous les jetons sont désactivés) ; purger la mémoire locale |

⚠️ Le jeton identifie une **installation**, pas un compte : sur un téléphone prêté,
le service réaffecte le jeton au nouveau compte. C'est pourquoi l'enregistrement a
lieu **à chaque connexion**, pas seulement à la première installation.

Le jeton passe dans le chemin d'URL au désenregistrement : il doit être **encodé**.
L'opération est idempotente et ne renvoie jamais d'erreur métier.

## 5. Regroupement et limites

- Le service regroupe les push de messagerie à **un par fil et par minute** ; au-delà,
  seule la notification interne est créée. L'écran de messagerie ne doit donc pas
  dépendre du push pour être à jour (rafraîchissement au retour au premier plan).
- L'auteur d'une action n'est **jamais** notifié de sa propre action : ne pas attendre
  de push de confirmation.
- Un refus d'autorisation ne bloque aucun parcours ; le centre de notifications reste
  le canal de référence, et un rappel est proposé dans les réglages de l'application.
- Débit d'enregistrement d'appareil : 30 par jour.

## 6. Limite de vérification connue

Aucun fournisseur d'envoi n'est configuré sur l'environnement de développement : les
charges utiles ci-dessus sont établies à partir des appels d'évènements du code du
service. Le routage se développe et se teste avec des charges **simulées** injectées
dans la fonction de routage ; la validation en conditions réelles nécessite un
environnement doté d'identifiants d'envoi.
