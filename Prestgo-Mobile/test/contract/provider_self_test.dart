// T139 — Contrat du dossier prestataire (opérations 65 à 68).
//
// Les pièges de ces routes :
//   • le **409 de la création est un succès** — c'est la reprise d'un parcours
//     interrompu, le dépôt enchaîne sur GET et rend l'aperçu (scénario 4.3) ;
//   • le **verrou de `pending_review`** refuse tout PATCH d'identité (400) mais
//     laisse passer `availabilityStatus` seul (scénario 4.8) ;
//   • `canSubmit` pilote le bouton « Soumettre » — le compte démo approuvé a
//     `canSubmit: false` avec une checklist pourtant « complète » au sens naïf.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'provider/self',
    caseName,
  );
  return ApiHarness.always(status, body);
}

ProviderSelfRepository repositoryOn(ApiHarness harness) =>
    ProviderSelfRepository(harness.client);

void main() {
  group('Opération 65 — POST /providers/me', () {
    test(
      '201 — le corps de réponse est l’aperçu complet, checklist comprise',
      () async {
        final ApiHarness harness = harnessFor('created');

        final ProviderProfile
        profile = await repositoryOn(harness).createProfile(
          publicName: 'Koffi Électricité Générale',
          bio:
              'Électricien depuis 8 ans à Abidjan. Installation, dépannage, '
              'mise aux normes.',
          experienceYears: 8,
        );

        expect(harness.lastCall.method, 'POST');
        expect(harness.lastUrl, 'http://localhost:3000/api/v1/providers/me');
        expect(harness.lastBody['publicName'], 'Koffi Électricité Générale');
        expect(harness.lastBody['experienceYears'], 8);

        expect(profile.id, 'e7a41f9c-2b6d-4c83-9f05-8a1b2c3d4e5f');
        expect(
          profile.validationStatus,
          ProviderValidationStatus.profileIncomplete,
        );
        expect(profile.checklist.profile, isTrue);
        expect(profile.checklist.services, isFalse);
        expect(profile.canSubmit, isFalse);
        expect(profile.requiredDocumentTypes, <String>['id_card']);
      },
    );

    test(
      '201 sans présentation — la case `profile` reste FAUSSE (4.1)',
      () async {
        final ApiHarness harness = harnessFor('createdWithoutBio');

        final ProviderProfile profile = await repositoryOn(
          harness,
        ).createProfile(publicName: 'Koffi Électricité Générale');

        expect(
          harness.lastBody.containsKey('bio'),
          isFalse,
          reason: 'une présentation absente ne part pas en chaîne vide',
        );
        expect(profile.checklist.profile, isFalse);
      },
    );

    test(
      '409 — TRAITÉ COMME UN SUCCÈS : GET puis aperçu, aucune erreur (4.3)',
      () async {
        // Premier appel : POST → 409. Second : GET → aperçu.
        final ApiHarness harness = ApiHarness((RequestOptions options, int _) {
          if (options.method == 'POST') {
            return fixture('provider/self', 'alreadyExists');
          }
          return fixture('provider/self', 'overviewIncomplete');
        });

        final ProviderProfile profile = await repositoryOn(
          harness,
        ).createProfile(publicName: 'Koffi Électricité Générale');

        expect(harness.callCount, 2);
        expect(harness.lastCall.method, 'GET');
        expect(profile.id, 'e7a41f9c-2b6d-4c83-9f05-8a1b2c3d4e5f');
        expect(profile.checklist.zones, isTrue);
      },
    );

    test('400 — la validation désigne le champ', () async {
      await expectLater(
        repositoryOn(harnessFor('validation')).createProfile(publicName: 'K'),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.isUserFixable,
                'corrigeable',
                isTrue,
              )
              .having(
                (ApiException e) => e.messageForField('publicName'),
                'champ publicName',
                'Le nom public doit contenir au moins 2 caractères',
              ),
        ),
      );
    });
  });

  group('Opération 66 — GET /providers/me', () {
    test(
      'l’aperçu porte checklist, canSubmit et types de justificatifs',
      () async {
        final ProviderProfile profile = await repositoryOn(
          harnessFor('overviewComplete'),
        ).overview();

        expect(profile.checklist.isComplete, isTrue);
        expect(profile.canSubmit, isTrue);
        expect(profile.resubmissionBlocked, isFalse);
      },
    );

    test(
      'capture réelle du compte approuvé : canSubmit FAUX malgré le statut',
      () async {
        final ProviderProfile profile = await repositoryOn(
          harnessFor('overviewApproved'),
        ).overview();

        expect(profile.validationStatus, ProviderValidationStatus.approved);
        expect(
          profile.canSubmit,
          isFalse,
          reason:
              'rien à re-soumettre : le bouton se pilote sur canSubmit, '
              'jamais sur la checklist ni sur le statut',
        );
        expect(
          profile.checklist.documents,
          isFalse,
          reason:
              'la capture réelle prouve qu’approbation et checklist '
              'complète sont deux choses distinctes',
        );
        expect(profile.score, 4.5);
        expect(profile.reviewsCount, 12);
      },
    );

    test('changes_requested : le motif est là, en tête des écrans', () async {
      final ProviderProfile profile = await repositoryOn(
        harnessFor('overviewChangesRequestedDocument'),
      ).overview();

      expect(
        profile.validationStatus,
        ProviderValidationStatus.changesRequested,
      );
      expect(
        profile.rejectionReason,
        'Votre pièce d\'identité est illisible : redéposez une photo nette '
        'du recto.',
      );
      expect(profile.canSubmit, isFalse);
    });

    test(
      'rejeté avec re-soumission bloquée : le bouton disparaît pour de bon',
      () async {
        final ProviderProfile profile = await repositoryOn(
          harnessFor('overviewRejectedBlocked'),
        ).overview();

        expect(profile.validationStatus, ProviderValidationStatus.rejected);
        expect(profile.resubmissionBlocked, isTrue);
        expect(profile.canSubmit, isFalse);
      },
    );

    test(
      '403 — pas de profil : le prédicat renvoie vers la création',
      () async {
        await expectLater(
          repositoryOn(harnessFor('noProfile')).overview(),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.hasNoProviderProfile,
              'hasNoProviderProfile',
              isTrue,
            ),
          ),
        );
      },
    );
  });

  group('Opération 67 — PATCH /providers/me et verrou de vérification', () {
    test(
      '400 — identité verrouillée en pending_review, message tel quel (4.8)',
      () async {
        await expectLater(
          repositoryOn(
            harnessFor('lockedInReview'),
          ).updateProfile(publicName: 'Nouveau nom'),
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
                  'Votre dossier est en cours de vérification : il n\'est plus '
                      'modifiable',
                ),
          ),
        );
      },
    );

    test('availabilityStatus SEUL traverse le verrou', () async {
      final ApiHarness harness = harnessFor('availabilityPatched');

      final ProviderProfile profile = await repositoryOn(
        harness,
      ).setAvailability(AvailabilityStatus.busy);

      expect(harness.lastCall.method, 'PATCH');
      expect(
        harness.lastBody,
        <String, Object?>{'availabilityStatus': 'busy'},
        reason:
            'le moindre champ d’identité dans ce corps déclencherait le '
            'verrou : availabilityStatus part strictement seul',
      );
      expect(profile.availabilityStatus, AvailabilityStatus.busy);
      expect(profile.validationStatus, ProviderValidationStatus.pendingReview);
    });

    test('la mise à jour ordinaire rend l’aperçu à jour', () async {
      final ApiHarness harness = harnessFor('patched');

      final ProviderProfile profile = await repositoryOn(harness).updateProfile(
        publicName: 'Koffi Électricité & Domotique',
        bio:
            'Électricien depuis 8 ans à Abidjan. Installation, dépannage, '
            'mise aux normes, domotique.',
      );

      expect(profile.publicName, 'Koffi Électricité & Domotique');
      expect(
        harness.lastBody.containsKey('experienceYears'),
        isFalse,
        reason: 'un champ non modifié ne part pas — PATCH partiel',
      );
    });
  });
}
