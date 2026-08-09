# Données de démonstration — comptes de test

**Public :** toute personne testant l'API ou l'application mobile à la main.
**Source :** `apps/api/prisma/seed.ts`, rejouable sans créer de doublons
(`corepack pnpm db:seed` depuis `apps/api`, ou `pnpm --filter @prestgo/api db:seed`
depuis la racine).

---

## 1. Mot de passe des comptes de démonstration

Tous les comptes de démonstration ci-dessous (client, prestataires, y compris
celui de la section 2) partagent le même mot de passe :

```
prestgo123!
```

(Le compte super admin, `admin@prestgo.test`, a le même mot de passe — voir
`Docs/README.md` §2.)

---

## 2. Prestataire « prêt à réserver » — ajouté le 29 juillet 2026

**Pourquoi ce compte existe :** les deux prestataires historiques (Kofi
Plomberie, Ama Électricité) sont volontairement laissés `pending_review` — ils
servent à tester l'écran **Vérifications** du back-office. Pour tester le
**parcours de réservation mobile** (recherche → fiche publique → création de
mission), il fallait un profil déjà `approved`, sans passer par une validation
manuelle à chaque réinitialisation de la base (`prisma db push` + `db:seed`).

| Champ | Valeur |
|---|---|
| Email | `provider.ready@prestgo.test` |
| Mot de passe | `prestgo123!` |
| Nom public | PRESTGO Demo — Plomberie Express |
| Statut de validation | `approved` |
| Disponibilité | `available` |
| Note / avis | 4.5 ★ (12 avis — compteur affiché, aucun avis réel n'est créé) |
| Prestation | Dépannage plomberie express → formule **Intervention express**, 5 000 XOF, 45 min |
| Zone couverte | Cocody (Abidjan) — réutilise la zone déjà présente dans le seed, aucune zone inventée |
| Agenda | Tous les jours (lundi à dimanche), 8h00–18h00 — large exprès, pour ne jamais bloquer un test manuel sur « pas de créneau » |

**Vérifié via de vrais appels HTTP le 29 juillet 2026 :**
- `GET /api/v1/providers/search` renvoie ce prestataire (seul résultat tant que
  Kofi et Ama restent `pending_review`).
- `GET /api/v1/providers/{id}/public` renvoie une fiche complète (bio,
  prestations, formules, zones, agenda) sans aucune donnée interne (pas
  d'email, de téléphone, d'empreinte de mot de passe ni d'identifiant
  utilisateur — seuls les champs sélectionnés explicitement par
  `provider-search.service.ts` sont exposés).

**Rejouabilité :** relancer le seed ne duplique ni le compte, ni la
prestation/formule, ni le lien de zone, ni les 7 lignes d'agenda (vérifié :
un deuxième passage donne toujours 1 formule, 1 zone, 7 créneaux).

---

## 3. Autres comptes de démonstration (déjà présents avant le 29 juillet 2026)

| Compte | Email | Statut |
|---|---|---|
| Super admin | `admin@prestgo.test` | actif, toutes permissions |
| Prestataire (plomberie) | `kofi.plombier@prestgo.test` | `pending_review` — pour tester la validation |
| Prestataire (électricité) | `ama.electricite@prestgo.test` | `pending_review` — pour tester la validation |
| Client | `client.demo@prestgo.test` | actif — a une mission `confirmed` avec Kofi, un fil de discussion, un avis signalé et un litige ouvert |
