// Amorçage du rapport d'incident (R5 de research.md).
//
// Trois garde-fous, dans cet ordre :
//   1. **désactivé en `dev`** — quoi qu'en dise la définition d'environnement ;
//   2. désactivé si aucun DSN n'est fourni (le dépôt n'en versionne aucun) ;
//   3. ni jeton, ni mot de passe, ni corps de requête ne sortent de l'appareil.
//
// L'identifiant de corrélation (`meta.correlationId`) est attaché en étiquette par
// `ErrorReporter` (T033), pas ici : ce fichier ne connaît pas la couche réseau.

import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

/// Environnement courant, injecté par `--dart-define-from-file`.
const String _appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

/// Activation demandée par la définition d'environnement.
const bool _sentryEnabledDefine = bool.fromEnvironment('SENTRY_ENABLED');

/// DSN, vide dans le dépôt ; injecté par l'intégration continue.
const String _sentryDsnDefine = String.fromEnvironment('SENTRY_DSN');

/// Nom de l'environnement de développement, seul à interdire la télémétrie.
const String kDevEnvironmentName = 'dev';

/// Vrai si le rapport d'incident doit réellement être armé.
///
/// Exposé pour que l'amorçage (T041) et les tests puissent l'interroger sans
/// dupliquer la règle.
bool sentryIsEnabled({
  String environment = _appEnv,
  bool enabledByDefine = _sentryEnabledDefine,
  String dsn = _sentryDsnDefine,
}) => enabledByDefine && dsn.isNotEmpty && environment != kDevEnvironmentName;

/// Lance [appRunner], sous Sentry lorsque l'environnement l'autorise.
///
/// Quand la télémétrie est désactivée, [appRunner] est simplement exécuté : aucun
/// chemin de démarrage parallèle, donc aucun écart de comportement entre `dev` et
/// les autres environnements.
Future<void> runWithSentry(
  FutureOr<void> Function() appRunner, {
  String environment = _appEnv,
  bool enabledByDefine = _sentryEnabledDefine,
  String dsn = _sentryDsnDefine,
  String? release,
}) async {
  if (!sentryIsEnabled(
    environment: environment,
    enabledByDefine: enabledByDefine,
    dsn: dsn,
  )) {
    await appRunner();
    return;
  }

  await SentryFlutter.init(
    (SentryFlutterOptions options) => _configure(
      options,
      dsn: dsn,
      environment: environment,
      release: release,
    ),
    appRunner: appRunner,
  );
}

void _configure(
  SentryFlutterOptions options, {
  required String dsn,
  required String environment,
  required String? release,
}) {
  options
    ..dsn = dsn
    ..environment = environment
    ..debug = false
    // Aucune donnée personnelle déduite automatiquement (adresse IP, identifiants).
    ..sendDefaultPii = false
    // Le corps des requêtes peut porter un mot de passe ou un justificatif.
    ..maxRequestBodySize = MaxRequestBodySize.never
    // Traces de performance des écrans clés — mesure de SC-005.
    ..tracesSampleRate = environment == 'prod' ? 0.2 : 1.0
    ..beforeSend = _scrub;

  if (release != null) {
    options.release = release;
  }
}

/// Ne laisse partir que la route et la méthode : ni en-têtes (donc ni jeton
/// d'authentification), ni corps, ni cookies, ni chaîne de requête.
SentryEvent? _scrub(SentryEvent event, Hint hint) {
  final SentryRequest? request = event.request;
  if (request == null) {
    return event;
  }
  return event.copyWith(
    request: SentryRequest(url: request.url, method: request.method),
  );
}
