# PRESTGO Mobile

Application mobile Flutter portant les deux surfaces PRESTGO — **client** et
**prestataire** — au-dessus du service REST existant (`prestgo-main`).

- Spécification, plan et contrats : [specs/001-prestgo-mobile-app/](specs/001-prestgo-mobile-app/)
- Cahier des charges (contrat d'API figé, captures réelles) :
  [docs/PRESTGO-Mobile-Flutter-Cahier-des-charges.md](docs/PRESTGO-Mobile-Flutter-Cahier-des-charges.md)
- Guide complet de mise en route et de validation :
  [specs/001-prestgo-mobile-app/quickstart.md](specs/001-prestgo-mobile-app/quickstart.md)

## Prérequis

| Élément | Version / valeur |
|---|---|
| Flutter | 3.38.4 stable (Dart 3.10.3) |
| Android | SDK API 26 et plus, un émulateur ou un appareil |
| iOS *(optionnel sur Windows)* | Xcode, iOS 14 et plus |
| Service PRESTGO | démarré et accessible, base de démonstration alimentée |

### Démarrer le service

Le service vit dans un dépôt séparé (`prestgo-main`, monorepo pnpm). Sa base
d'API est `http://<hôte>:3000/api/v1` — le préfixe `/api/v1` est posé
globalement par le serveur.

```bash
cd <racine de prestgo-main>/apps/api
corepack pnpm db:migrate     # schéma
corepack pnpm db:seed        # comptes et données de démonstration
corepack pnpm dev            # écoute sur :3000
```

## Mise en route

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Lancement en développement (émulateur Android)
flutter run --dart-define-from-file=env/dev.json
```

### Environnements

Trois fichiers de définitions dans [env/](env/), injectés au lancement par
`--dart-define-from-file` :

| Environnement | Base d'API | Particularités |
|---|---|---|
| `dev` (émulateur Android) | `http://10.0.2.2:3000/api/v1` | HTTP en clair autorisé, journaux réseau actifs, Sentry désactivé |
| `dev` (simulateur iOS) | `http://localhost:3000/api/v1` | idem |
| `staging` | `https://<hôte-staging>/api/v1` | HTTPS strict |
| `prod` | `https://<hôte-prod>/api/v1` | HTTPS strict, journaux réseau désactivés |

⚠️ **Deux pièges classiques** :

- Sur **émulateur Android**, l'hôte de développement est `10.0.2.2`, jamais
  `localhost` (qui désigne l'émulateur lui-même).
- La base d'API **contient déjà** `/api/v1` : aucun chemin d'appel ne le répète.
  Un 404 généralisé signale presque toujours un préfixe doublé.

Côté Android, les saveurs `dev` / `staging` / `prod` correspondent aux mêmes
environnements (`flutter run --flavor dev --dart-define-from-file=env/dev.json`) ;
le trafic en clair n'est autorisé que dans la saveur `dev`.

### Comptes de démonstration

Créés par le seed du service, tous au statut `active`, mot de passe commun
`prestgo123!` :

| Usage | Email |
|---|---|
| Client | `client.demo@prestgo.test` |
| Prestataire **réservable** (`approved` + `available`) | `provider.ready@prestgo.test` |
| Prestataire en vérification | `kofi.plombier@prestgo.test` |
| Prestataire en vérification (2e) | `ama.electricite@prestgo.test` |
| Super admin (back-office, approbation des dossiers) | `admin@prestgo.test` |

Les identifiants de ressources changent à chaque réinitialisation de la base ;
les emails, eux, sont stables. Voir le
[quickstart](specs/001-prestgo-mobile-app/quickstart.md) pour les données posées
par le seed et ses deux pièges connus.

## Vérification

```bash
# Analyse statique (inclut la règle de frontière d'import entre features — porte G5)
flutter analyze

# Tests unitaires, de contrat et de widgets
flutter test

# Parcours de bout en bout (appareil ou émulateur requis, service démarré)
flutter test integration_test --dart-define-from-file=env/dev.json
```

Attendu avant toute revue : `flutter analyze` sans avertissement et
`flutter test` au vert. Les tests de contrat rejouent les captures JSON réelles
du cahier des charges (`test/fixtures/`).

## Architecture en bref

Un seul paquet Flutter, découpage **feature-first** :

```text
lib/
├── app/          # MaterialApp.router, go_router, gardien unique (auth + rôle), thème
├── core/         # socle : enveloppe d'API unique, ApiException, AuthInterceptor,
│                 # idempotence, cache drift, connectivité, push, formats fr_CI
├── features/     # auth, profile, search, booking, missions, reviews, messaging,
│                 # notifications, disputes, provider_onboarding, provider_space
└── shared/       # modèles réellement partagés (catalogue)
```

Règles non négociables (portes G1 à G7 du
[plan](specs/001-prestgo-mobile-app/plan.md)) : le serveur est l'autorité métier ;
aucun écran ne lit `data` brut ni ne teste un code HTTP hors de `lib/core/api/` ;
aucun seuil métier figé à la compilation (les six réglages viennent de
`GET /settings/public`) ; aucune écriture hors ligne différée ; les surfaces
client et prestataire ne partagent que le socle ; aucune donnée sensible sur
disque ; chaque dépôt est couvert par un test de contrat.

## Dépannage courant

Voir le [§6 du quickstart](specs/001-prestgo-mobile-app/quickstart.md) —
notamment : requêtes en échec sur émulateur (`localhost` au lieu de `10.0.2.2`),
404 généralisé (`/api/v1` doublé), agenda décalé d'une heure (les heures `HH:MM`
ne se convertissent jamais de fuseau), créneau refusé (dates d'intervention
toujours en UTC).
