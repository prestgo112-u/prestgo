// Remontée d'incident portant l'identifiant de corrélation (R5, FR-091, SC-010).
//
// L'exigence est nette : **100 %** des incidents remontés portent le
// `meta.correlationId` de l'erreur qui les a provoqués. C'est la clé qui relie une
// plainte utilisateur à la trace serveur, et Sentry l'indexe comme étiquette, donc
// interrogeable directement.
//
// Ce qui ne sort jamais de l'appareil : jetons, mots de passe, corps de requête.
// L'assainissement est posé par `sentry_bootstrap.dart` ; ici on n'ajoute que des
// métadonnées de routage.

import 'dart:async';

import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Étiquette portant l'identifiant de corrélation du service.
const String kCorrelationIdTag = 'correlation_id';

/// Étiquette portant la nature de l'échec (`network`, `response`, `cancelled`).
const String kFailureKindTag = 'failure_kind';

/// Étiquette portant le code de statut, quand il existe.
const String kStatusCodeTag = 'status_code';

class ErrorReporter {
  const ErrorReporter({this.enabled = true, Hub? hub}) : _hub = hub;

  /// Faux en `dev` : la télémétrie n'est pas armée, les appels sont sans effet.
  final bool enabled;

  final Hub? _hub;

  /// `HubAdapter` délègue au hub courant : injecter un [Hub] dans les tests évite
  /// d'armer Sentry pour vérifier qu'une étiquette est bien posée.
  Hub get _sentry => _hub ?? HubAdapter();

  /// Remonte une erreur applicative avec son identifiant de corrélation.
  ///
  /// Les échecs réseau ne sont **pas** remontés : une coupure de connexion n'est pas
  /// un incident de l'application, et les noyer dans la télémétrie masquerait les
  /// vrais défauts.
  Future<void> reportApiFailure(
    ApiException error, {
    StackTrace? stackTrace,
    String? operation,
  }) async {
    if (!enabled || error.isNetwork || error.isCancelled) {
      return;
    }
    // Une saisie invalide et un débit dépassé sont des issues attendues, pas des
    // incidents.
    if (error.isUserFixable || error.isRateLimited || error.isAuth) {
      return;
    }

    await _capture(
      error,
      stackTrace: stackTrace,
      correlationId: error.correlationId,
      operation: operation,
      tags: <String, String>{
        kFailureKindTag: error.kind.name,
        if (error.statusCode case final int code)
          kStatusCodeTag: code.toString(),
      },
    );
  }

  /// Remonte une erreur quelconque — anomalie de décodage, état incohérent.
  Future<void> reportError(
    Object error, {
    StackTrace? stackTrace,
    String? correlationId,
    String? operation,
  }) => _capture(
    error,
    stackTrace: stackTrace,
    correlationId: correlationId,
    operation: operation,
    tags: const <String, String>{},
  );

  Future<void> _capture(
    Object error, {
    required StackTrace? stackTrace,
    required String? correlationId,
    required String? operation,
    required Map<String, String> tags,
  }) async {
    if (!enabled) {
      return;
    }
    await _sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (Scope scope) {
        // L'étiquette est posée systématiquement, y compris quand le service n'a pas
        // fourni d'identifiant : l'absence doit être visible en recherche, pas
        // silencieuse (SC-010).
        scope.setTag(kCorrelationIdTag, correlationId ?? 'absent');
        if (operation != null) {
          scope.setTag('operation', operation);
        }
        for (final MapEntry<String, String> tag in tags.entries) {
          scope.setTag(tag.key, tag.value);
        }
      },
    );
  }

  /// Trace de performance d'un écran clé — mesure directe de SC-005.
  Future<T> traceScreen<T>(
    String name,
    Future<T> Function() body, {
    String operation = 'ui.load',
  }) async {
    if (!enabled) {
      return body();
    }
    final ISentrySpan transaction = _sentry.startTransaction(
      name,
      operation,
      bindToScope: true,
    );
    try {
      final T result = await body();
      transaction.status = const SpanStatus.ok();
      return result;
    } on Object catch (error, stackTrace) {
      transaction.throwable = error;
      transaction.status = const SpanStatus.internalError();
      // Les `ApiException` sont déjà remontées — avec leur `correlationId` — par
      // la chaîne d'intercepteurs (SC-010) ; les recapturer ici les doublerait et
      // contournerait le tri incident / issue attendue de `reportApiFailure`.
      if (error is! ApiException) {
        unawaited(reportError(error, stackTrace: stackTrace, operation: name));
      }
      rethrow;
    } finally {
      await transaction.finish();
    }
  }
}
