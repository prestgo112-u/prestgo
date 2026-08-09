// Couverture du `correlationId` sur les incidents remontés (T243, SC-010).
//
// Deux étages, deux vérités :
//   1. la chaîne d'intercepteurs ne relaie au rapport d'incident que les échecs
//      **définitifs** — jamais un 401 rattrapé par le renouvellement — et
//      l'exception relayée porte le `meta.correlationId` du service ;
//   2. `ErrorReporter` remonte les incidents et eux seuls : coupure réseau,
//      saisie invalide, débit dépassé et session expirée sont des issues
//      attendues, pas des incidents.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/config/app_environment.dart';
import 'package:prestgo_mobile/core/error/error_reporter.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../support/api_harness.dart';
import '../support/recording_adapter.dart';
import '../support/screen_harness.dart';

class _MockHub extends Mock implements Hub {}

void main() {
  group('IncidentReportingInterceptor (chaîne assemblée)', () {
    late InMemoryTokenStore tokenStore;
    late List<(ApiException, String)> incidents;

    setUp(() {
      tokenStore = InMemoryTokenStore()
        ..tokens = const AuthTokens(
          accessToken: 'accès',
          refreshToken: 'renouvellement',
        );
      incidents = <(ApiException, String)>[];
    });

    ApiClient clientWith(AdapterScenario respond) {
      final AppEnvironment environment = AppEnvironment.fromDefines(
        apiBaseUrl: kTestBaseUrl,
        networkLogsEnabled: false,
      );
      final Dio refreshDio = buildRefreshDio(environment);
      final RecordingAdapter adapter = RecordingAdapter(respond);
      refreshDio.httpClientAdapter = adapter;
      final Dio dio = buildAuthenticatedDio(
        environment: environment,
        tokenStore: tokenStore,
        refreshDio: refreshDio,
        onSessionExpired: () async {},
        onIncident: (ApiException exception, String path) =>
            incidents.add((exception, path)),
      )..httpClientAdapter = adapter;
      return ApiClient(dio);
    }

    test('un échec définitif est relayé une seule fois, avec son '
        'correlationId', () async {
      final ApiClient client = clientWith(
        (RequestOptions options, int index) => (
          500,
          <String, Object?>{
            'success': false,
            'message': 'Erreur interne',
            'meta': <String, Object?>{'correlationId': 'cid-500'},
          },
        ),
      );

      await expectLater(
        client.post<JsonMap>('/missions', parse: parseObject(identityJson)),
        throwsA(isA<ApiException>()),
      );

      expect(incidents, hasLength(1));
      final (ApiException exception, String path) = incidents.single;
      expect(exception.correlationId, 'cid-500');
      expect(path, '/missions');
    });

    test(
      'un 401 rattrapé par le renouvellement n’est pas un incident',
      () async {
        bool expired = true;
        final ApiClient client = clientWith((
          RequestOptions options,
          int index,
        ) {
          if (options.path == '/auth/refresh') {
            expired = false;
            return (
              200,
              <String, Object?>{
                'success': true,
                'data': <String, Object?>{
                  'accessToken': 'frais',
                  'refreshToken': 'renouvellement-2',
                },
              },
            );
          }
          if (expired) {
            return (
              401,
              <String, Object?>{'success': false, 'message': 'Invalid token'},
            );
          }
          return (
            200,
            <String, Object?>{
              'success': true,
              'data': <String, Object?>{'id': 'u-1'},
            },
          );
        });

        final ApiEnvelope<JsonMap> envelope = await client.get<JsonMap>(
          '/me',
          parse: parseObject(identityJson),
        );

        expect(envelope.data?['id'], 'u-1');
        expect(
          incidents,
          isEmpty,
          reason: 'seuls les échecs définitifs sont des incidents',
        );
      },
    );
  });

  group('ErrorReporter.reportApiFailure', () {
    late _MockHub hub;
    late ErrorReporter reporter;

    setUp(() {
      hub = _MockHub();
      when(
        () => hub.captureException(
          any<Object>(),
          stackTrace: any<Object?>(named: 'stackTrace'),
          hint: any<Hint?>(named: 'hint'),
          withScope: any<ScopeCallback?>(named: 'withScope'),
        ),
      ).thenAnswer((_) async => const SentryId.empty());
      reporter = ErrorReporter(hub: hub);
    });

    void expectCaptured({required int times}) => verify(
      () => hub.captureException(
        any<Object>(),
        stackTrace: any<Object?>(named: 'stackTrace'),
        hint: any<Hint?>(named: 'hint'),
        withScope: any<ScopeCallback?>(named: 'withScope'),
      ),
    ).called(times);

    test('une erreur serveur est remontée', () async {
      await reporter.reportApiFailure(
        ApiException.fromResponse(
          statusCode: 500,
          body: <String, Object?>{
            'success': false,
            'message': 'Erreur interne',
            'meta': <String, Object?>{'correlationId': 'cid-1'},
          },
        ),
      );
      expectCaptured(times: 1);
    });

    test(
      'réseau, saisie, débit et session ne sont pas des incidents',
      () async {
        await reporter.reportApiFailure(const ApiException.network());
        await reporter.reportApiFailure(
          ApiException.fromResponse(
            statusCode: 400,
            body: <String, Object?>{'success': false, 'message': 'Invalide'},
          ),
        );
        await reporter.reportApiFailure(
          ApiException.fromResponse(
            statusCode: 429,
            body: <String, Object?>{
              'success': false,
              'message': 'Trop d’appels',
            },
          ),
        );
        await reporter.reportApiFailure(
          ApiException.fromResponse(
            statusCode: 401,
            body: <String, Object?>{'success': false, 'message': 'Expirée'},
          ),
        );
        verifyNever(
          () => hub.captureException(
            any<Object>(),
            stackTrace: any<Object?>(named: 'stackTrace'),
            hint: any<Hint?>(named: 'hint'),
            withScope: any<ScopeCallback?>(named: 'withScope'),
          ),
        );
      },
    );
  });
}

/// Rend `data` tel quel — suffisant quand seul le trajet de l'erreur compte.
JsonMap identityJson(JsonMap json) => json;
