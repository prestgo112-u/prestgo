// Câblage de la couche réseau — non-régression.
//
// `test/unit/auth_interceptor_test.dart` vérifie le comportement de l'intercepteur,
// construit à la main. Ce fichier-ci vérifie autre chose : que l'instance **assemblée
// par les providers** sait réellement rejouer.
//
// La distinction n'est pas théorique. L'intercepteur a longtemps eu son propre
// provider, dont la fermeture de rejeu lisait `apiDioProvider` — lequel observait cet
// intercepteur. Riverpod refuse cette dépendance circulaire, mais seulement à
// l'exécution, et seulement au premier renouvellement : le rejeu remontait alors une
// `CircularDependencyError` que `dio` présentait comme une **erreur réseau**. Tous les
// tests d'intercepteur passaient, puisqu'ils n'utilisaient pas les providers.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/config/app_environment.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';

import '../support/api_harness.dart';
import '../support/recording_adapter.dart';
import '../support/screen_harness.dart';

void main() {
  late LocalDatabase database;
  late InMemoryTokenStore tokenStore;
  late RecordingAdapter adapter;
  late ProviderContainer container;
  late bool accessTokenExpired;

  setUp(() {
    accessTokenExpired = true;
    database = LocalDatabase.memory();
    tokenStore = InMemoryTokenStore()
      ..tokens = const AuthTokens(
        accessToken: 'périmé',
        refreshToken: 'renouvellement',
      );

    adapter = RecordingAdapter((RequestOptions options, int index) {
      if (options.path == '/auth/refresh') {
        accessTokenExpired = false;
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
      if (accessTokenExpired) {
        return (
          401,
          <String, Object?>{
            'success': false,
            'message': 'Invalid access token',
          },
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

    final AppEnvironment environment = AppEnvironment.fromDefines(
      apiBaseUrl: kTestBaseUrl,
      networkLogsEnabled: false,
    );

    container = ProviderContainer(
      overrides: <Override>[
        appEnvironmentProvider.overrideWithValue(environment),
        localDatabaseProvider.overrideWithValue(database),
        secureTokenStoreProvider.overrideWithValue(tokenStore),
        refreshDioProvider.overrideWith(
          (Ref ref) =>
              buildRefreshDio(environment)..httpClientAdapter = adapter,
        ),
        apiDioProvider.overrideWith(
          (Ref ref) => buildAuthenticatedDio(
            environment: environment,
            tokenStore: tokenStore,
            refreshDio: ref.watch(refreshDioProvider),
            onSessionExpired: () async {},
          )..httpClientAdapter = adapter,
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('l’instance issue des providers rejoue après renouvellement', () async {
    final ApiEnvelope<String> envelope = await container
        .read(apiClientProvider)
        .get<String>(
          '/me',
          parse: parseObject<String>((JsonMap json) => json['id']! as String),
        );

    expect(envelope.data, 'u-1');
    expect(adapter.countFor('/auth/refresh'), 1);
    expect(
      adapter.countFor('/me'),
      2,
      reason: 'une requête refusée, puis la même rejouée avec le jeton frais',
    );
    expect(tokenStore.tokens?.refreshToken, 'renouvellement-2');
  });

  test('un seul renouvellement pour des requêtes concurrentes', () async {
    await Future.wait<void>(<Future<void>>[
      for (int i = 0; i < 5; i++)
        container
            .read(apiClientProvider)
            .get<String>(
              '/me',
              parse: parseObject<String>(
                (JsonMap json) => json['id']! as String,
              ),
            )
            .then((_) {}),
    ]);

    expect(
      adapter.countFor('/auth/refresh'),
      1,
      reason:
          'cinq renouvellements atteindraient le plafond de 30 appels par '
          'minute (invariant 1 de R8)',
    );
    expect(adapter.countFor('/me'), 10);
  });
}
