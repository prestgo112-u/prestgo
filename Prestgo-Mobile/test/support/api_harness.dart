// Client d'essai des tests de contrat.
//
// Il monte la chaîne minimale qui reproduit fidèlement ce que voit un dépôt :
// `EnvelopeInterceptor` — le point de conversion **unique** d'un échec en
// `ApiException` — et rien d'autre. L'intercepteur d'authentification et la politique
// de rejeu ont leurs propres tests unitaires ; les inclure ici rendrait ces
// tests-là sensibles à des invariants qui ne les concernent pas.
//
// La base porte `/api/v1`, comme en production : c'est ce qui permet de vérifier
// qu'aucun chemin de dépôt ne le répète.

import 'package:dio/dio.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/envelope_interceptor.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

import 'recording_adapter.dart';

/// Base identique à celle de l'environnement `dev`.
const String kTestBaseUrl = 'http://localhost:3000/api/v1';

class ApiHarness {
  ApiHarness(AdapterScenario respond)
    : adapter = RecordingAdapter(respond),
      _dio = Dio(
        BaseOptions(
          baseUrl: kTestBaseUrl,
          connectTimeout: NetworkTimeouts.connect,
          receiveTimeout: NetworkTimeouts.receive,
        ),
      ) {
    _dio
      ..httpClientAdapter = adapter
      ..interceptors.add(const EnvelopeInterceptor());
  }

  /// Répond toujours la même chose, quel que soit l'appel.
  factory ApiHarness.always(int status, Object? body) =>
      ApiHarness((RequestOptions options, int index) => (status, body));

  final RecordingAdapter adapter;
  final Dio _dio;

  ApiClient get client => ApiClient(_dio);

  /// Dernier appel reçu — chemin, méthode, corps et en-têtes.
  RequestOptions get lastCall => adapter.calls.last;

  /// Corps du dernier appel, décodé.
  Map<String, Object?> get lastBody {
    final Object? data = adapter.calls.last.data;
    return data is Map<Object?, Object?>
        ? data.cast<String, Object?>()
        : <String, Object?>{};
  }

  int get callCount => adapter.calls.length;

  /// URL complète telle qu'elle partirait — sert à vérifier l'absence de `/api/v1`
  /// répété.
  String get lastUrl => adapter.calls.last.uri.toString();
}
