// T141 — Contrat des zones d'intervention (opérations 77 et 78).
//
// Les pièges de cette paire :
//   • c'est un **PUT** : l'état complet remplace la liste — pas d'ajout unitaire ;
//   • le contrôle serveur est **atomique** : une seule zone inconnue et RIEN
//     n'est écrit, le 400 liste les fautives ;
//   • la liste **vide est acceptée** (« je ne couvre plus aucune zone ») — c'est
//     l'écran qui exige une confirmation, pas le service (scénario 4.4).

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/shared/catalog/catalog.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const String kCocodyId = 'fddb1349-5f23-4307-9560-710c6220c049';
const String kMarcoryId = 'b4d92c63-8fa5-4e27-9c31-475a6b8d9f21';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'provider/zones',
    caseName,
  );
  return ApiHarness.always(status, body);
}

ProviderSelfRepository repositoryOn(ApiHarness harness) =>
    ProviderSelfRepository(harness.client);

void main() {
  group('Opération 77 — GET /providers/me/zones', () {
    test('non paginé — alimente le pré-cochage de l’écran', () async {
      final ApiHarness harness = harnessFor('mine');

      final List<Zone> zones = await repositoryOn(harness).myZones();

      expect(harness.lastUrl, endsWith('/providers/me/zones'));
      expect(zones, hasLength(2));
      expect(zones.first.label, 'Cocody, Abidjan');
    });

    test(
      'le catalogue public GET /zones se lit depuis la même surface',
      () async {
        final ApiHarness harness = harnessFor('catalog');

        final List<Zone> zones = await repositoryOn(harness).availableZones();

        expect(harness.lastUrl, endsWith('/api/v1/zones'));
        expect(zones, hasLength(3));
      },
    );
  });

  group('Opération 78 — PUT /providers/me/zones', () {
    test('remplacement intégral : l’état complet part dans zoneIds', () async {
      final ApiHarness harness = harnessFor('replaced');

      final ZonesUpdate update = await repositoryOn(
        harness,
      ).replaceZones(<String>[kCocodyId]);

      expect(harness.lastCall.method, 'PUT');
      expect(harness.lastBody, <String, Object?>{
        'zoneIds': <Object?>[kCocodyId],
      });
      expect(update.zones.single.id, kCocodyId);
      expect(update.message, 'Zones d\'intervention mises à jour');
    });

    test('la liste vide est ACCEPTÉE — la confirmation est l’affaire de '
        'l’écran (4.4)', () async {
      final ApiHarness harness = harnessFor('replacedEmpty');

      final ZonesUpdate update = await repositoryOn(
        harness,
      ).replaceZones(const <String>[]);

      expect(harness.lastBody, <String, Object?>{'zoneIds': <Object?>[]});
      expect(update.zones, isEmpty);
    });

    test('400 ATOMIQUE — le message liste les zones invalides, rien n’est '
        'écrit', () async {
      await expectLater(
        repositoryOn(harnessFor('unknownZone')).replaceZones(<String>[
          kCocodyId,
          '9f8e7d6c-5b4a-4392-8170-6f5e4d3c2b1a',
          '8e7d6c5b-4a39-4281-8069-5e4d3c2b1a09',
        ]),
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
                'Zone inconnue ou inactive : '
                    '9f8e7d6c-5b4a-4392-8170-6f5e4d3c2b1a, '
                    '8e7d6c5b-4a39-4281-8069-5e4d3c2b1a09',
              ),
        ),
      );
    });

    test('400 — plafond de 15 zones, l’erreur désigne le champ', () async {
      await expectLater(
        repositoryOn(
          harnessFor('tooMany'),
        ).replaceZones(List<String>.generate(16, (int i) => 'zone-$i')),
        throwsA(
          isA<ApiException>()
              .having(
                (ApiException e) => e.message,
                'message',
                'Vous ne pouvez pas couvrir plus de 15 zones',
              )
              .having(
                (ApiException e) => e.messageForField('zoneIds'),
                'champ zoneIds',
                'Pas plus de 15 zones',
              ),
        ),
      );
    });

    test('400 — doublon dans la liste', () async {
      await expectLater(
        repositoryOn(
          harnessFor('duplicateZone'),
        ).replaceZones(<String>[kCocodyId, kCocodyId]),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            'La même zone est indiquée plusieurs fois',
          ),
        ),
      );
    });
  });
}
