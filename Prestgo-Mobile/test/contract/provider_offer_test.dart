// T140 — Contrat de l'offre : services, formules, options (opérations 69 à 76).
//
// Les pièges de ces routes :
//   • la création répond la forme **brute** (sans packs) : `data.id` est le
//     `providerServiceId` exigé par la formule — le perdre casse P4 ;
//   • 404 « type inactif » = catalogue changé entre l'affichage et l'envoi ;
//   • 409 « doublon » = rediriger vers le service existant, pas d'erreur brute ;
//   • créer une option passe par le chemin **imbriqué**, la modifier par le
//     chemin **à plat** — la seule paire asymétrique du contrat.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_offer.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const String kServiceId = '4698c3da-7697-41b5-8c6d-946fdcec95f0';
const String kPackId = '7f0b2a4c-9d1e-4f3a-8b5c-6d7e8f9a0b1c';
const String kOptionId = '2c3d4e5f-6a7b-4c8d-9e0f-1a2b3c4d5e6f';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'provider/services',
    caseName,
  );
  return ApiHarness.always(status, body);
}

ProviderSelfRepository repositoryOn(ApiHarness harness) =>
    ProviderSelfRepository(harness.client);

void main() {
  group('Opération 69 — GET /providers/me/services', () {
    test('non paginé, formules et options imbriquées', () async {
      final ApiHarness harness = harnessFor('list');

      final List<ProviderService> services = await repositoryOn(
        harness,
      ).services();

      expect(services, hasLength(1));
      final ProviderService service = services.single;
      expect(service.title, 'Dépannage plomberie à domicile');
      expect(service.serviceType?.label, 'Réparation de fuite — Plomberie');
      expect(service.packs, hasLength(1));
      expect(service.packs.single.options, hasLength(1));
      expect(service.hasActivePack, isTrue);
    });

    test(
      'un service sans formule active ne satisfait pas la checklist (4.2)',
      () async {
        final List<ProviderService> services = await repositoryOn(
          harnessFor('listServiceWithoutPack'),
        ).services();

        expect(services.single.packs, isEmpty);
        expect(services.single.hasActivePack, isFalse);
      },
    );
  });

  group('Opération 70 — POST /providers/me/services', () {
    test(
      '201 — forme brute sans packs, data.id = providerServiceId de P4',
      () async {
        final ApiHarness harness = harnessFor('serviceCreated');

        final ProviderService service = await repositoryOn(harness)
            .createService(
              serviceTypeId: 'c3fe35c0-9331-47d4-a809-bd63fe69a70f',
              title: 'Dépannage plomberie à domicile',
              description: 'Fuites, robinetterie, évacuation.',
            );

        expect(harness.lastCall.method, 'POST');
        expect(
          harness.lastBody['serviceTypeId'],
          'c3fe35c0-9331-47d4-a809-bd63fe69a70f',
        );
        expect(service.id, kServiceId);
        expect(service.packs, isEmpty);
        expect(service.serviceType, isNull);
      },
    );

    test('404 — type inactif : le catalogue a changé', () async {
      await expectLater(
        repositoryOn(
          harnessFor('typeInactive'),
        ).createService(serviceTypeId: 'type-disparu', title: 'Dépannage'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.isNotFound, 'isNotFound', isTrue)
              .having(
                (ApiException e) => e.message,
                'message',
                'Type de service introuvable ou inactif',
              ),
        ),
      );
    });

    test('409 — doublon de type : rediriger vers l’existant', () async {
      await expectLater(
        repositoryOn(harnessFor('duplicateType')).createService(
          serviceTypeId: 'c3fe35c0-9331-47d4-a809-bd63fe69a70f',
          title: 'Dépannage bis',
        ),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.isConflict, 'isConflict', isTrue)
              .having(
                (ApiException e) => e.message,
                'message',
                'Vous proposez déjà un service actif de ce type',
              ),
        ),
      );
    });
  });

  group('Opérations 72 et 73 — formules', () {
    test('la création exige providerServiceId dans le corps', () async {
      final ApiHarness harness = harnessFor('packCreated');

      final ServicePack pack = await repositoryOn(harness).createPack(
        providerServiceId: kServiceId,
        title: 'Intervention express',
        description: 'Petite réparation, sur place en moins d\'une heure.',
        price: 5000,
        durationMinutes: 45,
      );

      expect(harness.lastUrl, endsWith('/providers/me/service-packs'));
      expect(harness.lastBody['providerServiceId'], kServiceId);
      expect(harness.lastBody['price'], 5000);
      expect(harness.lastBody['durationMinutes'], 45);
      expect(pack.id, kPackId);
      expect(pack.active, isTrue);
    });

    test(
      '404 — providerServiceId inconnu : recharger la liste des services',
      () async {
        await expectLater(
          repositoryOn(harnessFor('packServiceNotFound')).createPack(
            providerServiceId: 'service-fantome',
            title: 'Formule',
            price: 1000,
            durationMinutes: 30,
          ),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.isNotFound, 'isNotFound', isTrue)
                .having(
                  (ApiException e) => e.message,
                  'message',
                  'Service introuvable pour ce prestataire',
                ),
          ),
        );
      },
    );

    test('400 — la validation de durée désigne le champ', () async {
      await expectLater(
        repositoryOn(harnessFor('packValidation')).createPack(
          providerServiceId: kServiceId,
          title: 'Formule',
          price: 1000,
          durationMinutes: 2,
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.messageForField('durationMinutes'),
            'champ durationMinutes',
            'La durée minimale est de 5 minutes',
          ),
        ),
      );
    });

    test(
      'la modification passe par PATCH /providers/me/service-packs/{id}',
      () async {
        final ApiHarness harness = harnessFor('packUpdated');

        final ServicePack pack = await repositoryOn(
          harness,
        ).updatePack(kPackId, price: 6000);

        expect(harness.lastCall.method, 'PATCH');
        expect(
          harness.lastUrl,
          endsWith('/providers/me/service-packs/$kPackId'),
        );
        expect(harness.lastBody, <String, Object?>{'price': 6000});
        expect(pack.price, 6000);
      },
    );
  });

  group('Opérations 74 à 76 — options : imbriqué à la création, À PLAT à la '
      'modification', () {
    test('la lecture et la création passent par le pack porteur', () async {
      final ApiHarness listHarness = harnessFor('optionsList');
      final List<PackOption> options = await repositoryOn(
        listHarness,
      ).packOptions(kPackId);

      expect(
        listHarness.lastUrl,
        endsWith('/providers/me/service-packs/$kPackId/options'),
      );
      expect(options, hasLength(2));

      final ApiHarness createHarness = harnessFor('optionCreated');
      final PackOption option = await repositoryOn(
        createHarness,
      ).createOption(kPackId, title: 'Fourniture du joint', price: 1500);

      expect(
        createHarness.lastUrl,
        endsWith('/providers/me/service-packs/$kPackId/options'),
      );
      expect(option.id, kOptionId);
      expect(
        createHarness.lastBody.containsKey('durationMinutes'),
        isFalse,
        reason: 'la durée par défaut (0) appartient au service',
      );
    });

    test('⚠️ la modification passe par le chemin À PLAT', () async {
      final ApiHarness harness = harnessFor('optionUpdated');

      final PackOption option = await repositoryOn(
        harness,
      ).updateOption(kOptionId, price: 2000);

      expect(harness.lastCall.method, 'PATCH');
      expect(
        harness.lastUrl,
        endsWith('/providers/me/service-pack-options/$kOptionId'),
        reason:
            'PAS /service-packs/{packId}/options/{id} — la seule route '
            'd’option non imbriquée du contrat',
      );
      expect(option.price, 2000);
    });
  });
}
