// Montage de l'application entière sur un service simulé.
//
// Partagé par les parcours d'intégration. Trois choses seulement sont remplacées :
// le transport HTTP, la base locale et le stockage sécurisé. Le reste — routeur,
// gardien, chaîne d'intercepteurs, dépôts, écrans — est le code livré.
//
// La chaîne d'intercepteurs est **reconstruite par les fonctions de production**
// (`buildAuthenticatedDio`, `buildRefreshDio`) : seul l'adaptateur de transport
// change. C'est ce qui permet à un parcours de vérifier le renouvellement de session
// ou le rejeu d'une réservation, qui vivent précisément dans ces intercepteurs.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:prestgo_mobile/app/push_driver.dart';
import 'package:prestgo_mobile/app/router.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/config/app_environment.dart';
import 'package:prestgo_mobile/core/connectivity/offline_banner.dart';
import 'package:prestgo_mobile/core/connectivity/offline_gate.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/location/location_service.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/settings/public_settings.dart';
import 'package:prestgo_mobile/l10n/generated/app_localizations.dart';

import '../../test/support/recording_adapter.dart';
import '../../test/support/screen_harness.dart';

/// Base identique à celle de l'environnement `dev`.
const String kFlowBaseUrl = 'http://localhost:3000/api/v1';

/// Position simulée, et ce qu'elle vaut.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.result = const LocationResult(outcome: LocationOutcome.denied),
  });

  /// Modifiable en cours de parcours : un utilisateur peut accorder la
  /// localisation après l'avoir refusée.
  LocationResult result;

  @override
  Future<LocationResult> current() async => result;
}

/// Conteneur monté sur un service simulé.
///
/// [extraOverrides] permet à un parcours de substituer un point d'injection qui
/// lui est propre — le sélecteur de fichier de P7, par exemple — sans que le
/// harnais commun n'ait à connaître chaque écran.
ProviderContainer buildAppContainer({
  required RecordingAdapter adapter,
  required LocalDatabase database,
  required InMemoryTokenStore tokenStore,
  LocationService? location,
  PublicSettings? settings,
  OfflineGate? offlineGate,
  List<Override> extraOverrides = const <Override>[],
}) {
  final AppEnvironment environment = AppEnvironment.fromDefines(
    apiBaseUrl: kFlowBaseUrl,
    networkLogsEnabled: false,
  );

  return ProviderContainer(
    overrides: <Override>[
      appEnvironmentProvider.overrideWithValue(environment),
      localDatabaseProvider.overrideWithValue(database),
      secureTokenStoreProvider.overrideWithValue(tokenStore),
      // Les réglages publics sont lus au démarrage par l'amorçage, que les
      // parcours ne déroulent pas : on pose la valeur qu'il aurait obtenue.
      publicSettingsProvider.overrideWithValue(
        settings ?? PublicSettings.fallback,
      ),
      // Jamais le greffon de connectivité en test : muet par défaut, piloté
      // par le parcours US10 quand il fournit le sien.
      offlineGateProvider.overrideWithValue(offlineGate ?? StubOfflineGate()),
      if (location != null) locationServiceProvider.overrideWithValue(location),
      refreshDioProvider.overrideWith(
        (Ref ref) => buildRefreshDio(environment)..httpClientAdapter = adapter,
      ),
      apiDioProvider.overrideWith(
        (Ref ref) => buildAuthenticatedDio(
          environment: environment,
          tokenStore: tokenStore,
          refreshDio: ref.watch(refreshDioProvider),
          onSessionExpired: () =>
              ref.read(sessionControllerProvider.notifier).onSessionExpired(),
        )..httpClientAdapter = adapter,
      ),
      ...extraOverrides,
    ],
  );
}

/// Application réelle, montée sur un conteneur fourni par le parcours.
class FlowApp extends StatelessWidget {
  const FlowApp({required this.container, super.key});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context) => UncontrolledProviderScope(
    container: container,
    child: const _RouterHost(),
  );
}

/// Reproduit la configuration de `PrestgoApp`, délégués de localisation compris.
///
/// Ce n'est pas un détail : `GlobalMaterialLocalizations` initialise les données de
/// date de la locale, dont dépend `DateLabels`. Sans elles, tout écran affichant une
/// date lèverait `LocaleDataException` — un échec du **harnais**, pas du code, qu'il
/// serait tentant de « corriger » en retirant le formatage.
class _RouterHost extends ConsumerWidget {
  const _RouterHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) => PushDriver(
    // Le pilote push fait partie du code livré : les parcours le traversent
    // comme la production — sans transport simulé, il reste un non-évènement.
    child: MaterialApp.router(
      routerConfig: ref.watch(goRouterProvider),
      // La bannière hors ligne fait partie du code livré : les parcours la
      // traversent comme la production (US10).
      builder: (BuildContext context, Widget? child) =>
          GlobalOfflineBanner(child: child ?? const SizedBox.shrink()),
      locale: const Locale(AppFormats.languageCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    ),
  );
}

/// Adresse de **base** de la pile de navigation.
///
/// ⚠️ À n'employer qu'après un `go`, qui remplace la pile. Après un `push`, cette
/// valeur ne bouge pas : go_router empile la nouvelle route sans changer l'adresse de
/// base, et un test qui s'y fierait conclurait qu'aucune navigation n'a eu lieu alors
/// que l'écran est bel et bien affiché. Les types qui portent le sommet de la pile
/// (`ImperativeRouteMatch`) ne font pas partie de l'API publique de go_router : un
/// écran empilé se vérifie donc **par son widget**, pas par son adresse.
String locationOf(ProviderContainer container) => container
    .read(goRouterProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .toString();

/// Coupure réseau simulée : `dio` la présente comme un échec sans réponse.
class NetworkDown implements Exception {
  const NetworkDown();

  @override
  String toString() => 'Réseau coupé (simulation)';
}

/// Réponse fabriquée à la volée, pour les cas qui n'ont pas de capture.
typedef Capture = (int statusCode, Map<String, Object?> body);

Capture envelope(Object? data, {int status = 200, String message = 'OK'}) => (
  status,
  <String, Object?>{'success': true, 'message': message, 'data': data},
);

/// Requêtes reçues par l'adaptateur, par chemin.
extension AdapterJournal on RecordingAdapter {
  List<RequestOptions> callsToPath(String path) =>
      calls.where((RequestOptions o) => o.path == path).toList();
}
