// Conversion **unique** d'un échec en `ApiException` (porte G2).
//
// Tout ce qui sort de `dio` — coupure réseau, délai dépassé, réponse d'erreur du
// service, corps illisible — traverse cet intercepteur et en ressort sous la forme
// d'une seule et même exception. Aucun autre fichier ne convertit d'erreur.

import 'package:dio/dio.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';

/// Clé d'extra portant l'`ApiException` sur la `DioException` rejetée.
const String kApiExceptionExtra = 'prestgo.apiException';

class EnvelopeInterceptor extends Interceptor {
  const EnvelopeInterceptor();

  @override
  void onResponse(
    Response<Object?> response,
    ResponseInterceptorHandler handler,
  ) {
    // Le filtre d'exception du service est global : une réponse 2xx porte
    // normalement `success: true`. Un `success: false` en 2xx est une anomalie de
    // contrat — la traiter ici évite qu'un écran l'interprète à sa façon.
    final Object? body = response.data;
    if (body is Map<Object?, Object?>) {
      final JsonMap json = body.cast<String, Object?>();
      if (json['success'] == false) {
        handler.reject(
          _rejection(
            response.requestOptions,
            ApiException.fromResponse(
              statusCode: response.statusCode ?? 200,
              body: json,
            ),
            response: response,
          ),
          true,
        );
        return;
      }
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Déjà converti par un intercepteur en amont : ne pas reconstruire.
    if (err.error is ApiException) {
      handler.next(err);
      return;
    }
    handler.next(
      _rejection(
        err.requestOptions,
        toApiException(err),
        response: err.response,
        source: err,
      ),
    );
  }

  DioException _rejection(
    RequestOptions options,
    ApiException exception, {
    Response<Object?>? response,
    DioException? source,
  }) => DioException(
    requestOptions: options,
    response: response,
    type: source?.type ?? DioExceptionType.badResponse,
    error: exception,
    message: exception.message,
  );
}

/// Relais d'incident : l'exception **définitive** et le chemin appelé.
typedef IncidentSink = void Function(ApiException exception, String path);

/// Remonte chaque échec définitif vers le rapport d'incident (SC-010).
///
/// Placé en **dernier** dans la chaîne : il ne voit que les erreurs qui ont
/// survécu au renouvellement de session et au rejeu — jamais un 401 rattrapé ni
/// un 503 rejoué avec succès. Comme `EnvelopeInterceptor` a déjà converti,
/// l'exception porte toujours son `meta.correlationId` quand le service en a
/// fourni un : c'est ce qui garantit la couverture à 100 % des incidents
/// remontés, le filtrage (réseau, saisie, débit) restant l'affaire du rapporteur.
class IncidentReportingInterceptor extends Interceptor {
  const IncidentReportingInterceptor(this.sink);

  final IncidentSink sink;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final Object? error = err.error;
    if (error is ApiException) {
      sink(error, err.requestOptions.path);
    }
    handler.next(err);
  }
}

/// Traduit une `DioException` en `ApiException`.
///
/// Exposée pour les tests et pour les rares appels qui n'utilisent pas
/// l'intercepteur (envoi de fichier, cf. R7/R8).
ApiException toApiException(DioException err) {
  final Object? existing = err.error;
  if (existing is ApiException) {
    return existing;
  }

  switch (err.type) {
    case DioExceptionType.cancel:
      return const ApiException.cancelled();
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.transformTimeout:
    case DioExceptionType.connectionError:
    case DioExceptionType.badCertificate:
      // Du point de vue de l'utilisateur, tous ces cas sont « la connexion n'a pas
      // abouti » : un seul message, une seule action de reprise.
      return const ApiException.network();
    case DioExceptionType.badResponse:
    case DioExceptionType.unknown:
      break;
  }

  final Response<Object?>? response = err.response;
  final int? statusCode = response?.statusCode;
  if (statusCode == null) {
    // `unknown` sans réponse : socket fermée, DNS, TLS. Du point de vue de
    // l'utilisateur, c'est une coupure réseau.
    return const ApiException.network();
  }

  return ApiException.fromResponse(
    statusCode: statusCode,
    body: response?.data,
  );
}
