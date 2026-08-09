// T055 — Contrat des codes à usage unique (opérations 2 et 3).
//
// L'enjeu de ce fichier : `POST /auth/otp/verify` change de **forme de réponse**
// selon le motif. Les deux formes sont vérifiées ici côte à côte, et le fait que le
// dépôt les serve par deux méthodes distinctes est la garantie qu'on ne peut pas les
// confondre à l'appel.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';
import 'package:prestgo_mobile/features/auth/data/dto/otp_dto.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

ApiHarness sendHarness(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'auth/otp_send',
    caseName,
  );
  return ApiHarness.always(status, body);
}

ApiHarness verifyHarness(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'auth/otp_verify',
    caseName,
  );
  return ApiHarness.always(status, body);
}

void main() {
  group('Envoi — opération 2', () {
    test(
      '200 — la durée de validité vient du service, pas d’une constante',
      () async {
        final ApiHarness harness = sendHarness('sent');

        final OtpChallenge challenge = await AuthRepository(harness.client)
            .sendOtp(
              target: '+2250700000042',
              purpose: OtpPurpose.phoneVerification,
            );

        expect(challenge.expiresInMinutes, 10);
        expect(challenge.expiresIn, const Duration(minutes: 10));
        expect(challenge.message, 'Un code de vérification a été envoyé.');
      },
    );

    test('le motif est toujours transmis explicitement', () async {
      final ApiHarness harness = sendHarness('sent');

      await AuthRepository(harness.client).sendOtp(
        target: 'client.demo@prestgo.test',
        purpose: OtpPurpose.emailVerification,
      );

      expect(harness.lastBody['purpose'], 'email_verification');
      expect(harness.lastBody['target'], 'client.demo@prestgo.test');
    });

    test('le code de développement est lu quand le service l’expose', () async {
      final ApiHarness harness = sendHarness('sentWithDevCode');

      final OtpChallenge challenge = await AuthRepository(
        harness.client,
      ).sendOtp(target: '+2250700000042', purpose: OtpPurpose.login);

      expect(challenge.devCode, '418902');
    });

    test(
      'sans `expiresInMinutes`, l’écran retombe sur le repli local',
      () async {
        final ApiHarness harness = ApiHarness.always(200, <String, Object?>{
          'success': true,
          'data': <String, Object?>{'message': 'Un code a été envoyé.'},
        });

        final OtpChallenge challenge = await AuthRepository(harness.client)
            .sendOtp(
              target: '+2250700000042',
              purpose: OtpPurpose.phoneVerification,
            );

        expect(challenge.expiresIn, isNull);
        expect(
          AuthLimits.verificationCodeFallbackLifetime,
          const Duration(minutes: 10),
          reason: 'le repli doit rester aligné sur OTP_TTL_MINUTES du service',
        );
      },
    );

    test('429 — envoi refusé, aucun rejeu', () async {
      final ApiHarness harness = sendHarness('rateLimited');

      await expectLater(
        AuthRepository(harness.client).sendOtp(
          target: '+2250700000042',
          purpose: OtpPurpose.phoneVerification,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.isRateLimited,
            'isRateLimited',
            isTrue,
          ),
        ),
      );
      expect(harness.callCount, 1);
    });
  });

  group('Vérification d’un contact — opération 3, forme 1', () {
    test(
      '200 — `activated` vrai : le compte passe de `pending` à `active`',
      () async {
        final ApiHarness harness = verifyHarness('activated');

        final OtpVerification result = await AuthRepository(harness.client)
            .verifyContact(
              target: '+2250700000042',
              code: '418902',
              purpose: OtpPurpose.phoneVerification,
            );

        expect(result.verified, isTrue);
        expect(result.activated, isTrue);
      },
    );

    test('200 — `activated` faux : simple vérification d’un contact', () async {
      final ApiHarness harness = verifyHarness('verifiedOnly');

      final OtpVerification result = await AuthRepository(harness.client)
          .verifyContact(
            target: 'awa.kone@prestgo.test',
            code: '418902',
            purpose: OtpPurpose.emailVerification,
          );

      expect(result.verified, isTrue);
      expect(
        result.activated,
        isFalse,
        reason:
            'la suite du parcours se décide sur ce booléen, jamais sur le texte '
            'du message (FR-004)',
      );
    });

    test('les deux messages du service portent la même information', () {
      // « Compte activé » et « Code vérifié » ne sont que des libellés : ce qui
      // distingue les deux cas est `activated`.
      expect(fixtureBody('auth/otp_verify', 'activated')['message'], isNotNull);
      expect(
        fixtureData('auth/otp_verify', 'activated')['activated'],
        isNot(fixtureData('auth/otp_verify', 'verifiedOnly')['activated']),
      );
    });

    test(
      '400 — message unique pour un code faux, expiré ou consommé',
      () async {
        final ApiHarness harness = verifyHarness('invalidCode');

        await expectLater(
          AuthRepository(harness.client).verifyContact(
            target: '+2250700000042',
            code: '000000',
            purpose: OtpPurpose.phoneVerification,
          ),
          throwsA(
            isA<ApiException>()
                .having(
                  (ApiException e) => e.isUserFixable,
                  'corrigeable',
                  isTrue,
                )
                .having(
                  (ApiException e) => e.message,
                  'message',
                  'Code invalide ou expiré',
                ),
          ),
        );
      },
    );

    test(
      '401 après 5 tentatives — ce code est brûlé, pas la session',
      () async {
        final ApiHarness harness = verifyHarness('tooManyAttempts');

        await expectLater(
          AuthRepository(harness.client).verifyContact(
            target: '+2250700000042',
            code: '000000',
            purpose: OtpPurpose.phoneVerification,
          ),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.isAuth, 'isAuth', isTrue)
                .having(
                  (ApiException e) => e.message,
                  'message',
                  'Trop de tentatives. Demandez un nouveau code.',
                ),
          ),
        );
        expect(
          AuthLimits.verificationMaxAttempts,
          5,
          reason: 'aligné sur OTP_MAX_ATTEMPTS du service',
        );
      },
    );
  });

  group('Connexion par code — opération 3, forme 2', () {
    test(
      '200 — la réponse est un couple de jetons, pas `{verified, activated}`',
      () async {
        final ApiHarness harness = verifyHarness('loginTokens');

        final AuthTokens tokens = await AuthRepository(
          harness.client,
        ).signInWithCode(target: '+2250700000042', code: '418902');

        expect(tokens.isComplete, isTrue);
        expect(tokens.accessToken, startsWith('eyJ'));
        expect(tokens.refreshToken, isNotEmpty);
      },
    );

    test('`purpose: login` est toujours transmis', () async {
      final ApiHarness harness = verifyHarness('loginTokens');

      await AuthRepository(
        harness.client,
      ).signInWithCode(target: '+2250700000042', code: '418902');

      expect(
        harness.lastBody['purpose'],
        'login',
        reason:
            'omis, il vaudrait `phone_verification` : le service renverrait '
            '{verified, activated} et le parcours s’arrêterait sans erreur',
      );
    });

    test(
      '401 — le code était bon, mais aucun compte actif ne correspond',
      () async {
        final ApiHarness harness = verifyHarness('loginNoActiveAccount');

        await expectLater(
          AuthRepository(
            harness.client,
          ).signInWithCode(target: '+2250700000042', code: '418902'),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.isAuth, 'isAuth', isTrue)
                .having(
                  (ApiException e) => e.isAccountNotActive,
                  'compte non actif',
                  isTrue,
                )
                .having(
                  (ApiException e) => e.message,
                  'message assaini',
                  ApiFallbackMessages.accountNotActive,
                ),
          ),
        );
      },
    );

    test('la forme de connexion n’est jamais servie par `verifyContact`', () {
      // Garde de conception : l'assertion interdit le motif `login` sur la méthode
      // de vérification de contact, dont le type de retour ne saurait pas le porter.
      expect(
        () =>
            AuthRepository(
              ApiHarness.always(200, const <String, Object?>{}).client,
            ).verifyContact(
              target: '+2250700000042',
              code: '418902',
              purpose: OtpPurpose.login,
            ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
