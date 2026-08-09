// T087 — Contrat du carnet d'adresses (opérations 13 à 17).
//
// Deux pièges de cette famille de routes, tous deux vérifiés ici :
//   • `POST .../default` renvoie **la liste**, pas l'adresse modifiée ;
//   • `DELETE` a **deux formes de succès** — retrait réel, ou archivage quand
//     l'adresse documente une mission passée. Traiter la seconde comme un échec
//     ferait croire à une suppression ratée alors qu'elle a fait ce qu'il fallait.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/profile/data/address_repository.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

late LocalDatabase database;
late CacheDao cache;

const AddressDraft draft = AddressDraft(
  label: 'Chez ma mère',
  city: 'Abidjan',
  commune: 'Yopougon',
  latitude: 5.34,
  longitude: -4.07,
);

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'booking/addresses',
    caseName,
  );
  return ApiHarness.always(status, body);
}

AddressRepository repositoryOn(ApiHarness harness) =>
    AddressRepository(harness.client, cache);

void main() {
  setUp(() {
    database = LocalDatabase.memory();
    cache = CacheDao(database);
  });

  tearDown(() => database.close());

  group('Opération 13 — GET /me/addresses', () {
    test(
      'l’adresse par défaut est en tête, comme le service la trie',
      () async {
        final ApiHarness harness = harnessFor('list');

        final List<Address> addresses = await repositoryOn(harness).list();

        expect(addresses, hasLength(2));
        expect(addresses.first.isDefault, isTrue);
        expect(addresses.first.label, 'Domicile');
        expect(harness.lastUrl, '$kTestBaseUrl/me/addresses');
      },
    );

    test('la ligne affichable compose commune, ville et détails', () async {
      final List<Address> addresses = await repositoryOn(
        harnessFor('list'),
      ).list();

      expect(addresses.first.locality, 'Cocody, Abidjan');
      expect(
        addresses.first.fullLine,
        'Rue des Jardins, villa 12 — Cocody, Abidjan',
      );
      expect(addresses.last.fullLine, 'Plateau, Abidjan');
    });

    test(
      'le carnet est mis en cache pour l’étape « lieu d’intervention »',
      () async {
        final AddressRepository repository = repositoryOn(harnessFor('list'));

        expect(await repository.cached(), isNull);
        await repository.list();
        final List<Address>? cached = await repository.cached();

        expect(cached, hasLength(2));
        expect(
          cached!.first.isDefault,
          isTrue,
          reason: 'l’ordre du service est conservé jusque dans le cache',
        );
      },
    );

    test('un carnet vide est un succès', () async {
      expect(await repositoryOn(harnessFor('empty')).list(), isEmpty);
    });
  });

  group('Opération 14 — création', () {
    test('201 — la première adresse devient l’adresse par défaut', () async {
      final ApiHarness harness = harnessFor('created');

      final Address created = await repositoryOn(harness).create(draft);

      expect(created.isDefault, isTrue);
      expect(created.label, 'Chez ma mère');
      expect(harness.lastCall.method, 'POST');
    });

    test('les champs facultatifs absents ne sont pas envoyés', () async {
      final ApiHarness harness = harnessFor('created');

      await repositoryOn(harness).create(draft);

      final Map<String, Object?> body = harness.lastBody;
      expect(body['commune'], 'Yopougon');
      expect(body.containsKey('details'), isFalse);
      expect(
        body.containsKey('isDefault'),
        isFalse,
        reason:
            'ne pas le transmettre laisse le service appliquer sa règle : la '
            'première adresse devient celle par défaut',
      );
    });

    test('la position est toujours transmise', () async {
      final ApiHarness harness = harnessFor('created');

      await repositoryOn(harness).create(draft);

      expect(harness.lastBody['latitude'], 5.34);
      expect(harness.lastBody['longitude'], -4.07);
    });

    test('400 — le plafond de 10 est refusé avec son motif', () async {
      await expectLater(
        repositoryOn(harnessFor('capacityReached')).create(draft),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            'Vous ne pouvez pas enregistrer plus de 10 adresses',
          ),
        ),
      );
    });

    test('le plafond est connu localement, pour devancer ce refus', () {
      expect(ContentLimits.addressesPerAccount, 10);
      expect(AddressRepository.isAtCapacity(9), isFalse);
      expect(AddressRepository.isAtCapacity(10), isTrue);
    });

    test('400 — une adresse sans position est refusée', () async {
      await expectLater(
        repositoryOn(harnessFor('missingCoordinates')).create(draft),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.messageForField('latitude'),
            'champ latitude',
            'La latitude est obligatoire',
          ),
        ),
      );
    });
  });

  group('Opération 17 — définir par défaut', () {
    test('la réponse est la LISTE complète à jour, pas l’adresse', () async {
      final ApiHarness harness = harnessFor('defaultChanged');

      final List<Address> addresses = await repositoryOn(
        harness,
      ).setDefault('addr-b1111111-1111-4111-8111-222222222222');

      expect(addresses, hasLength(2));
      expect(addresses.first.label, 'Bureau');
      expect(addresses.first.isDefault, isTrue);
      expect(addresses.last.isDefault, isFalse);
      expect(harness.lastUrl, contains('/default'));
    });

    test('elle alimente le cache directement — aucun second appel', () async {
      final ApiHarness harness = harnessFor('defaultChanged');
      final AddressRepository repository = repositoryOn(harness);

      await repository.setDefault('addr-b1111111-1111-4111-8111-222222222222');

      expect(harness.callCount, 1);
      final List<Address>? cached = await repository.cached();
      expect(cached?.first.label, 'Bureau');
    });
  });

  group('Opération 16 — suppression, deux formes de succès', () {
    test('retrait réel', () async {
      final AddressRemoval result = await repositoryOn(
        harnessFor('removed'),
      ).remove('addr-b1111111-1111-4111-8111-222222222222');

      expect(result.removed, isTrue);
      expect(result.archived, isFalse);
      expect(result.message, 'Adresse supprimée.');
    });

    test('archivage — un succès aussi, avec un message différent', () async {
      final AddressRemoval result = await repositoryOn(
        harnessFor('archived'),
      ).remove('addr-b1111111-1111-4111-8111-111111111111');

      expect(result.removed, isFalse);
      expect(
        result.archived,
        isTrue,
        reason:
            'l’adresse documente une mission passée : la supprimer romprait '
            'l’historique',
      );
      expect(
        result.message,
        'Adresse conservée car utilisée par des missions passées',
      );
    });

    test('une adresse archivée est reconnaissable à son libellé', () {
      // Le service marque l'archivage en suffixant le libellé, faute de colonne
      // dédiée : ces adresses n'ont pas à réapparaître dans le carnet.
      final Address archived = Address(
        id: 'a-1',
        label: 'Domicile (archivée)',
        city: 'Abidjan',
        latitude: 5.35,
        longitude: -3.98,
        isDefault: false,
        createdAt: DateTime.utc(2026),
      );
      expect(archived.isArchived, isTrue);
      expect(
        Address.fromJson(
          fixtureData('booking/addresses', 'created'),
        ).isArchived,
        isFalse,
      );
    });

    test(
      '404 — révéler l’adresse d’un inconnu serait déjà une fuite',
      () async {
        await expectLater(
          repositoryOn(harnessFor('notFound')).remove('addr-inconnue'),
          throwsA(
            isA<ApiException>()
                .having((ApiException e) => e.isNotFound, 'isNotFound', isTrue)
                .having(
                  (ApiException e) => e.message,
                  'message',
                  'Adresse introuvable',
                ),
          ),
        );
      },
    );
  });
}
