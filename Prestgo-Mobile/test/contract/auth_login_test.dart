// T056 — Contrat de `POST /auth/login` (opération 4).
//
// Le point de vigilance de ce fichier est un point de **sécurité** : les deux 401 du
// service ne doivent jamais permettre de savoir si une adresse est inscrite. Le test
// « les deux 401 sont distincts pour l'application » vérifie qu'on sait les séparer ;
// celui qui suit vérifie que le message affiché, lui, ne les distingue pas.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';
import 'package:prestgo_mobile/features/auth/data/dto/auth_requests.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const LoginRequest credentials = LoginRequest(
  email: 'client.demo@prestgo.test',
  password: 'prestgo123!',
);

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'auth/login',
    caseName,
  );
  return ApiHarness.always(status, body);
}

void main() {
  test('200 — un couple de jetons complet', () async {
    final ApiHarness harness = harnessFor('authenticated');

    final AuthTokens tokens = await AuthRepository(
      harness.client,
    ).signIn(credentials);

    expect(tokens.isComplete, isTrue);
    expect(tokens.accessToken, isNotEmpty);
    expect(tokens.refreshToken, isNotEmpty);
    expect(harness.lastUrl, '$kTestBaseUrl/auth/login');
  });

  test('les jetons ne s’écrivent jamais dans un journal', () async {
    final ApiHarness harness = harnessFor('authenticated');

    final AuthTokens tokens = await AuthRepository(
      harness.client,
    ).signIn(credentials);

    expect(tokens.toString(), 'AuthTokens(<masqués>)');
    expect(tokens.toString(), isNot(contains(tokens.accessToken)));
  });

  test('401 identifiants — message unique et non discriminant', () async {
    final ApiHarness harness = harnessFor('invalidCredentials');

    await expectLater(
      AuthRepository(harness.client).signIn(credentials),
      throwsA(
        isA<ApiException>()
            .having(
              (ApiException e) => e.message,
              'message affiché',
              ApiFallbackMessages.invalidCredentials,
            )
            .having(
              (ApiException e) => e.message,
              'jamais le message technique',
              isNot('Invalid credentials'),
            ),
      ),
    );
  });

  test('401 compte non actif — reconnu, mais sans révéler davantage', () async {
    final ApiHarness harness = harnessFor('accountNotActive');

    await expectLater(
      AuthRepository(harness.client).signIn(credentials),
      throwsA(
        isA<ApiException>()
            .having(
              (ApiException e) => e.isAccountNotActive,
              'compte non actif',
              isTrue,
            )
            .having(
              (ApiException e) => e.message,
              'message',
              ApiFallbackMessages.accountNotActive,
            ),
      ),
    );
  });

  test('les deux 401 restent distinguables par l’application', () async {
    ApiException failureFor(String caseName) {
      final (int status, Map<String, Object?> body) = fixture(
        'auth/login',
        caseName,
      );
      return ApiException.fromResponse(statusCode: status, body: body);
    }

    final ApiException credentialsFailure = failureFor('invalidCredentials');
    final ApiException statusFailure = failureFor('accountNotActive');

    // Distinguables — l'écran propose la vérification dans un cas et pas l'autre…
    expect(credentialsFailure.isAccountNotActive, isFalse);
    expect(statusFailure.isAccountNotActive, isTrue);
    // …sans que le service ait révélé si l'adresse existe : le premier cas couvre
    // aussi bien un email inconnu qu'un mot de passe faux.
    expect(credentialsFailure.statusCode, statusFailure.statusCode);
  });

  test('400 — l’erreur de format désigne le champ', () async {
    final ApiHarness harness = harnessFor('invalidEmailFormat');

    await expectLater(
      AuthRepository(harness.client).signIn(credentials),
      throwsA(
        isA<ApiException>().having(
          (ApiException e) => e.messageForField('email'),
          'champ email',
          'Adresse email invalide',
        ),
      ),
    );
  });

  test('429 — 10 connexions par minute, aucun rejeu', () async {
    final ApiHarness harness = harnessFor('rateLimited');

    await expectLater(
      AuthRepository(harness.client).signIn(credentials),
      throwsA(
        isA<ApiException>()
            .having(
              (ApiException e) => e.isRateLimited,
              'isRateLimited',
              isTrue,
            )
            .having(
              (ApiException e) => e.message,
              'message',
              ApiFallbackMessages.rateLimited,
            ),
      ),
    );
    expect(harness.callCount, 1);
  });

  group('Renouvellement et déconnexion', () {
    test('la rotation renvoie DEUX nouveaux jetons', () {
      final Map<String, Object?> data = fixtureData('auth/refresh', 'rotated');
      final Map<String, Object?> before = fixtureData(
        'auth/login',
        'authenticated',
      );

      expect(data['accessToken'], isNot(before['accessToken']));
      expect(
        data['refreshToken'],
        isNot(before['refreshToken']),
        reason:
            'le jeton de renouvellement TOURNE : conserver l’ancien ferait tomber '
            'la session au renouvellement suivant',
      );
    });

    test(
      'déconnexion — le jeton de renouvellement part dans le corps',
      () async {
        final (int status, Map<String, Object?> body) = fixture(
          'auth/logout',
          'loggedOut',
        );
        final ApiHarness harness = ApiHarness.always(status, body);

        await AuthRepository(
          harness.client,
        ).signOut(refreshToken: 'refresh-42');

        expect(harness.lastBody['refreshToken'], 'refresh-42');
        expect(harness.lastUrl, '$kTestBaseUrl/auth/logout');
      },
    );

    test(
      'déconnexion sans jeton — le champ est omis, pas mis à null',
      () async {
        final (int status, Map<String, Object?> body) = fixture(
          'auth/logout',
          'loggedOut',
        );
        final ApiHarness harness = ApiHarness.always(status, body);

        await AuthRepository(harness.client).signOut();

        expect(harness.lastBody.containsKey('refreshToken'), isFalse);
      },
    );
  });
}
