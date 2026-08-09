// T059 — Contrat du profil (opérations 9 à 12) et de son cache (T080).
//
// Trois choses s'y jouent :
//   • la **projection de routage** — `status`, `hasProviderProfile` et
//     `providerValidationStatus`, et rien d'autre. `roles` est renvoyé par le service
//     mais ne doit jamais entrer dans la décision ;
//   • le **cache du profil**, qui permet d'aiguiller au démarrage sans réseau ;
//   • les deux routes qui répondent **401 pour un mot de passe erroné** — leur
//     requête doit être marquée pour que l'intercepteur n'y voie pas une session
//     expirée.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/request_markers.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/features/profile/data/me_repository.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

late LocalDatabase database;
late CacheDao cache;

ApiHarness harnessFor(String file, String caseName) {
  final (int status, Map<String, Object?> body) = fixture(file, caseName);
  return ApiHarness.always(status, body);
}

MeRepository repositoryOn(ApiHarness harness) =>
    MeRepository(harness.client, cache);

void main() {
  setUp(() {
    database = LocalDatabase.memory();
    cache = CacheDao(database);
  });

  tearDown(() => database.close());

  group('Opération 9 — GET /me', () {
    test('un client actif atterrit dans l’espace client', () async {
      final ApiHarness harness = harnessFor('auth/me', 'client');

      final Me me = await repositoryOn(harness).fetch();

      expect(me.status, UserStatus.active);
      expect(me.hasProviderProfile, isFalse);
      expect(me.routing.isActive, isTrue);
      expect(me.displayName, 'Awa Koné');
      expect(harness.lastUrl, '$kTestBaseUrl/me');
    });

    test('`hasClientProfile` à faux n’empêche rien (FR-015)', () async {
      final ApiHarness harness = harnessFor(
        'auth/me',
        'clientWithUnverifiedPhone',
      );

      final Me me = await repositoryOn(harness).fetch();

      expect(me.hasClientProfile, isFalse);
      expect(
        me.routing.isActive,
        isTrue,
        reason:
            'des comptes historiques ont ce drapeau à faux tout en étant clients',
      );
    });

    test('`roles` est lu mais absent de la projection de routage', () async {
      final ApiHarness harness = harnessFor('auth/me', 'admin');

      final Me me = await repositoryOn(harness).fetch();

      expect(me.roles, <String>['super_admin']);
      expect(
        me.routing,
        const RoutingProfile(
          userStatus: UserStatus.active,
          hasProviderProfile: false,
        ),
        reason:
            'un rôle d’administration ne change pas l’écran d’atterrissage '
            '(FR-013)',
      );
    });

    test('les trois états de dossier prestataire sont distingués', () async {
      Future<ProviderValidationStatus?> validationOf(String caseName) async =>
          (await repositoryOn(
            harnessFor('auth/me', caseName),
          ).fetch()).providerValidationStatus;

      expect(
        await validationOf('providerApproved'),
        ProviderValidationStatus.approved,
      );
      expect(
        await validationOf('providerPendingReview'),
        ProviderValidationStatus.pendingReview,
      );
      expect(
        await validationOf('providerProfileIncomplete'),
        ProviderValidationStatus.profileIncomplete,
      );
    });

    test('un compte suspendu est reconnu comme non actif', () async {
      final ApiHarness harness = harnessFor('auth/me', 'suspended');

      final Me me = await repositoryOn(harness).fetch();

      expect(me.status, UserStatus.suspended);
      expect(me.routing.isActive, isFalse);
    });

    test(
      'les contacts non vérifiés alimentent les pastilles du profil',
      () async {
        final ApiHarness harness = harnessFor(
          'auth/me',
          'clientWithUnverifiedPhone',
        );

        final Me me = await repositoryOn(harness).fetch();

        expect(me.unverifiedChannels, <VerificationChannel>[
          VerificationChannel.sms,
        ]);
      },
    );

    test('un compte sans nom retombe sur son contact', () async {
      final ApiHarness harness = harnessFor('auth/me', 'pendingAccount');

      final Me me = await repositoryOn(harness).fetch();

      expect(me.firstName, isNull);
      expect(me.displayName, 'nouveau.client@prestgo.test');
    });

    test('401 — session absente', () async {
      final ApiHarness harness = harnessFor('auth/me', 'unauthenticated');

      await expectLater(
        repositoryOn(harness).fetch(),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.isAuth, 'isAuth', isTrue)
              .having(
                (ApiException e) => e.message,
                'message assaini',
                ApiFallbackMessages.unknown,
              ),
        ),
      );
    });
  });

  group('Cache du profil — T080', () {
    test('une lecture réussie alimente le cache', () async {
      final ApiHarness harness = harnessFor('auth/me', 'providerApproved');
      final MeRepository repository = repositoryOn(harness);

      expect(await repository.cached(), isNull);
      final Me fetched = await repository.fetch();
      final Me? restored = await repository.cached();

      expect(restored, isNotNull);
      expect(restored, fetched);
      expect(
        restored!.routing,
        fetched.routing,
        reason: 'c’est cette projection qui permet d’aiguiller hors ligne',
      );
    });

    test('le cache ne contient aucun secret', () async {
      final ApiHarness harness = harnessFor('auth/me', 'client');
      final MeRepository repository = repositoryOn(harness);

      final Me me = await repository.fetch();
      final Map<String, Object?> stored = me.toJson();

      expect(stored.containsKey('pendingVerifications'), isFalse);
      for (final String key in stored.keys) {
        expect(
          key.toLowerCase(),
          isNot(anyOf(contains('token'), contains('password'))),
          reason: 'porte G6 : rien de sensible sur disque',
        );
      }
    });

    test('le cache ne garde qu’un seul compte', () async {
      final MeRepository first = repositoryOn(harnessFor('auth/me', 'client'));
      final MeRepository second = repositoryOn(
        harnessFor('auth/me', 'providerApproved'),
      );

      await first.fetch();
      await second.fetch();

      final Me? restored = await second.cached();
      expect(
        restored?.email,
        'provider.ready@prestgo.test',
        reason: 'un changement de compte ne doit pas laisser deux identités',
      );
    });

    test(
      'un cache illisible est écarté sans faire échouer le démarrage',
      () async {
        await cache.writeProfile(
          id: 'abc',
          payload: <String, Object?>{'id': 'abc', 'status': 'active'},
          fetchedAt: DateTime.now(),
        );

        final Me? restored = await repositoryOn(
          harnessFor('auth/me', 'client'),
        ).cached();

        // Champs manquants : les valeurs de repli s'appliquent, rien ne lève.
        expect(restored, isNotNull);
        expect(restored!.hasProviderProfile, isFalse);
      },
    );
  });

  group('Opération 10 — PATCH /me', () {
    test(
      'sans changement de contact, aucune vérification n’est demandée',
      () async {
        final ApiHarness harness = harnessFor('auth/me_patch', 'nameOnly');

        final Me me = await repositoryOn(
          harness,
        ).updateProfile(lastName: 'Koné-Diabaté');

        expect(me.pendingVerifications, isEmpty);
        expect(harness.lastBody, <String, Object?>{'lastName': 'Koné-Diabaté'});
      },
    );

    test('le canal `sms` correspond au motif `phone_verification`', () async {
      final ApiHarness harness = harnessFor('auth/me_patch', 'phoneChanged');

      final Me me = await repositoryOn(
        harness,
      ).updateProfile(phone: '+2250700000077');

      expect(me.phoneVerified, isFalse);
      expect(me.pendingVerifications, hasLength(1));
      final PendingVerification pending = me.pendingVerifications.single;
      expect(pending.channel, VerificationChannel.sms);
      expect(
        pending.channel.otpPurpose,
        'phone_verification',
        reason:
            'le service dit `sms`, la route OTP attend `phone_verification` : '
            'la correspondance ne doit exister qu’à un seul endroit',
      );
      expect(pending.target, '+2250700000077');
    });

    test('deux contacts modifiés — l’email est vérifié en premier', () async {
      final ApiHarness harness = harnessFor('auth/me_patch', 'bothChanged');

      final Me me = await repositoryOn(
        harness,
      ).updateProfile(email: 'awa.kone@prestgo.test', phone: '+2250700000077');

      expect(
        me.pendingVerifications.map((PendingVerification v) => v.channel),
        <VerificationChannel>[
          VerificationChannel.email,
          VerificationChannel.sms,
        ],
      );
    });

    test('les champs non fournis ne sont pas transmis', () async {
      final ApiHarness harness = harnessFor('auth/me_patch', 'nameOnly');

      await repositoryOn(harness).updateProfile(firstName: 'Awa');

      expect(harness.lastBody.keys, <String>['firstName']);
    });

    test('409 — contact déjà utilisé', () async {
      final ApiHarness harness = harnessFor('auth/me_patch', 'contactTaken');

      await expectLater(
        repositoryOn(harness).updateProfile(email: 'pris@prestgo.test'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.isConflict, 'isConflict', isTrue)
              .having(
                (ApiException e) => e.message,
                'message',
                'Cet email ou ce numéro est déjà utilisé',
              ),
        ),
      );
    });
  });

  group('Opération 11 — POST /me/password', () {
    test('200 — le message chiffré du service est rendu tel quel', () async {
      final ApiHarness harness = harnessFor(
        'auth/me_password_and_delete',
        'passwordChanged',
      );

      final PasswordChangeResult result = await repositoryOn(
        harness,
      ).changePassword(currentPassword: 'ancien123', newPassword: 'nouveau123');

      expect(result.revokedSessions, 2);
      expect(
        result.message,
        'Mot de passe mis à jour. 2 autre(s) session(s) fermée(s).',
        reason:
            'l’application ne saurait pas reconstruire ce décompte (FR-088)',
      );
    });

    test('la requête interdit le renouvellement automatique', () async {
      final ApiHarness harness = harnessFor(
        'auth/me_password_and_delete',
        'passwordChanged',
      );

      await repositoryOn(
        harness,
      ).changePassword(currentPassword: 'ancien123', newPassword: 'nouveau123');

      expect(
        harness.lastCall.extra[kSkipRefreshExtra],
        isTrue,
        reason:
            'un mot de passe actuel erroné répond 401 : sans ce marqueur, '
            'l’intercepteur renouvellerait, rejouerait, puis déconnecterait',
      );
    });

    test(
      '401 — mot de passe actuel erroné, la session n’est pas en cause',
      () async {
        final ApiHarness harness = harnessFor(
          'auth/me_password_and_delete',
          'passwordWrongCurrent',
        );

        await expectLater(
          repositoryOn(
            harness,
          ).changePassword(currentPassword: 'faux', newPassword: 'nouveau123'),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.isAuth, 'isAuth', isTrue)
                .having(
                  (ApiException e) => e.message,
                  'message',
                  'Mot de passe actuel incorrect',
                ),
          ),
        );
        expect(harness.callCount, 1, reason: 'aucun rejeu');
      },
    );

    test('400 — nouveau mot de passe identique à l’ancien', () async {
      final ApiHarness harness = harnessFor(
        'auth/me_password_and_delete',
        'passwordSameAsCurrent',
      );

      await expectLater(
        repositoryOn(harness).changePassword(
          currentPassword: 'prestgo123!',
          newPassword: 'prestgo123!',
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            // Apostrophe droite : c'est celle du service, et le message est
            // affiché tel quel.
            "Le nouveau mot de passe doit être différent de l'ancien",
          ),
        ),
      );
    });
  });

  group('Opération 12 — DELETE /me', () {
    test(
      '200 — le compte est désactivé, le mot de passe part dans le corps',
      () async {
        final ApiHarness harness = harnessFor(
          'auth/me_password_and_delete',
          'deactivated',
        );

        await repositoryOn(harness).deactivate(password: 'prestgo123!');

        expect(harness.lastCall.method, 'DELETE');
        expect(harness.lastBody['password'], 'prestgo123!');
        expect(harness.lastCall.extra[kSkipRefreshExtra], isTrue);
      },
    );

    test(
      '400 — le décompte des missions bloquantes est affiché tel quel',
      () async {
        final ApiHarness harness = harnessFor(
          'auth/me_password_and_delete',
          'deactivateBlockedByMissions',
        );

        await expectLater(
          repositoryOn(harness).deactivate(password: 'prestgo123!'),
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
                  'Désactivation impossible : 2 mission(s) confirmée(s) ou en '
                      "cours. Terminez-les ou annulez-les d'abord.",
                ),
          ),
        );
      },
    );

    test('401 — mot de passe incorrect', () async {
      final ApiHarness harness = harnessFor(
        'auth/me_password_and_delete',
        'deactivateWrongPassword',
      );

      await expectLater(
        repositoryOn(harness).deactivate(password: 'faux'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            'Mot de passe incorrect',
          ),
        ),
      );
    });
  });
}
