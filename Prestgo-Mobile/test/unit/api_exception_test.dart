// T044 — Conversion d'erreur → `ApiException`, messages de repli, `messageForField`
// et `correlationId`.
//
// Voir contracts/api-envelope.md §4 à §6. Porte G2 : c'est le seul endroit où un
// code HTTP est nommé ; partout ailleurs, seuls les prédicats sont employés.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/envelope_interceptor.dart';

DioException _dioError({
  required DioExceptionType type,
  int? statusCode,
  Object? body,
}) {
  final RequestOptions options = RequestOptions(path: '/me');
  return DioException(
    requestOptions: options,
    type: type,
    response: statusCode == null
        ? null
        : Response<Object?>(
            requestOptions: options,
            statusCode: statusCode,
            data: body,
          ),
  );
}

Map<String, Object?> _errorBody({
  String? message,
  List<Map<String, Object?>>? errors,
  String? correlationId,
}) => <String, Object?>{
  'success': false,
  'message': ?message,
  'errors': ?errors,
  if (correlationId case final String id)
    'meta': <String, Object?>{'correlationId': id},
};

void main() {
  group('Prédicats', () {
    test('classe chaque famille de code', () {
      expect(ApiException.fromResponse(statusCode: 400).isUserFixable, isTrue);
      expect(ApiException.fromResponse(statusCode: 409).isUserFixable, isTrue);
      expect(ApiException.fromResponse(statusCode: 401).isAuth, isTrue);
      expect(ApiException.fromResponse(statusCode: 403).isForbidden, isTrue);
      expect(ApiException.fromResponse(statusCode: 404).isNotFound, isTrue);
      expect(ApiException.fromResponse(statusCode: 429).isRateLimited, isTrue);
      expect(ApiException.fromResponse(statusCode: 500).isServer, isTrue);
      expect(ApiException.fromResponse(statusCode: 503).isServer, isTrue);
    });

    test(
      '`isTransient` ne couvre que le réseau et les passerelles en défaut',
      () {
        expect(const ApiException.network().isTransient, isTrue);
        expect(ApiException.fromResponse(statusCode: 502).isTransient, isTrue);
        expect(ApiException.fromResponse(statusCode: 503).isTransient, isTrue);
        expect(ApiException.fromResponse(statusCode: 504).isTransient, isTrue);

        // Une erreur 500 franche n'est pas rejouable : le service a traité la
        // requête et a échoué.
        expect(ApiException.fromResponse(statusCode: 500).isTransient, isFalse);
        expect(ApiException.fromResponse(statusCode: 429).isTransient, isFalse);
        expect(ApiException.fromResponse(statusCode: 400).isTransient, isFalse);
      },
    );
  });

  group('Messages de repli', () {
    test('réseau', () {
      expect(
        toApiException(
          _dioError(type: DioExceptionType.connectionError),
        ).message,
        ApiFallbackMessages.network,
      );
      expect(
        toApiException(
          _dioError(type: DioExceptionType.connectionTimeout),
        ).isNetwork,
        isTrue,
      );
      // `unknown` sans réponse : socket fermée, DNS, TLS — une coupure du point de
      // vue de l'utilisateur.
      expect(
        toApiException(_dioError(type: DioExceptionType.unknown)).isNetwork,
        isTrue,
      );
    });

    test('429 — message d’attente générique, jamais le texte du service', () {
      final ApiException error = ApiException.fromResponse(
        statusCode: 429,
        body: _errorBody(message: 'Too many requests, retry in 42s'),
      );
      expect(error.message, ApiFallbackMessages.rateLimited);
      expect(error.rawMessage, 'Too many requests, retry in 42s');
    });

    test('5xx sans message affichable', () {
      expect(
        ApiException.fromResponse(statusCode: 500).message,
        ApiFallbackMessages.server,
      );
    });

    test('corps illisible — page d’erreur d’un intermédiaire', () {
      final ApiException error = ApiException.fromResponse(
        statusCode: 502,
        body: '<html>Bad Gateway</html>',
      );
      expect(error.message, ApiFallbackMessages.server);
      expect(error.isTransient, isTrue);
    });

    test('annulation', () {
      expect(
        toApiException(_dioError(type: DioExceptionType.cancel)).isCancelled,
        isTrue,
      );
    });
  });

  group('Messages assainis (§4)', () {
    test('`Invalid credentials` devient un message affichable', () {
      final ApiException error = ApiException.fromResponse(
        statusCode: 401,
        body: _errorBody(message: 'Invalid credentials'),
      );
      expect(error.message, ApiFallbackMessages.invalidCredentials);
      expect(error.rawMessage, 'Invalid credentials');
    });

    test(
      '`Account is not active` devient générique et reste reconnaissable',
      () {
        final ApiException error = ApiException.fromResponse(
          statusCode: 401,
          body: _errorBody(message: 'Account is not active'),
        );
        expect(error.message, ApiFallbackMessages.accountNotActive);
        expect(error.isAccountNotActive, isTrue);
      },
    );

    test('les messages techniques de jeton ne sont jamais affichés', () {
      for (final String raw in <String>[
        'Bearer token required',
        'Invalid access token',
      ]) {
        final ApiException error = ApiException.fromResponse(
          statusCode: 401,
          body: _errorBody(message: raw),
        );
        expect(error.message, ApiFallbackMessages.unknown);
        expect(error.message, isNot(contains('token')));
      }
    });

    test(
      'tout autre message métier est affiché tel quel, nombre interpolé compris',
      () {
        const String serverMessage =
            'Vous avez 2 missions confirmées : annulez-les avant de désactiver '
            'votre compte.';
        final ApiException error = ApiException.fromResponse(
          statusCode: 400,
          body: _errorBody(message: serverMessage),
        );
        // Reconstruire ce texte côté client produirait un nombre faux (FR-088).
        expect(error.message, serverMessage);
      },
    );

    test('403 sans profil prestataire est reconnaissable', () {
      final ApiException error = ApiException.fromResponse(
        statusCode: 403,
        body: _errorBody(message: "Ce compte n'a pas de profil prestataire"),
      );
      expect(error.hasNoProviderProfile, isTrue);
    });
  });

  group('messageForField', () {
    test('associe chaque message à son champ, imbriqué compris', () {
      final ApiException error = ApiException.fromResponse(
        statusCode: 400,
        body: _errorBody(
          message: 'Validation échouée',
          errors: <Map<String, Object?>>[
            <String, Object?>{
              'field': 'email',
              'code': 'invalid',
              'message': 'Email invalide',
            },
            <String, Object?>{
              'field': 'slots.1.startTime',
              'code': 'invalid_time',
              'message': 'Heure invalide',
            },
          ],
        ),
      );

      expect(error.messageForField('email'), 'Email invalide');
      expect(error.messageForField('slots.1.startTime'), 'Heure invalide');
      expect(error.messageForField('phone'), isNull);
      expect(error.hasFieldErrors, isTrue);
      expect(error.fieldMessages, hasLength(2));
    });

    test('un conflit métier n’a pas de `field` : il relève de la bannière', () {
      final ApiException error = ApiException.fromResponse(
        statusCode: 409,
        body: _errorBody(message: 'Cet email ou ce numéro est déjà utilisé'),
      );

      expect(error.hasFieldErrors, isFalse);
      expect(error.fieldMessages, isEmpty);
      expect(error.message, 'Cet email ou ce numéro est déjà utilisé');
      expect(error.isConflict, isTrue);
    });
  });

  group('correlationId', () {
    test('est extrait de `meta` sur toutes les erreurs', () {
      final ApiException error = ApiException.fromResponse(
        statusCode: 500,
        body: _errorBody(message: 'Erreur interne', correlationId: 'req-abc-1'),
      );
      expect(error.correlationId, 'req-abc-1');
    });

    test('reste nul quand le service n’en fournit pas', () {
      expect(ApiException.fromResponse(statusCode: 500).correlationId, isNull);
    });

    test('n’apparaît pas dans le message affiché', () {
      final ApiException error = ApiException.fromResponse(
        statusCode: 500,
        body: _errorBody(message: 'Erreur interne', correlationId: 'req-abc-1'),
      );
      expect(error.message, isNot(contains('req-abc-1')));
    });
  });

  test('une exception déjà convertie n’est pas reconstruite', () {
    const ApiException original = ApiException.network();
    final DioException wrapped = DioException(
      requestOptions: RequestOptions(path: '/me'),
      error: original,
    );
    expect(identical(toApiException(wrapped), original), isTrue);
  });
}
