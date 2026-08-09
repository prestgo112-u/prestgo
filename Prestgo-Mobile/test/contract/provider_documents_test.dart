// T143 — Contrat des justificatifs (opérations 83 et 84).
//
// Les pièges de cette paire :
//   • l'écran se construit depuis `requiredTypes` — rien n'est codé en dur ;
//   • `missingTypes` = types sans justificatif **exploitable** : un dépôt
//     `pending` suffit, un `rejected` remet le type en manquant ;
//   • un document `approved` ne se remplace pas (400) ;
//   • **effet de bord central** : un dépôt en `changes_requested` repasse le
//     dossier en `pending_review` tout seul — l'aperçu DOIT être relu après
//     chaque dépôt (scénario 4.9).

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_document.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const String kFileId = '2e3d4c5b-6a78-4899-8011-bbccddeeff00';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'provider/documents',
    caseName,
  );
  return ApiHarness.always(status, body);
}

ProviderSelfRepository repositoryOn(ApiHarness harness) =>
    ProviderSelfRepository(harness.client);

void main() {
  group('Opération 83 — GET /providers/me/documents', () {
    test('capture réelle : les quatre champs de la vue, aucun dépôt', () async {
      final ProviderDocumentsOverview overview = await repositoryOn(
        harnessFor('emptyRequired'),
      ).documents();

      expect(overview.requiredTypes, <String>['id_card']);
      expect(overview.missingTypes, <String>['id_card']);
      expect(overview.current, isEmpty);
      expect(overview.documents, isEmpty);
      expect(overview.isMissing('id_card'), isTrue);
    });

    test(
      'un dépôt `pending` est exploitable : le type ne manque plus',
      () async {
        final ProviderDocumentsOverview overview = await repositoryOn(
          harnessFor('withPending'),
        ).documents();

        expect(overview.missingTypes, isEmpty);
        final ProviderDocument? current = overview.currentFor('id_card');
        expect(current?.status, ProviderDocumentStatus.pending);
        expect(current?.version, 1);
        expect(current?.isLocked, isFalse);
      },
    );

    test('un refus remet le type en manquant, avec son motif — LA donnée de '
        'l’écran de correction', () async {
      final ProviderDocumentsOverview overview = await repositoryOn(
        harnessFor('withRejected'),
      ).documents();

      expect(overview.missingTypes, <String>['id_card']);
      expect(
        overview.currentFor('id_card')?.rejectionReason,
        'Document illisible : la photo est floue, reprenez le recto en pleine '
        'lumière.',
      );
    });

    test('l’historique garde toutes les versions ; `current` la dernière ; '
        'un `approved` est verrouillé', () async {
      final ProviderDocumentsOverview overview = await repositoryOn(
        harnessFor('withApprovedHistory'),
      ).documents();

      final ProviderDocument? current = overview.currentFor('id_card');
      expect(current?.version, 2);
      expect(current?.status, ProviderDocumentStatus.approved);
      expect(
        current?.isLocked,
        isTrue,
        reason: 'un document validé ne se redépose pas — action grisée',
      );

      final List<ProviderDocument> versions = overview.versionsFor('id_card');
      expect(versions, hasLength(2));
      expect(versions.first.version, 2);
      expect(versions.last.status, ProviderDocumentStatus.rejected);
      expect(overview.missingTypes, isEmpty);
    });
  });

  group('Opération 84 — POST /providers/me/documents', () {
    test('201 — {type, fileId} part, la nouvelle VERSION revient', () async {
      final ApiHarness harness = harnessFor('attached');

      final ProviderDocument document = await repositoryOn(
        harness,
      ).attachDocument(type: 'id_card', fileId: kFileId);

      expect(harness.lastCall.method, 'POST');
      expect(harness.lastUrl, endsWith('/providers/me/documents'));
      expect(harness.lastBody, <String, Object?>{
        'type': 'id_card',
        'fileId': kFileId,
      });
      expect(document.version, 2);
      expect(document.status, ProviderDocumentStatus.pending);
    });

    test('400 — un document validé ne se remplace pas', () async {
      await expectLater(
        repositoryOn(
          harnessFor('alreadyApproved'),
        ).attachDocument(type: 'id_card', fileId: kFileId),
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
                'Votre justificatif « id_card » est déjà validé',
              ),
        ),
      );
    });

    test(
      '404 — le fichier n’appartient pas au compte : refaire l’étape 1',
      () async {
        await expectLater(
          repositoryOn(
            harnessFor('fileNotFound'),
          ).attachDocument(type: 'id_card', fileId: 'fichier-d-un-autre'),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.isNotFound, 'isNotFound', isTrue)
                .having(
                  (ApiException e) => e.message,
                  'message',
                  'Fichier introuvable ou ne vous appartenant pas',
                ),
          ),
        );
      },
    );

    test('RETOUR AUTOMATIQUE en vérification : l’aperçu relu après le dépôt '
        'est déjà pending_review (4.9)', () async {
      // Le service simulé rejoue l'effet de bord : avant le dépôt, le dossier
      // est en changes_requested ; après, l'aperçu répond pending_review.
      bool deposited = false;
      final ApiHarness harness = ApiHarness((RequestOptions options, int _) {
        if (options.path == '/providers/me/documents' &&
            options.method == 'POST') {
          deposited = true;
          return fixture('provider/documents', 'attached');
        }
        if (options.path == '/providers/me') {
          return fixture(
            'provider/self',
            deposited
                ? 'overviewPendingReview'
                : 'overviewChangesRequestedDocument',
          );
        }
        return (404, <String, Object?>{'success': false});
      });
      final ProviderSelfRepository repository = repositoryOn(harness);

      final ProviderProfile before = await repository.overview();
      expect(
        before.validationStatus,
        ProviderValidationStatus.changesRequested,
      );

      await repository.attachDocument(type: 'id_card', fileId: kFileId);

      // C'est CETTE relecture que l'écran doit faire après chaque dépôt : le
      // statut a changé sans autre appel d'écriture, et `rejectionReason` a
      // disparu — ne jamais supposer qu'il est resté changes_requested.
      final ProviderProfile after = await repository.overview();
      expect(after.validationStatus, ProviderValidationStatus.pendingReview);
      expect(after.rejectionReason, isNull);
      expect(
        after.canSubmit,
        isFalse,
        reason: 'plus rien à re-soumettre : le bouton disparaît (4.9)',
      );
    });
  });
}
