// T054 — Contrat de `POST /auth/register` (opération 1).
//
// Les réponses sont les captures réelles de `test/fixtures/auth/register.json`.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';
import 'package:prestgo_mobile/features/auth/data/dto/auth_requests.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const RegisterRequest request = RegisterRequest(
  email: 'nouveau.client@prestgo.test',
  password: 'prestgo123!',
  firstName: 'Awa',
);

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'auth/register',
    caseName,
  );
  return ApiHarness.always(status, body);
}

void main() {
  test('201 — le compte est créé au statut `pending`', () async {
    final ApiHarness harness = harnessFor('created');

    final RegisteredAccount account = await AuthRepository(
      harness.client,
    ).register(request);

    expect(account.id, isNotEmpty);
    expect(account.status, 'pending');
    expect(
      account.isPending,
      isTrue,
      reason: 'un compte neuf ne peut pas se connecter avant vérification',
    );
    expect(account.email, 'nouveau.client@prestgo.test');
  });

  test('le chemin ne répète pas le préfixe de la base', () async {
    final ApiHarness harness = harnessFor('created');

    await AuthRepository(harness.client).register(request);

    expect(harness.lastUrl, '$kTestBaseUrl/auth/register');
    expect(
      RegExp('api/v1').allMatches(harness.lastUrl).length,
      1,
      reason: 'le préfixe est déjà dans la base configurée',
    );
  });

  test('les champs facultatifs absents ne sont pas envoyés', () async {
    final ApiHarness harness = harnessFor('created');

    await AuthRepository(harness.client).register(request);

    final Map<String, Object?> body = harness.lastBody;
    expect(body['email'], 'nouveau.client@prestgo.test');
    expect(body['firstName'], 'Awa');
    expect(
      body.containsKey('phone'),
      isFalse,
      reason:
          'le service applique `whitelist: true` : un champ absent est plus sûr '
          'qu’un champ à null',
    );
    expect(body.containsKey('lastName'), isFalse);
  });

  test(
    'inscription par téléphone — le destinataire du code est le numéro',
    () async {
      final ApiHarness harness = harnessFor('createdByPhone');

      final RegisteredAccount account = await AuthRepository(harness.client)
          .register(
            const RegisterRequest(
              phone: '+2250700000042',
              password: 'prestgo123!',
            ),
          );

      expect(account.email, isNull);
      expect(account.verificationTarget, '+2250700000042');
    },
  );

  test('400 — les erreurs de validation désignent leur champ', () async {
    final ApiHarness harness = harnessFor('invalidFields');

    await expectLater(
      AuthRepository(harness.client).register(request),
      throwsA(
        isA<ApiException>()
            .having(
              (ApiException e) => e.isUserFixable,
              'isUserFixable',
              isTrue,
            )
            .having(
              (ApiException e) => e.messageForField('email'),
              'message du champ email',
              'Adresse email invalide',
            )
            .having(
              (ApiException e) => e.fieldMessages.keys,
              'champs en erreur',
              containsAll(<String>['email', 'password']),
            ),
      ),
    );
  });

  test('400 sans champ — le message va en bannière', () async {
    final ApiHarness harness = harnessFor('missingContact');

    await expectLater(
      AuthRepository(harness.client).register(request),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.hasFieldErrors, 'champs', isFalse)
            .having(
              (ApiException e) => e.message,
              'message',
              'Un email ou un numéro de téléphone est obligatoire',
            ),
      ),
    );
  });

  test('409 — doublon, message métier affiché tel quel', () async {
    final ApiHarness harness = harnessFor('duplicate');

    await expectLater(
      AuthRepository(harness.client).register(request),
      throwsA(
        isA<ApiException>()
            .having((ApiException e) => e.isConflict, 'isConflict', isTrue)
            .having(
              (ApiException e) => e.message,
              'message',
              'Un compte existe déjà avec cet email ou ce numéro',
            ),
      ),
    );
  });

  test('429 — message d’attente, et aucun rejeu', () async {
    final ApiHarness harness = harnessFor('rateLimited');

    await expectLater(
      AuthRepository(harness.client).register(request),
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
    expect(
      harness.callCount,
      1,
      reason: 'rejouer un 429 ne ferait qu’aggraver le débit (porte G4)',
    );
  });

  test('l’identifiant de corrélation est conservé pour le support', () async {
    final ApiHarness harness = harnessFor('duplicate');

    await expectLater(
      AuthRepository(harness.client).register(request),
      throwsA(
        isA<ApiException>().having(
          (ApiException e) => e.correlationId,
          'correlationId',
          isNotNull,
        ),
      ),
    );
  });
}
