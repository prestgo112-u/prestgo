// Lecture de la configuration d'environnement (R4 de research.md).
//
// Les valeurs viennent de `--dart-define-from-file=env/<env>.json` : rien n'est
// embarqué comme ressource, rien n'est lu à l'exécution depuis le disque.

/// Les trois environnements de la livraison.
enum AppEnvironmentName {
  dev,
  staging,
  prod;

  static AppEnvironmentName parse(String raw) {
    for (final AppEnvironmentName value in AppEnvironmentName.values) {
      if (value.name == raw) {
        return value;
      }
    }
    throw ArgumentError.value(
      raw,
      'APP_ENV',
      'Environnement inconnu — attendu dev, staging ou prod',
    );
  }
}

/// Configuration figée pour toute la durée de la session.
class AppEnvironment {
  const AppEnvironment({
    required this.name,
    required this.apiBaseUrl,
    required this.sentryEnabled,
    required this.sentryDsn,
    required this.networkLogsEnabled,
  });

  /// Construit la configuration depuis les définitions de compilation.
  ///
  /// [apiBaseUrl] est normalisée : le `/` final est retiré pour qu'aucun appel ne
  /// produise de double barre oblique.
  factory AppEnvironment.fromDefines({
    String name = _appEnvDefine,
    String apiBaseUrl = _apiBaseUrlDefine,
    bool sentryEnabled = _sentryEnabledDefine,
    String sentryDsn = _sentryDsnDefine,
    bool networkLogsEnabled = _networkLogsDefine,
  }) {
    if (apiBaseUrl.isEmpty) {
      throw StateError(
        'API_BASE_URL absente : lancer avec --dart-define-from-file=env/<env>.json',
      );
    }
    final String normalised = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;

    // Le préfixe de version fait partie de la base : aucun chemin d'appel ne le
    // répète (piège n°2 de §6 de quickstart.md).
    if (!normalised.endsWith(apiVersionPrefix)) {
      throw StateError(
        'API_BASE_URL doit se terminer par "$apiVersionPrefix" (reçu : $normalised)',
      );
    }

    return AppEnvironment(
      name: AppEnvironmentName.parse(name),
      apiBaseUrl: normalised,
      sentryEnabled: sentryEnabled,
      sentryDsn: sentryDsn,
      networkLogsEnabled: networkLogsEnabled,
    );
  }

  /// Suffixe de version porté par la base d'API.
  static const String apiVersionPrefix = '/api/v1';

  static const String _appEnvDefine = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'dev',
  );
  static const String _apiBaseUrlDefine = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000/api/v1',
  );
  static const bool _sentryEnabledDefine = bool.fromEnvironment(
    'SENTRY_ENABLED',
  );
  static const String _sentryDsnDefine = String.fromEnvironment('SENTRY_DSN');
  static const bool _networkLogsDefine = bool.fromEnvironment(
    'NETWORK_LOGS_ENABLED',
    defaultValue: true,
  );

  final AppEnvironmentName name;

  /// Base d'API **contenant déjà** `/api/v1`.
  final String apiBaseUrl;

  final bool sentryEnabled;
  final String sentryDsn;
  final bool networkLogsEnabled;

  bool get isDev => name == AppEnvironmentName.dev;

  /// Le rapport d'incident n'est jamais armé en `dev`, quoi qu'en dise la
  /// définition d'environnement (R5).
  bool get reportsIncidents => sentryEnabled && sentryDsn.isNotEmpty && !isDev;

  @override
  String toString() =>
      'AppEnvironment(${name.name}, $apiBaseUrl, sentry: $reportsIncidents)';
}
