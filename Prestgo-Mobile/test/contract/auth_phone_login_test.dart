// T057 — Contrat de la connexion par téléphone.
//
// Ce parcours enchaîne les deux mêmes routes que la vérification de contact, avec un
// seul paramètre de différence : `purpose: "login"`. Ce fichier vérifie la **suite**
// des deux appels, là où `auth_otp_test.dart` vérifie chaque réponse isolément.
//
// L'écart que ce test protège : omettre `purpose` ferait partir le code normalement,
// puis renverrait `{ verified, activated }` au lieu des jetons. Aucune erreur ne
// serait levée — la connexion échouerait silencieusement.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';
import 'package:prestgo_mobile/features/auth/data/dto/otp_dto.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const String phone = '+2250700000003';

/// Répond à `otp/send` puis à `otp/verify` — le parcours complet en un scénario.
ApiHarness phoneLoginHarness({required String verifyCase}) {
  final (int sendStatus, Map<String, Object?> sendBody) = fixture(
    'auth/otp_send',
    'sent',
  );
  final (int verifyStatus, Map<String, Object?> verifyBody) = fixture(
    'auth/otp_verify',
    verifyCase,
  );

  return ApiHarness(
    (RequestOptions options, int index) => options.path == '/auth/otp/send'
        ? (sendStatus, sendBody)
        : (verifyStatus, verifyBody),
  );
}

void main() {
  test('le parcours complet produit une session de plein droit', () async {
    final ApiHarness harness = phoneLoginHarness(verifyCase: 'loginTokens');
    final AuthRepository repository = AuthRepository(harness.client);

    final OtpChallenge challenge = await repository.sendOtp(
      target: phone,
      purpose: OtpPurpose.login,
    );
    final AuthTokens tokens = await repository.signInWithCode(
      target: phone,
      code: '418902',
    );

    expect(challenge.expiresInMinutes, 10);
    expect(tokens.isComplete, isTrue);
    expect(harness.callCount, 2);
  });

  test('`purpose: login` est posé sur les DEUX appels', () async {
    final ApiHarness harness = phoneLoginHarness(verifyCase: 'loginTokens');
    final AuthRepository repository = AuthRepository(harness.client);

    await repository.sendOtp(target: phone, purpose: OtpPurpose.login);
    await repository.signInWithCode(target: phone, code: '418902');

    for (final RequestOptions call in harness.adapter.calls) {
      final Object? data = call.data;
      expect(
        (data! as Map<String, Object?>)['purpose'],
        'login',
        reason: '${call.path} doit porter le motif de connexion',
      );
    }
  });

  test(
    'la réponse est un couple de jetons, jamais `{verified, activated}`',
    () async {
      final Map<String, Object?> data = fixtureData(
        'auth/otp_verify',
        'loginTokens',
      );

      expect(data.keys, containsAll(<String>['accessToken', 'refreshToken']));
      expect(
        data.containsKey('verified'),
        isFalse,
        reason:
            'confondre les deux formes ferait échouer la connexion sans erreur '
            'visible',
      );
      expect(data.containsKey('activated'), isFalse);
    },
  );

  test(
    'une réponse de vérification de contact ne passe pas pour une session',
    () async {
      // Ce que produirait un `purpose` oublié : le service répond bien 200, mais avec
      // l'autre forme. La désérialisation doit s'en apercevoir plutôt que de rendre
      // des jetons vides.
      final ApiHarness harness = ApiHarness.always(200, <String, Object?>{
        'success': true,
        'message': 'Code vérifié',
        'data': <String, Object?>{'verified': true, 'activated': false},
      });

      final AuthTokens tokens = await AuthRepository(
        harness.client,
      ).signInWithCode(target: phone, code: '418902');

      expect(
        tokens.isComplete,
        isFalse,
        reason:
            'des jetons incomplets sont détectables — SecureTokenStore refuse de '
            'les écrire, et la session ne s’ouvre pas à moitié',
      );
    },
  );

  test('401 — le code était bon, le compte ne l’est pas', () async {
    final ApiHarness harness = phoneLoginHarness(
      verifyCase: 'loginNoActiveAccount',
    );

    await expectLater(
      AuthRepository(
        harness.client,
      ).signInWithCode(target: phone, code: '418902'),
      throwsA(
        isA<ApiException>().having(
          (ApiException e) => e.isAccountNotActive,
          'compte non actif',
          isTrue,
        ),
      ),
    );
  });
}
