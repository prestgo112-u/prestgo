# Lot 3 — Compléter l'API

**Date :** 19 juillet 2026
**Périmètre :** `apps/api` uniquement (aucun changement côté back-office React)
**Origine :** audit de conformité au cahier des charges v1.2 (§8 Catalogue des API)
**Prérequis :** [Lot 0](Lot0-Securite-socle.md) · [Lot 1](Lot1-Fonctionnel-bloquant.md) · [Lot 2](Lot2-Ecrans-manquants.md)

---

## 1. Pourquoi ce lot

L'audit avait relevé **29 endpoints manquants** sur les 77 du CDC §8. Après les
Lots 1 et 2, il en restait une vingtaine, tous du même type : l'authentification
complète, et **toute la surface non-admin**.

C'est la partie que consommeront les futures applications client et prestataire.
Le CDC exclut ces *interfaces* de son périmètre (§1.3), mais il inclut
explicitement leurs *endpoints* dans son catalogue — le backend doit les exposer.

---

## 2. Authentification complète

Cinq routes manquaient. `auth.controller.ts` n'en avait que trois (login,
refresh, logout).

| Route | Rôle |
|---|---|
| `POST /auth/register` | créer un compte |
| `POST /auth/forgot-password` | demander un lien de réinitialisation |
| `POST /auth/reset-password` | changer son mot de passe avec ce lien |
| `POST /auth/otp/send` | envoyer un code à usage unique |
| `POST /auth/otp/verify` | vérifier ce code (et activer le compte) |

### 2.1 Deux nouvelles tables

`PasswordResetToken` et `OtpCode`. Elles ne figurent pas au CDC §7 mais sont
indispensables au parcours demandé.

**On n'y stocke que l'empreinte du secret, jamais sa valeur.** Si la base
fuitait, les jetons volés seraient inutilisables : le jeton envoyé à
l'utilisateur n'existe nulle part côté serveur.

> Choix technique : SHA-256 ici, alors que les mots de passe utilisent scrypt.
> Ces secrets sont aléatoires et de courte durée de vie — il n'y a pas de
> dictionnaire à craindre. Un hachage lent serait inutilement coûteux, et il
> tournerait à chaque tentative, ce qui ouvrirait un angle de déni de service.

### 2.2 Le parcours d'inscription

Un compte naît au statut `pending` (CDC §9.1) : il existe mais **ne peut pas se
connecter**. La vérification par OTP le fait passer en `active`.

Une nuance importante : on n'active **que depuis `pending`**. Un compte suspendu
par un administrateur ne doit pas pouvoir se réactiver tout seul en vérifiant
son téléphone.

### 2.3 Ne rien révéler

`POST /auth/forgot-password` renvoie **toujours la même réponse**, que le compte
existe ou non :

> « Si un compte existe pour cette adresse, un lien de réinitialisation a été envoyé. »

Sans cette précaution, la route deviendrait un moyen de découvrir quelles
adresses sont inscrites sur la plateforme (CDC §5.2). Même logique pour les
échecs de réinitialisation : un seul message pour « jeton inconnu », « déjà
utilisé » et « expiré ».

### 2.4 Protections

| Mesure | Détail |
|---|---|
| Mot de passe | 8 caractères minimum, **au moins une lettre et un chiffre** — sans cette règle, « aaaaaaaa » passerait |
| Jeton de réinitialisation | usage unique, 30 minutes, les demandes précédentes sont annulées |
| Code OTP | 6 chiffres, 10 minutes, **5 tentatives maximum** — sinon un code se devine en un million d'essais |
| Débit | 5 inscriptions/min, 5 demandes de réinitialisation/min, 5 envois d'OTP/min par IP |

### 2.5 Le point à connaître : comment récupérer le code en développement

Aucun email ni SMS n'est réellement envoyé (le transport arrive au Lot 5). Le
code serait donc introuvable, et la fonctionnalité intestable.

Solution : le secret est renvoyé dans la réponse **uniquement si la variable
`AUTH_EXPOSE_DEV_CODES=true` est présente**. Sans ce réglage explicite — donc
en production — il n'apparaît jamais dans une réponse HTTP ; il n'est visible
que dans les logs du serveur.

```bash
# apps/api/.env — pour tester les parcours OTP et mot de passe oublié
AUTH_EXPOSE_DEV_CODES=true
```

---

## 3. La surface non-admin

### 3.1 Vitrine publique (sans compte)

| Route | Contenu |
|---|---|
| `GET /categories` | catégories et types de service **actifs uniquement** |
| `GET /zones` | zones **actives**, sans les champs internes |
| `GET /providers/:id/service-packs` | formules actives d'un prestataire |
| `GET /providers/:id/availabilities` | agenda hebdomadaire |
| `GET /providers/:id/reviews` | avis **publiés** + note moyenne |

Le filtrage « actif » n'est pas cosmétique : une catégorie désactivée reste en
base pour l'historique des missions passées, mais elle ne doit plus apparaître
dans l'application publique. Idem pour un avis masqué par la modération.

### 3.2 Espace prestataire

| Route | Rôle |
|---|---|
| `POST /providers/me/service-packs` | créer une de ses formules |
| `PATCH /providers/me/service-packs/:id` | modifier une de ses formules |
| `PUT /providers/me/availabilities` | remplacer tout son agenda |

**Pourquoi `me` et pas un identifiant ?** C'est la protection centrale. Le
`ProviderContextService` retrouve le profil prestataire **à partir du token**,
jamais d'un identifiant fourni par le client. Un prestataire ne peut donc pas
modifier le catalogue d'un confrère en changeant un chiffre dans l'URL.

Deuxième niveau de contrôle : `createPackForProvider` vérifie que le
`providerServiceId` visé lui appartient bien.

> Détail de routage : les routes `me/...` sont déclarées **avant** `:id/...`
> dans chaque contrôleur, sinon le segment « me » serait capturé comme un
> identifiant de prestataire.

**Le `PUT` sur l'agenda** suit le CDC : l'appelant envoie l'agenda complet tel
qu'il doit être. Tous les créneaux sont validés — format, cohérence, absence de
chevauchement — **avant d'écrire quoi que ce soit**. Si le 5ᵉ créneau est
invalide, le prestataire ne se retrouve pas avec un agenda à moitié effacé.
C'est vérifié par un test (§5, scénario 14).

### 3.3 Routes des parties prenantes

| Route | Rôle |
|---|---|
| `GET /missions/:id/history` | historique des statuts et des reports |
| `GET /messages/threads/:id/messages` | lire sa conversation |
| `POST /messages/threads/:id/messages` | écrire dans sa conversation |
| `POST /disputes` | ouvrir un litige sur sa mission |
| `GET /disputes/:id` | suivre son litige |

Ces routes sont les plus sensibles du lot : elles donnent accès à des données
privées sans passer par une permission de back-office.

Le **`MissionAccessService`** centralise la règle : sont autorisés le client de
la mission, le prestataire qui la réalise, et les agents porteurs de la
permission admin correspondante. Tout autre compte connecté reçoit un **403
« Vous n'êtes pas partie à cette mission »**.

Sans ce contrôle, n'importe quel compte connecté aurait pu lire l'historique de
la mission d'un inconnu, écrire dans sa conversation ou ouvrir un litige à sa
place. Ce contrôle ne peut pas se faire côté client.

Autre garde-fou : un fil de discussion clos n'accepte plus de message — sinon
une conversation fermée après litige pourrait être relancée sans que personne
ne le voie.

---

## 4. Compléments admin

| Route | Note |
|---|---|
| `DELETE /admin/categories/:id` | **désactive**, ne supprime pas : les missions passées y font référence |
| `GET /admin/notification-templates` | chemin officiel du CDC (celui sous `/admin/notifications/templates` reste en place) |
| `PATCH /admin/notification-templates/:id` | le `code` n'est **pas** modifiable : c'est lui que le code applicatif utilise pour retrouver un modèle, le renommer casserait silencieusement les envois |
| `POST /admin/users/:id/notes` | note interne, stockée sur le profil client (CDC §7) |
| `GET /admin/verifications/documents/:id` | consulter un document soumis |

---

## 5. Vérifications effectuées

`typecheck` ✅ · `build` ✅ · `vitest` : **102 tests passent** ✅
**91 routes** mappées au démarrage (contre 57 avant le Lot 1).

Tout a été joué sur une **base jetable** (`prestgo_lot3`, créée puis supprimée).

| # | Scénario | Résultat |
|---|---|---|
| 1 | `/categories` et `/zones` sans aucun token | ✅ 200 |
| 2 | Inscription | ✅ compte créé au statut `pending` |
| 3 | Mot de passe « aaaaaaaa » | ✅ refusé |
| 4 | Email en doublon | ✅ refusé |
| 5 | Connexion avant activation | ✅ refusée |
| 6 | OTP : mauvais code puis bon code | ✅ refusé, puis « Compte activé » |
| 7 | Connexion après activation | ✅ 200 |
| 8 | Mot de passe oublié | ✅ même réponse pour un email inconnu ; jeton **à usage unique** ; ancien mot de passe invalidé |
| 9 | `GET /missions/:id/history` | ✅ client 200, prestataire 200, admin 200, **tiers 403**, sans token 401 |
| 10 | Écrire dans une conversation | ✅ parties 201, **tiers 403**, message vide refusé |
| 11 | Ouvrir un litige | ✅ client 201, **tiers 403** |
| 12 | Vitrine publique d'un prestataire | ✅ formules, agenda et avis lisibles sans compte |
| 13 | Prestataire crée une formule | ✅ ; un client reçoit « Ce compte n'a pas de profil prestataire » |
| 14 | Remplacement de l'agenda | ✅ ; chevauchement et heures incohérentes refusés, **agenda intact après refus** |
| 15 | Désactivation d'une catégorie | ✅ disparaît du catalogue public, reste visible en admin |
| 16 | Modèles de notification | ✅ liste et modification |
| 17 | Note interne utilisateur | ✅ horodatée |

Les scénarios 9, 10 et 11 sont les plus importants : ils prouvent que la surface
non-admin **n'est pas un contournement du contrôle d'accès**.

---

## 6. Ce qui a été fait de ton côté

Le schéma a déjà été appliqué à ta base de développement (`prisma db push`), et
le client Prisma régénéré. Les deux nouvelles tables (`PasswordResetToken`,
`OtpCode`) sont en place. **Rien à faire.**

Si tu veux tester les parcours OTP et mot de passe oublié, ajoute cette ligne à
`apps/api/.env` :

```
AUTH_EXPOSE_DEV_CODES=true
```

---

## 7. Ce que le Lot 3 ne règle PAS

- **Envoi réel** des emails et SMS : les codes ne partent nulle part. → **Lot 5**
- **Redis/BullMQ** : le CDC prévoit d'y stocker les OTP ; ils sont pour l'instant
  en base PostgreSQL, ce qui fonctionne mais garde des lignes à purger. → **Lot 5**
- **Nettoyage** des jetons et codes expirés : aucune tâche planifiée ne les
  supprime. → **Lot 5**
- **`sort`** : toujours validé mais pas appliqué.
- **Inscription prestataire** : `register` crée un compte utilisateur simple. La
  création du profil prestataire et le dépôt de ses documents restent des
  actions back-office.
- **Pièces jointes de litige** et **commentaire interne** (`internalOnly`). → **Lot 4**
- **Tests** : la majorité des anciens fichiers restent factices. → **Lot 5**
