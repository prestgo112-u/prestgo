// T144 — Contrat de la soumission (opération 68).
//
// Les pièges de cette route :
//   • le 400 « dossier incomplet » porte `errors[].field` = des clés de
//     checklist : l'écran passe en rouge EXACTEMENT ces lignes-là
//     (`ChecklistStep.fromSubmitError`, scénario 4.7) ;
//   • le 400 « rien à soumettre » signifie que le statut a changé entre
//     l'affichage et le clic — rafraîchir l'aperçu ;
//   • le 403 correspond à `resubmissionBlocked` : bouton retiré POUR DE BON,
//     contact support seul.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'provider/submit',
    caseName,
  );
  return ApiHarness.always(status, body);
}

ProviderSelfRepository repositoryOn(ApiHarness harness) =>
    ProviderSelfRepository(harness.client);

void main() {
  group('Opération 68 — POST /providers/me/submit', () {
    test(
      '200 — l’aperçu revient en pending_review, soumission datée',
      () async {
        final ApiHarness harness = harnessFor('submitted');

        final ProviderProfile profile = await repositoryOn(harness).submit();

        expect(harness.lastCall.method, 'POST');
        expect(harness.lastUrl, endsWith('/providers/me/submit'));
        expect(
          profile.validationStatus,
          ProviderValidationStatus.pendingReview,
        );
        expect(profile.submittedAt, isNotNull);
        expect(profile.rejectionReason, isNull);
        expect(profile.canSubmit, isFalse);
      },
    );

    test('400 incomplet — errors[].field désigne les lignes rouges, et '
        'SEULEMENT elles (4.7)', () async {
      late ApiException failure;
      try {
        await repositoryOn(harnessFor('incomplete')).submit();
        fail('un 400 devait être levé');
      } on ApiException catch (error) {
        failure = error;
      }

      expect(failure.message, 'Votre dossier n\'est pas complet');
      expect(ChecklistStep.fromSubmitError(failure), <ChecklistStep>{
        ChecklistStep.documents,
      });
      expect(
        failure.messageForField('documents'),
        'Fournissez tous les justificatifs obligatoires',
        reason: 'le libellé officiel de la case, affiché sous la ligne',
      );
    });

    test('400 incomplet, deux lignes — les deux passent en rouge, pas une de '
        'plus', () async {
      late ApiException failure;
      try {
        await repositoryOn(harnessFor('incompleteTwoLines')).submit();
        fail('un 400 devait être levé');
      } on ApiException catch (error) {
        failure = error;
      }

      expect(ChecklistStep.fromSubmitError(failure), <ChecklistStep>{
        ChecklistStep.profile,
        ChecklistStep.documents,
      });
      expect(
        failure.messageForField('profile'),
        'Complétez votre nom public et votre présentation',
      );
    });

    test('400 « rien à soumettre » — le statut a changé : message tel quel, '
        'aucune ligne désignée', () async {
      late ApiException failure;
      try {
        await repositoryOn(harnessFor('nothingToSubmit')).submit();
        fail('un 400 devait être levé');
      } on ApiException catch (error) {
        failure = error;
      }

      expect(
        failure.message,
        'Votre dossier est au statut « approved » : il n\'y a rien à '
        'soumettre.',
      );
      expect(ChecklistStep.fromSubmitError(failure), isEmpty);
    });

    test('403 — re-soumission bloquée : masquer le bouton, contacter le '
        'support', () async {
      await expectLater(
        repositoryOn(harnessFor('resubmissionBlocked')).submit(),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.isForbidden, 'isForbidden', isTrue)
              .having(
                (ApiException e) => e.message,
                'message',
                'La re-soumission de votre dossier a été bloquée. Contactez '
                    'le support.',
              ),
        ),
      );
    });
  });
}
