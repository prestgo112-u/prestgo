# Définitions d'environnement

Injectées au lancement, jamais lues depuis un fichier embarqué (R4) :

```bash
flutter run   --dart-define-from-file=env/dev.json
flutter build appbundle --flavor prod --dart-define-from-file=env/prod.json
flutter test  integration_test --dart-define-from-file=env/dev.json
```

| Clé | Type | Rôle |
|---|---|---|
| `APP_ENV` | `String` | `dev`, `staging` ou `prod` — pilote les saveurs et les garde-fous |
| `API_BASE_URL` | `String` | Base d'API **contenant déjà `/api/v1`** — aucun chemin ne le répète |
| `SENTRY_ENABLED` | `bool` | Rapport d'incident ; **faux en `dev`** (R5) |
| `SENTRY_DSN` | `String` | Vide dans le dépôt ; fourni par la CI ou un fichier local |
| `NETWORK_LOGS_ENABLED` | `bool` | Journaux de requêtes ; faux en `prod` |

⚠️ `API_BASE_URL` en `dev` vaut `http://10.0.2.2:3000/api/v1` sur **émulateur
Android** (`localhost` y désigne l'émulateur lui-même) et
`http://localhost:3000/api/v1` sur **simulateur iOS**. Pour la variante iOS, copier
`dev.json` en `local.json` (ignoré par git) et lancer avec
`--dart-define-from-file=env/local.json`.

Le trafic en clair n'est autorisé que pour `dev` : `usesCleartextTraffic` est limité à
la saveur Android `dev` et l'exception ATS iOS au seul domaine de développement.

## Secrets

Aucun secret n'est versionné. `SENTRY_DSN` est vide dans `staging.json` et
`prod.json` : la valeur réelle est injectée par l'intégration continue, ou placée dans
`env/local.json` pour un poste de développement.
