// T045 — `AuthInterceptor` : les quatre invariants de R8.
//
//   1. un seul renouvellement pour N requêtes concurrentes ;
//   2. rotation enregistrée (le nouveau jeton de renouvellement remplace l'ancien) ;
//   3. rejeu unique — un second 401 met fin à la session ;
//   4. routes d'authentification exclues du renouvellement.
//
// Plus : échec du renouvellement → purge et fermeture de session.

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:prestgo_mobile/core/api/auth_interceptor.dart';
import 'package:prestgo_mobile/core/api/envelope_interceptor.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';

import '../support/recording_adapter.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

Map<String, Object?> tokensBody(String access, String refresh) =>
    <String, Object?>{
      'success': true,
      'data': <String, Object?>{'accessToken': access, 'refreshToken': refresh},
    };

const Map<String, Object?> okBody = <String, Object?>{
  'success': true,
  'data': <String, Object?>{'id': 'u-1'},
};

const Map<String, Object?> unauthorizedBody = <String, Object?>{
  'success': false,
  'message': 'Invalid access token',
};

void main() {
  late Map<String, String> storage;
  late MockSecureStorage secureStorage;
  late SecureTokenStore tokenStore;
  late int sessionExpiredCount;

  setUp(() {
    storage = <String, String>{};
    secureStorage = MockSecureStorage();
    sessionExpiredCount = 0;

    when(
      () => secureStorage.read(key: any(named: 'key')),
    ).thenAnswer((Invocation i) async => storage[i.namedArguments[#key]]);
    when(
      () => secureStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((Invocation i) async {
      storage[i.namedArguments[#key] as String] =
          i.namedArguments[#value] as String;
    });
    when(() => secureStorage.delete(key: any(named: 'key'))).thenAnswer((
      Invocation i,
    ) async {
      storage.remove(i.namedArguments[#key]);
    });

    tokenStore = SecureTokenStore(storage: secureStorage);
  });

  /// Monte le client complet et son instance de renouvellement séparée.
  Future<(Dio, RecordingAdapter, RecordingAdapter)> buildClient({
    required (int, Object?) Function(RequestOptions, int) api,
    required (int, Object?) Function(RequestOptions, int) refresh,
  }) async {
    final RecordingAdapter apiAdapter = RecordingAdapter(api);
    final RecordingAdapter refreshAdapter = RecordingAdapter(refresh);

    final Dio refreshDio = Dio(BaseOptions(baseUrl: 'https://x.test/api/v1'))
      ..httpClientAdapter = refreshAdapter
      ..interceptors.add(const EnvelopeInterceptor());

    final Dio dio = Dio(BaseOptions(baseUrl: 'https://x.test/api/v1'))
      ..httpClientAdapter = apiAdapter;

    dio.interceptors.addAll(<Interceptor>[
      const EnvelopeInterceptor(),
      AuthInterceptor(
        tokenStore: tokenStore,
        refreshDio: refreshDio,
        client: () => dio,
        onSessionExpired: () async => sessionExpiredCount++,
      ),
    ]);

    return (dio, apiAdapter, refreshAdapter);
  }

  group('Invariant 1 — un seul renouvellement pour N requêtes concurrentes', () {
    test(
      'trois requêtes parallèles ne déclenchent qu’un appel de renouvellement',
      () async {
        await tokenStore.write(
          const AuthTokens(accessToken: 'vieux', refreshToken: 'r-1'),
        );

        final (
          Dio dio,
          RecordingAdapter apiAdapter,
          RecordingAdapter refreshAdapter,
        ) = await buildClient(
          // Toute requête portant l'ancien jeton est refusée ; le nouveau passe.
          api: (RequestOptions o, int _) =>
              o.headers['Authorization'] == 'Bearer neuf'
              ? (200, okBody)
              : (401, unauthorizedBody),
          refresh: (RequestOptions o, int _) =>
              (200, tokensBody('neuf', 'r-2')),
        );

        final List<Response<Object?>> responses =
            await Future.wait(<Future<Response<Object?>>>[
              dio.get<Object?>('/me'),
              dio.get<Object?>('/me/addresses'),
              dio.get<Object?>('/me/missions'),
            ]);

        expect(
          responses.every((Response<Object?> r) => r.statusCode == 200),
          isTrue,
        );
        expect(
          refreshAdapter.countFor(kRefreshPath),
          1,
          reason:
              'dix requêtes parallèles qui renouvelleraient chacune atteindraient '
              'le plafond de 30 appels/minute',
        );
        // Chaque requête a été jouée deux fois : l'échec puis le rejeu.
        expect(apiAdapter.calls, hasLength(6));
        expect(sessionExpiredCount, 0);
      },
    );
  });

  group('Invariant 2 — rotation enregistrée', () {
    test('le nouveau jeton de renouvellement remplace l’ancien', () async {
      await tokenStore.write(
        const AuthTokens(accessToken: 'vieux', refreshToken: 'r-1'),
      );

      final (Dio dio, _, _) = await buildClient(
        api: (RequestOptions o, int _) =>
            o.headers['Authorization'] == 'Bearer neuf'
            ? (200, okBody)
            : (401, unauthorizedBody),
        refresh: (RequestOptions o, int _) => (200, tokensBody('neuf', 'r-2')),
      );

      await dio.get<Object?>('/me');

      final AuthTokens? stored = await tokenStore.read();
      expect(stored!.accessToken, 'neuf');
      expect(
        stored.refreshToken,
        'r-2',
        reason:
            'ne pas remplacer le jeton de renouvellement déconnecte '
            'l’utilisateur au renouvellement suivant',
      );
    });

    test('les deux jetons sont écrits ensemble — une seule entrée', () async {
      await tokenStore.write(
        const AuthTokens(accessToken: 'a', refreshToken: 'r'),
      );
      expect(storage.keys, <String>[SecureTokenStore.tokensKey]);
    });

    test('une écriture partielle est refusée', () {
      expect(
        () => tokenStore.write(
          const AuthTokens(accessToken: 'a', refreshToken: ''),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Invariant 3 — rejeu unique', () {
    test('un second 401 met fin à la session sans boucler', () async {
      await tokenStore.write(
        const AuthTokens(accessToken: 'vieux', refreshToken: 'r-1'),
      );

      final (
        Dio dio,
        RecordingAdapter apiAdapter,
        RecordingAdapter refreshAdapter,
      ) = await buildClient(
        // Le service refuse même le jeton fraîchement obtenu.
        api: (RequestOptions o, int _) => (401, unauthorizedBody),
        refresh: (RequestOptions o, int _) => (200, tokensBody('neuf', 'r-2')),
      );

      await expectLater(dio.get<Object?>('/me'), throwsA(isA<DioException>()));

      expect(apiAdapter.countFor('/me'), 2, reason: 'un seul rejeu');
      expect(refreshAdapter.countFor(kRefreshPath), 1);
      expect(sessionExpiredCount, 1);
      expect(await tokenStore.read(), isNull, reason: 'purge du stockage');
    });
  });

  group('Invariant 4 — routes d’authentification exclues', () {
    test('un 401 sur /auth/login ne déclenche aucun renouvellement', () async {
      await tokenStore.write(
        const AuthTokens(accessToken: 'a', refreshToken: 'r-1'),
      );

      final (Dio dio, _, RecordingAdapter refreshAdapter) = await buildClient(
        api: (RequestOptions o, int _) => (401, unauthorizedBody),
        refresh: (RequestOptions o, int _) => (200, tokensBody('neuf', 'r-2')),
      );

      await expectLater(
        dio.post<Object?>('/auth/login'),
        throwsA(isA<DioException>()),
      );

      expect(
        refreshAdapter.countFor(kRefreshPath),
        0,
        reason: 'les débits d’authentification sont serrés (5 à 10 par minute)',
      );
      expect(sessionExpiredCount, 0);
    });

    test('/auth/logout reçoit quand même l’en-tête d’autorisation', () async {
      await tokenStore.write(
        const AuthTokens(accessToken: 'a-1', refreshToken: 'r-1'),
      );

      final (Dio dio, RecordingAdapter apiAdapter, _) = await buildClient(
        api: (RequestOptions o, int _) => (200, okBody),
        refresh: (RequestOptions o, int _) => (200, tokensBody('n', 'r-2')),
      );

      await dio.post<Object?>('/auth/logout');

      expect(
        apiAdapter.calls.single.headers['Authorization'],
        'Bearer a-1',
        reason: 'sans l’en-tête, le service ne sait pas quelle session fermer',
      );
    });

    test('le renouvellement lui-même ne porte pas l’en-tête', () async {
      await tokenStore.write(
        const AuthTokens(accessToken: 'vieux', refreshToken: 'r-1'),
      );

      final (Dio dio, _, RecordingAdapter refreshAdapter) = await buildClient(
        api: (RequestOptions o, int _) =>
            o.headers['Authorization'] == 'Bearer neuf'
            ? (200, okBody)
            : (401, unauthorizedBody),
        refresh: (RequestOptions o, int _) => (200, tokensBody('neuf', 'r-2')),
      );

      await dio.get<Object?>('/me');

      final RequestOptions refreshCall = refreshAdapter.calls.single;
      expect(refreshCall.headers.containsKey('Authorization'), isFalse);
      expect(
        (refreshCall.data! as Map<String, Object?>)['refreshToken'],
        'r-1',
      );
    });
  });

  group('Échec du renouvellement', () {
    test('purge le stockage et ferme la session', () async {
      await tokenStore.write(
        const AuthTokens(accessToken: 'vieux', refreshToken: 'r-1'),
      );

      final (Dio dio, _, _) = await buildClient(
        api: (RequestOptions o, int _) => (401, unauthorizedBody),
        // Compte suspendu entre-temps : le renouvellement est refusé.
        refresh: (RequestOptions o, int _) => (
          401,
          <String, Object?>{
            'success': false,
            'message': 'Invalid refresh token',
          },
        ),
      );

      await expectLater(dio.get<Object?>('/me'), throwsA(isA<DioException>()));

      expect(await tokenStore.read(), isNull);
      expect(sessionExpiredCount, 1);
    });

    test(
      'une session absente ferme immédiatement, sans appel réseau',
      () async {
        final (Dio dio, _, RecordingAdapter refreshAdapter) = await buildClient(
          api: (RequestOptions o, int _) => (401, unauthorizedBody),
          refresh: (RequestOptions o, int _) => (200, tokensBody('n', 'r')),
        );

        await expectLater(
          dio.get<Object?>('/me'),
          throwsA(isA<DioException>()),
        );

        expect(refreshAdapter.countFor(kRefreshPath), 0);
        expect(sessionExpiredCount, 1);
      },
    );
  });

  test('un jeton stocké illisible est purgé plutôt que servi', () async {
    storage[SecureTokenStore.tokensKey] = 'ceci-n-est-pas-du-json';
    expect(await tokenStore.read(), isNull);
    expect(storage.containsKey(SecureTokenStore.tokensKey), isFalse);
  });
}
