// T058 — Contrat du mot de passe oublié et de la réinitialisation (opérations 7 et 8).
//
// Le test central de ce fichier n'est pas fonctionnel mais **sécuritaire** : la
// réponse à la demande doit être rigoureusement identique qu'un compte existe ou non.
// Sans cette garantie, la route deviendrait un moyen de découvrir quelles adresses
// sont inscrites sur la plateforme.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';
import 'package:prestgo_mobile/features/auth/data/dto/auth_requests.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'auth/password_reset',
    caseName,
  );
  return ApiHarness.always(status, body);
}

void main() {
  group('Demande — opération 7', () {
    test('200 — message neutre', () async {
      final ApiHarness harness = harnessFor('forgotAccepted');

      final PasswordResetRequestResult result = await AuthRepository(
        harness.client,
      ).requestPasswordReset('client.demo@prestgo.test');

      expect(
        result.message,
        'Si un compte existe pour cette adresse, un lien de réinitialisation a '
        'été envoyé.',
      );
      expect(result.devToken, isNull);
    });

    test('le message ne dit pas si l’adresse est inscrite', () {
      // Une adresse connue et une adresse inconnue produisent la MÊME capture : le
      // service ne varie que sur `devToken`, absent en production.
      final Map<String, Object?> known = fixtureBody(
        'auth/password_reset',
        'forgotAccepted',
      );
      final Map<String, Object?> withDevToken = fixtureBody(
        'auth/password_reset',
        'forgotAcceptedWithDevToken',
      );

      expect(known['message'], withDevToken['message']);
      expect(known['success'], withDevToken['success']);
    });

    test('le jeton de développement est lu quand il est exposé', () async {
      final ApiHarness harness = harnessFor('forgotAcceptedWithDevToken');

      final PasswordResetRequestResult result = await AuthRepository(
        harness.client,
      ).requestPasswordReset('client.demo@prestgo.test');

      expect(result.devToken, hasLength(64));
    });

    test('400 — email mal formé', () async {
      final ApiHarness harness = harnessFor('forgotInvalidEmail');

      await expectLater(
        AuthRepository(harness.client).requestPasswordReset('pas-un-email'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.messageForField('email'),
            'champ email',
            'Adresse email invalide',
          ),
        ),
      );
    });
  });

  group('Réinitialisation — opération 8', () {
    test('200 — le message du service est rendu à l’appelant', () async {
      final ApiHarness harness = harnessFor('resetDone');

      final String message = await AuthRepository(
        harness.client,
      ).resetPassword(token: 'a' * 64, password: 'nouveau123');

      expect(message, 'Mot de passe mis à jour');
      expect(harness.lastBody['token'], hasLength(64));
      expect(harness.lastBody['password'], 'nouveau123');
    });

    test(
      '400 — un seul message pour jeton inconnu, consommé ou expiré',
      () async {
        final ApiHarness harness = harnessFor('resetInvalidToken');

        await expectLater(
          AuthRepository(
            harness.client,
          ).resetPassword(token: 'b' * 64, password: 'nouveau123'),
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
                  'Lien de réinitialisation invalide ou expiré',
                ),
          ),
        );
      },
    );

    test('400 — un fragment de jeton est refusé, champ désigné', () async {
      final ApiHarness harness = harnessFor('resetTokenTooShort');

      await expectLater(
        AuthRepository(
          harness.client,
        ).resetPassword(token: 'abc', password: 'nouveau123'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.messageForField('token'),
            'champ token',
            'Jeton de réinitialisation invalide',
          ),
        ),
      );
    });

    test(
      'la longueur minimale locale n’est pas plus stricte que le service',
      () {
        expect(
          AuthLimits.passwordResetTokenMinLength,
          10,
          reason: '`@MinLength(10)` sur ResetPasswordBodyDto',
        );
        expect(
          AuthLimits.passwordResetTokenLifetime,
          const Duration(minutes: 30),
          reason: 'RESET_TOKEN_TTL_MINUTES du service',
        );
      },
    );
  });
}
