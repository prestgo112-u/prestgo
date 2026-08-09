// Instance HTTP configurée et unique porte d'entrée typée du service.
//
// Deux responsabilités :
//   1. construire l'instance `dio` (base d'API de l'environnement, `User-Agent`
//      applicatif lisible, délais) ;
//   2. exposer `send<T>` — la seule fonction d'accès (R9), qui décode l'enveloppe et
//      relaie une `ApiException` et rien d'autre.
//
// ⚠️ La base configurée **contient déjà** `/api/v1` : aucun chemin passé ici ne le
// répète (piège n°2 de §6 de quickstart.md).

import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/auth_interceptor.dart';
import 'package:prestgo_mobile/core/api/envelope_interceptor.dart';
import 'package:prestgo_mobile/core/api/retry_policy.dart';
import 'package:prestgo_mobile/core/config/app_environment.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

/// Version applicative reportée dans le `User-Agent`.
///
/// Injectée à la compilation (`--dart-define=APP_VERSION=…`) par la chaîne de
/// livraison, qui la lit dans `version:` de pubspec.yaml — cf. l'étape « APK
/// staging » de `.github/workflows/ci.yml`. Le repli sert au poste de
/// développement, où la précision n'a pas d'enjeu.
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '1.0.0-dev',
);

/// `User-Agent` lisible — `PRESTGO-Android/1.0.0 (Android 14)`.
///
/// Il sert à identifier l'origine d'un appel dans les journaux du service ; il ne
/// porte aucune donnée personnelle.
String buildUserAgent({String version = kAppVersion}) {
  String platform;
  String system;
  try {
    if (Platform.isAndroid) {
      platform = 'Android';
    } else if (Platform.isIOS) {
      platform = 'iOS';
    } else {
      platform = Platform.operatingSystem;
    }
    system = Platform.operatingSystemVersion;
  } on Object {
    platform = 'Unknown';
    system = 'unknown';
  }
  return 'PRESTGO-$platform/$version ($system)';
}

/// Construit l'instance HTTP de base, sans intercepteur.
Dio buildBaseDio(AppEnvironment environment, {Duration? receiveTimeout}) => Dio(
  BaseOptions(
    baseUrl: environment.apiBaseUrl,
    connectTimeout: NetworkTimeouts.connect,
    sendTimeout: NetworkTimeouts.send,
    receiveTimeout: receiveTimeout ?? NetworkTimeouts.receive,
    headers: <String, Object?>{
      'Accept': 'application/json',
      'User-Agent': buildUserAgent(),
    },
  ),
);

/// Instance dédiée au renouvellement de session : **sans** `AuthInterceptor`.
///
/// Sans cette séparation, un 401 sur l'appel de renouvellement relancerait un
/// renouvellement, en récursion infinie (R8).
Dio buildRefreshDio(AppEnvironment environment, {IncidentSink? onIncident}) {
  final Dio dio = buildBaseDio(environment);
  dio.interceptors.addAll(<Interceptor>[
    const EnvelopeInterceptor(),
    if (onIncident != null) IncidentReportingInterceptor(onIncident),
  ]);
  return dio;
}

/// Instance principale, complète : enveloppe, authentification, rejeu.
///
/// ⚠️ L'intercepteur d'authentification est construit **ici**, et non fourni par
/// l'appelant. Il doit pouvoir rejouer la requête d'origine sur cette instance-ci —
/// donc la connaître — alors qu'elle n'existe pas encore au moment de le construire.
/// Le nœud se dénoue avec une variable locale capturée par la fermeture, comme le
/// fait déjà `RetryInterceptor`.
///
/// La tentation était de passer par deux providers, l'un pour l'intercepteur et
/// l'autre pour l'instance. Riverpod y voit — à raison — une dépendance circulaire :
/// l'instance observe l'intercepteur, qui lirait l'instance. `Ref.read` la refuse, et
/// l'échec ne se voit pas en lecture de code : il apparaît au premier renouvellement,
/// sous la forme trompeuse d'une erreur réseau.
Dio buildAuthenticatedDio({
  required AppEnvironment environment,
  required SecureTokenStore tokenStore,
  required Dio refreshDio,
  required Future<void> Function() onSessionExpired,
  IncidentSink? onIncident,
}) {
  late final Dio dio;
  final AuthInterceptor authInterceptor = AuthInterceptor(
    tokenStore: tokenStore,
    refreshDio: refreshDio,
    client: () => dio,
    onSessionExpired: onSessionExpired,
  );
  // `late` : la fermeture ci-dessus capture cette variable, pas sa valeur — elle ne
  // sera lue qu'au moment d'un rejeu, bien après cette affectation.
  return dio = _assemble(environment, authInterceptor, onIncident: onIncident);
}

/// Assemble la chaîne d'intercepteurs.
///
/// L'ordre compte : l'enveloppe convertit d'abord l'échec en `ApiException`, si bien
/// que l'authentification puis le rejeu raisonnent sur des prédicats et jamais sur
/// un code HTTP.
Dio _assemble(
  AppEnvironment environment,
  AuthInterceptor authInterceptor, {
  IncidentSink? onIncident,
}) {
  final Dio dio = buildBaseDio(environment);
  dio.interceptors.addAll(<Interceptor>[
    const EnvelopeInterceptor(),
    authInterceptor,
    RetryInterceptor(dio: dio),
    // Après le rejeu : seuls les échecs définitifs sont des incidents (SC-010).
    if (onIncident != null) IncidentReportingInterceptor(onIncident),
    if (environment.networkLogsEnabled)
      // Route et statut seulement : `requestBody` et `responseBody` restent à leur
      // défaut (faux) pour que ni mot de passe ni jeton n'atteigne un journal.
      LogInterceptor(
        request: false,
        requestHeader: false,
        responseHeader: false,
        logPrint: _logPrint,
      ),
  ]);
  return dio;
}

void _logPrint(Object? object) {
  // ignore: avoid_print — journal réseau, actif hors production seulement.
  print('[api] $object');
}

/// Accès typé au service : décode l'enveloppe, ne laisse remonter qu'une
/// `ApiException`.
class ApiClient {
  const ApiClient(this.dio);

  final Dio dio;

  Future<ApiEnvelope<T>> get<T>(
    String path, {
    required EnvelopeParser<T> parse,
    Map<String, Object?>? query,
    CancelToken? cancelToken,
  }) => send<T>(
    'GET',
    path,
    parse: parse,
    query: query,
    cancelToken: cancelToken,
  );

  Future<ApiEnvelope<T>> post<T>(
    String path, {
    required EnvelopeParser<T> parse,
    Object? body,
    Map<String, Object?>? query,
    Map<String, String>? headers,
    Map<String, Object?>? extra,
    CancelToken? cancelToken,
  }) => send<T>(
    'POST',
    path,
    parse: parse,
    body: body,
    query: query,
    headers: headers,
    extra: extra,
    cancelToken: cancelToken,
  );

  Future<ApiEnvelope<T>> patch<T>(
    String path, {
    required EnvelopeParser<T> parse,
    Object? body,
    CancelToken? cancelToken,
  }) => send<T>(
    'PATCH',
    path,
    parse: parse,
    body: body,
    cancelToken: cancelToken,
  );

  Future<ApiEnvelope<T>> put<T>(
    String path, {
    required EnvelopeParser<T> parse,
    Object? body,
    CancelToken? cancelToken,
  }) =>
      send<T>('PUT', path, parse: parse, body: body, cancelToken: cancelToken);

  Future<ApiEnvelope<T>> delete<T>(
    String path, {
    required EnvelopeParser<T> parse,
    Object? body,
    Map<String, Object?>? extra,
    CancelToken? cancelToken,
  }) => send<T>(
    'DELETE',
    path,
    parse: parse,
    body: body,
    extra: extra,
    cancelToken: cancelToken,
  );

  /// Fonction d'accès unique.
  ///
  /// [parse] interprète `data` — objet, tableau ou objet structuré, cf.
  /// contracts/api-envelope.md §2.
  Future<ApiEnvelope<T>> send<T>(
    String method,
    String path, {
    required EnvelopeParser<T> parse,
    Object? body,
    Map<String, Object?>? query,
    Map<String, String>? headers,
    Map<String, Object?>? extra,
    CancelToken? cancelToken,
  }) async {
    try {
      final Response<Object?> response = await dio.request<Object?>(
        path,
        data: body,
        queryParameters: query,
        cancelToken: cancelToken,
        options: Options(method: method, headers: headers, extra: extra),
      );

      final Object? payload = response.data;
      if (payload is! Map<Object?, Object?>) {
        // Le filtre d'exception du service est global : un corps qui n'est pas une
        // enveloppe vient d'un intermédiaire, pas de l'application.
        throw ApiException.fromResponse(statusCode: response.statusCode ?? 200);
      }
      return ApiEnvelope<T>.fromJson(
        payload.cast<String, Object?>(),
        parse,
        statusCode: response.statusCode,
      );
    } on DioException catch (error) {
      final Object? converted = error.error;
      throw converted is ApiException ? converted : toApiException(error);
    }
  }
}
