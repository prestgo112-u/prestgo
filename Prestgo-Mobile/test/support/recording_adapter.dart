// Adaptateur HTTP d'essai, partagé par les tests de contrat et unitaires.
//
// Il enregistre chaque appel et répond selon un scénario fourni par le test — ce qui
// permet de vérifier *combien* de fois une route a été jointe, pas seulement ce
// qu'elle a renvoyé. C'est indispensable aux invariants de rejeu et de
// renouvellement, qui portent sur le **nombre** d'appels.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Réponse simulée : code de statut et corps (encodé en JSON).
typedef AdapterResponse = (int statusCode, Object? body);

/// Décide de la réponse d'après la requête et le nombre d'appels déjà reçus sur ce
/// même chemin (0 pour le premier).
///
/// Le rappel peut aussi **lever** : l'exception traverse `dio`, qui la présente
/// comme un échec réseau — c'est ainsi qu'on simule une coupure.
typedef AdapterScenario =
    AdapterResponse Function(RequestOptions options, int callIndex);

class RecordingAdapter implements HttpClientAdapter {
  RecordingAdapter(this.respond);

  /// Toutes les requêtes reçues, dans l'ordre.
  final List<RequestOptions> calls = <RequestOptions>[];

  final AdapterScenario respond;

  /// Nombre d'appels reçus sur [path].
  int countFor(String path) =>
      calls.where((RequestOptions o) => o.path == path).length;

  /// Dernier appel reçu sur [path].
  RequestOptions lastFor(String path) =>
      calls.lastWhere((RequestOptions o) => o.path == path);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final int index = countFor(options.path);
    calls.add(options);
    final (int status, Object? body) = respond(options, index);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
