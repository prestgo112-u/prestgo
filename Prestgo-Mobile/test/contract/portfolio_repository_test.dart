// T207 — Contrat du portfolio (opérations 85 à 88).
//
// Les pièges de ces routes :
//   • plafond de **20 réalisations** et **images uniquement** — deux 400
//     exploitables, mais l'écran désactive l'ajout à 20 avant l'appel (8.3) ;
//   • l'ajout passe le fichier en visibilité `public`, le retrait le ramène en
//     `restricted` — le cache d'image local doit alors être purgé ;
//   • le PATCH n'accepte **aucun changement d'image** : remplacer la photo,
//     c'est retirer puis rajouter ;
//   • le réordonnancement est élément par élément (`displayOrder` seul) — il
//     n'existe aucune route de lot.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_space/domain/portfolio_item.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const String kItemId = 'a1b2c3d4-e5f6-4a7b-8c9d-0e1f2a3b4c5d';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'provider_offer/portfolio',
    caseName,
  );
  return ApiHarness.always(status, body);
}

ProviderSelfRepository repositoryOn(ApiHarness harness) =>
    ProviderSelfRepository(harness.client);

void main() {
  group('Opération 85 — GET /providers/me/portfolio', () {
    test('non paginé, trié par ordre d’affichage, fichiers publics', () async {
      final ApiHarness harness = harnessFor('list');

      final List<PortfolioItem> items = await repositoryOn(harness).portfolio();

      expect(harness.lastCall.method, 'GET');
      expect(harness.lastCall.path, '/providers/me/portfolio');
      expect(items, hasLength(2));
      expect(items.first.displayOrder, 0);
      expect(items.last.displayOrder, 1);
      expect(items.first.title, 'Rénovation salle de bain');
      // Une réalisation affichée est un contenu public — donc cacheable.
      expect(items.first.file.visibility, FileVisibility.public);
      expect(items.first.file.visibility.isDiskCacheable, isTrue);
    });
  });

  group('Opération 86 — POST /providers/me/portfolio', () {
    test('201 — le fichier rattaché est passé en visibilité public', () async {
      final ApiHarness harness = harnessFor('created');

      final PortfolioItem item = await repositoryOn(harness).addPortfolioItem(
        fileId: 'b3c4d5e6-f7a8-4b9c-8d0e-2f3a4b5c6d7e',
        title: 'Débouchage cuisine',
      );

      expect(harness.lastCall.method, 'POST');
      expect(
        harness.lastBody['fileId'],
        'b3c4d5e6-f7a8-4b9c-8d0e-2f3a4b5c6d7e',
      );
      // Description vide : le champ ne part pas.
      expect(harness.lastBody.containsKey('description'), isFalse);
      expect(item.file.visibility, FileVisibility.public);
      expect(item.displayOrder, 2);
    });

    test('400 — 21e réalisation : le plafond est celui du service', () async {
      await expectLater(
        repositoryOn(harnessFor('capReached')).addPortfolioItem(fileId: 'f-x'),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.isUserFixable,
                'isUserFixable',
                isTrue,
              )
              .having(
                (ApiException e) => e.message,
                'message',
                'Le portfolio est limité à 20 réalisations',
              ),
        ),
      );
    });

    test('400 — images uniquement', () async {
      await expectLater(
        repositoryOn(harnessFor('notImage')).addPortfolioItem(fileId: 'f-pdf'),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            'Seules les images sont acceptées dans le portfolio',
          ),
        ),
      );
    });
  });

  group('Opération 87 — PATCH /providers/me/portfolio/{id}', () {
    test('modification du titre — jamais de fileId dans le corps', () async {
      final ApiHarness harness = harnessFor('updated');

      final PortfolioItem item = await repositoryOn(harness)
          .updatePortfolioItem(
            kItemId,
            title: 'Rénovation complète de salle de bain',
          );

      expect(harness.lastCall.method, 'PATCH');
      expect(harness.lastCall.path, '/providers/me/portfolio/$kItemId');
      // Pas de changement d'image : la route ne connaît pas `fileId`.
      expect(harness.lastBody.containsKey('fileId'), isFalse);
      expect(item.title, 'Rénovation complète de salle de bain');
    });

    test('réordonnancement élément par élément : displayOrder seul', () async {
      final ApiHarness harness = harnessFor('reordered');

      final PortfolioItem item = await repositoryOn(harness)
          .updatePortfolioItem(
            'b2c3d4e5-f6a7-4b8c-9d0e-1f2a3b4c5d6e',
            displayOrder: 0,
          );

      expect(harness.lastBody, <String, Object?>{'displayOrder': 0});
      expect(item.displayOrder, 0);
    });
  });

  group('Opération 88 — DELETE /providers/me/portfolio/{id}', () {
    test(
      'le fichier est ramené en restricted — cache d’image à purger',
      () async {
        final ApiHarness harness = harnessFor('deleted');

        final PortfolioRemoval removal = await repositoryOn(
          harness,
        ).removePortfolioItem(kItemId);

        expect(harness.lastCall.method, 'DELETE');
        expect(harness.lastCall.path, '/providers/me/portfolio/$kItemId');
        expect(removal.removed, isTrue);
        expect(removal.file?.visibility, FileVisibility.restricted);
        expect(removal.file?.visibility.isDiskCacheable, isFalse);
      },
    );

    test('404 — la réalisation d’un autre prestataire est introuvable, '
        'jamais interdite', () async {
      await expectLater(
        repositoryOn(harnessFor('notFound')).removePortfolioItem('item-autre'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.isNotFound, 'isNotFound', isTrue)
              .having(
                (ApiException e) => e.message,
                'message',
                'Réalisation introuvable',
              ),
        ),
      );
    });
  });
}
