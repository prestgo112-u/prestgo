// Providers de la couche réseau.
//
// Deux instances HTTP coexistent, et c'est délibéré (R8) :
//   • [apiClientProvider]   — chaîne complète, avec `AuthInterceptor` ;
//   • [refreshDioProvider]  — **sans** `AuthInterceptor`, réservée à l'appel de
//     renouvellement. Sans cette séparation, un 401 sur le renouvellement
//     relancerait un renouvellement, en récursion infinie.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/envelope_interceptor.dart';
import 'package:prestgo_mobile/core/config/app_environment.dart';
import 'package:prestgo_mobile/core/connectivity/offline_banner.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';

/// Relais des échecs définitifs vers le rapport d'incident (SC-010).
///
/// Toute instance HTTP le reçoit : c'est lui qui garantit que 100 % des
/// incidents remontés portent l'étiquette `correlation_id` — le tri entre
/// incident et issue attendue (réseau, saisie, débit) appartient au rapporteur.
IncidentSink _incidentSink(Ref ref) =>
    (ApiException exception, String path) => unawaited(
      ref
          .read(errorReporterProvider)
          .reportApiFailure(exception, operation: path),
    );

/// Configuration d'environnement, figée pour toute la session.
///
/// Surchargée dans les tests et par l'amorçage lorsqu'une définition explicite est
/// fournie.
final Provider<AppEnvironment> appEnvironmentProvider =
    Provider<AppEnvironment>((Ref ref) => AppEnvironment.fromDefines());

/// Instance dédiée au renouvellement de session — **sans** `AuthInterceptor`.
final Provider<Dio> refreshDioProvider = Provider<Dio>((Ref ref) {
  final Dio dio = buildRefreshDio(
    ref.watch(appEnvironmentProvider),
    onIncident: _incidentSink(ref),
  );
  ref.onDispose(dio.close);
  return dio;
});

/// Instance HTTP principale.
///
/// ⚠️ L'intercepteur d'authentification n'a **pas** son propre provider, et c'est
/// délibéré : il doit pouvoir rejouer sur cette instance-ci, qu'il aurait donc à
/// lire. Riverpod y verrait une dépendance circulaire — `Ref.read` la refuse, et le
/// symptôme ne se manifesterait qu'au premier renouvellement, déguisé en erreur
/// réseau. `buildAuthenticatedDio` dénoue le nœud en construisant les deux ensemble.
final Provider<Dio> apiDioProvider = Provider<Dio>((Ref ref) {
  final Dio dio = buildAuthenticatedDio(
    environment: ref.watch(appEnvironmentProvider),
    tokenStore: ref.watch(secureTokenStoreProvider),
    refreshDio: ref.watch(refreshDioProvider),
    onSessionExpired: () =>
        ref.read(sessionControllerProvider.notifier).onSessionExpired(),
    onIncident: _incidentSink(ref),
  );
  ref.onDispose(dio.close);
  return dio;
});

/// Seule porte d'entrée typée du service (R9).
///
/// C'est aussi ici que chaque réponse réussie horodate « les dernières données
/// reçues » (T233) : attaché à l'instance que TOUS les dépôts traversent — y
/// compris celle que les harnais de test substituent, puisque le client est
/// construit après la surcharge.
final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((Ref ref) {
  final Dio dio = ref.watch(apiDioProvider);
  dio.interceptors.add(
    InterceptorsWrapper(
      onResponse:
          (Response<Object?> response, ResponseInterceptorHandler handler) {
            ref.read(lastDataTimestampProvider.notifier).record(DateTime.now());
            handler.next(response);
          },
    ),
  );
  return ApiClient(dio);
});
