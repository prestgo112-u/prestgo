// T088 — Contrat de `POST /missions` (opération 31).
//
// C'est le test le plus important de la phase. Il vérifie la séquence exacte du §3 de
// contracts/retry-and-idempotency.md, et surtout ce qu'elle **interdit** :
//
//   • ne jamais présenter un 409 comme une erreur ;
//   • ne jamais réessayer un 400 métier avec la même clé ;
//   • ne jamais réessayer un 429 ;
//   • ne jamais changer de clé entre deux tentatives sur le même contenu — c'est
//     exactement ce qui créerait la seconde réservation que la clé sert à éviter.

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/idempotency.dart';
import 'package:prestgo_mobile/features/booking/data/booking_repository.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const String key = 'e6f6a1c2-3b4d-4e5f-8a90-1b2c3d4e5f60';

const JsonMap body = <String, Object?>{
  'providerId': 'p-4c8e1a05-7b3d-4f62-9e08-1a5c7d9e0b3f',
  'packId': 'pack-71111111-1111-4111-8111-111111111111',
  'scheduledAt': '2026-08-03T09:00:00.000Z',
  'addressId': 'addr-b1111111-1111-4111-8111-111111111111',
};

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> caseBody) = fixture(
    'booking/booking',
    caseName,
  );
  return ApiHarness.always(status, caseBody);
}

/// Dépôt d'essai : n'attend jamais réellement entre deux tentatives.
BookingRepository repositoryOn(ApiHarness harness, {List<Duration>? pauses}) =>
    BookingRepository(
      harness.client,
      pause: (Duration delay) async => pauses?.add(delay),
    );

void main() {
  group('Succès', () {
    test(
      '201 — la mission est créée, le montant est figé par le service',
      () async {
        final ApiHarness harness = harnessFor('created');

        final BookingConfirmation result = await repositoryOn(
          harness,
        ).confirm(body: body, idempotencyKey: key);

        expect(result.outcome, BookingOutcome.created);
        expect(result.wasAlreadyRecorded, isFalse);
        expect(result.mission.quotedAmount, 6500);
        expect(result.mission.isPendingProvider, isTrue);
        expect(
          result.mission.threadId,
          isNotNull,
          reason:
              'le fil existe dès la demande : le prestataire peut poser une '
              'question avant d’accepter',
        );
      },
    );

    test('la clé part dans l’en-tête, à chaque appel', () async {
      final ApiHarness harness = harnessFor('created');

      await repositoryOn(harness).confirm(body: body, idempotencyKey: key);

      expect(harness.lastCall.headers[kIdempotencyKeyHeader], key);
      expect(harness.lastUrl, '$kTestBaseUrl/missions');
    });

    test('200 « déjà enregistrée » est un SUCCÈS, pas une erreur', () async {
      final BookingConfirmation result = await repositoryOn(
        harnessFor('alreadyRecorded'),
      ).confirm(body: body, idempotencyKey: key);

      expect(
        result.outcome,
        BookingOutcome.alreadyRecorded,
        reason:
            'le premier appel était passé : la coupure réseau n’a fait perdre '
            'que la réponse (FR-034)',
      );
      expect(result.mission.id, 'm-c1111111-1111-4111-8111-111111111111');
    });

    test('les deux succès rendent la MÊME mission', () async {
      final BookingConfirmation created = await repositoryOn(
        harnessFor('created'),
      ).confirm(body: body, idempotencyKey: key);
      final BookingConfirmation replayed = await repositoryOn(
        harnessFor('alreadyRecorded'),
      ).confirm(body: body, idempotencyKey: key);

      expect(
        replayed.mission.id,
        created.mission.id,
        reason: 'rien n’a été recréé — c’est tout l’intérêt de la clé',
      );
      expect(replayed.mission.quotedAmount, created.mission.quotedAmount);
    });
  });

  group('409 « déjà en cours de traitement » — ni succès ni erreur', () {
    test('la boucle patiente 2 s puis réessaie, avec la MÊME clé', () async {
      int calls = 0;
      final ApiHarness harness = ApiHarness((
        RequestOptions options,
        int index,
      ) {
        calls++;
        // Les deux premiers appels trouvent la requête d'origine encore en vol.
        return calls <= 2
            ? fixture('booking/booking', 'inFlight')
            : fixture('booking/booking', 'alreadyRecorded');
      });
      final List<Duration> pauses = <Duration>[];

      final BookingConfirmation result = await repositoryOn(
        harness,
        pauses: pauses,
      ).confirm(body: body, idempotencyKey: key);

      expect(result.wasAlreadyRecorded, isTrue);
      expect(harness.callCount, 3);
      expect(pauses, <Duration>[
        BookingRepository.inFlightDelay,
        BookingRepository.inFlightDelay,
      ]);
      for (final RequestOptions call in harness.adapter.calls) {
        expect(
          call.headers[kIdempotencyKeyHeader],
          key,
          reason:
              'changer de clé entre deux tentatives créerait la seconde '
              'réservation que la clé sert précisément à éviter',
        );
      }
    });

    test(
      'un 409 persistant ne remonte pas comme une erreur d’affichage',
      () async {
        final ApiHarness harness = harnessFor('inFlight');

        await expectLater(
          repositoryOn(harness).confirm(body: body, idempotencyKey: key),
          throwsA(
            isA<BookingStillProcessing>().having(
              (BookingStillProcessing e) => e.lastFailure.isConflict,
              'conflit',
              isTrue,
            ),
          ),
        );
        expect(
          harness.callCount,
          BookingRepository.inFlightAttempts + 1,
          reason: 'deux reprises au plus, puis on recharge les missions',
        );
      },
    );

    test(
      '`create` seul ne boucle pas — la boucle est dans `confirm`',
      () async {
        final ApiHarness harness = harnessFor('inFlight');

        await expectLater(
          repositoryOn(harness).create(body: body, idempotencyKey: key),
          throwsA(isA<ApiException>()),
        );
        expect(harness.callCount, 1);
      },
    );
  });

  group('Ce qui n’est JAMAIS réessayé', () {
    Future<void> expectSingleCall(
      String caseName,
      String expectedMessage,
    ) async {
      final ApiHarness harness = harnessFor(caseName);

      await expectLater(
        repositoryOn(harness).confirm(body: body, idempotencyKey: key),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            expectedMessage,
          ),
        ),
      );
      expect(
        harness.callCount,
        1,
        reason: '$caseName ne doit provoquer aucune reprise',
      );
    }

    test('délai minimum non respecté', () async {
      // Le nombre vient du réglage lu au démarrage : l'application ne saurait pas
      // reconstruire ce message, elle l'affiche tel quel (FR-088).
      await expectSingleCall(
        'leadTimeTooShort',
        "Une réservation doit être posée au moins 60 minutes à l'avance",
      );
    });

    test('adresse hors zone', () async {
      await expectSingleCall(
        'addressOutOfZone',
        "Cette adresse n'est pas dans la zone d'intervention du prestataire",
      );
    });

    test('créneau indisponible', () async {
      await expectSingleCall(
        'slotNotAvailable',
        "Le prestataire n'est pas disponible sur ce créneau",
      );
    });

    test('créneau déjà pris', () async {
      await expectSingleCall(
        'slotTaken',
        'Ce créneau est déjà réservé chez ce prestataire',
      );
    });

    test('prestataire absent', () async {
      await expectSingleCall(
        'providerAbsent',
        'Le prestataire est absent à cette date',
      );
    });

    test('option inconnue pour la formule', () async {
      final ApiHarness harness = harnessFor('unknownOption');

      await expectLater(
        repositoryOn(harness).confirm(body: body, idempotencyKey: key),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            startsWith('Option inconnue pour cette formule'),
          ),
        ),
      );
      expect(harness.callCount, 1);
    });

    test('doublon métier — distinct de la protection par clé', () async {
      await expectSingleCall(
        'duplicateBooking',
        'Vous avez déjà une réservation en cours avec ce prestataire sur ce '
            'créneau',
      );
    });

    test('429 — un rejeu ne ferait qu’aggraver le débit', () async {
      final ApiHarness harness = harnessFor('rateLimited');

      await expectLater(
        repositoryOn(harness).confirm(body: body, idempotencyKey: key),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.isRateLimited,
            'isRateLimited',
            isTrue,
          ),
        ),
      );
      expect(harness.callCount, 1);
    });

    test('404 — formule introuvable', () async {
      await expectSingleCall(
        'packNotFound',
        'Formule introuvable, inactive, ou ne correspondant pas à ce prestataire',
      );
    });
  });

  group('Cycle de vie de la clé', () {
    test('même contenu, même clé — y compris après un échec réseau', () {
      final IdempotencyKeyHolder holder = IdempotencyKeyHolder();
      final String fingerprint = bookingFingerprint(
        providerId: 'p-1',
        packId: 'pack-1',
        optionIds: const <String>['opt-2', 'opt-1'],
        scheduledAt: DateTime.utc(2026, 8, 3, 9),
        addressId: 'addr-1',
      );

      final IdempotencyKey first = holder.keyFor(fingerprint);
      final IdempotencyKey second = holder.keyFor(fingerprint);

      expect(second.value, first.value);
    });

    test('l’ordre de cochage des options ne change rien', () {
      final String a = bookingFingerprint(
        providerId: 'p-1',
        packId: 'pack-1',
        optionIds: const <String>['opt-1', 'opt-2'],
        scheduledAt: DateTime.utc(2026, 8, 3, 9),
        addressId: 'addr-1',
      );
      final String b = bookingFingerprint(
        providerId: 'p-1',
        packId: 'pack-1',
        optionIds: const <String>['opt-2', 'opt-1'],
        scheduledAt: DateTime.utc(2026, 8, 3, 9),
        addressId: 'addr-1',
      );

      expect(a, b);
    });

    test('une option ajoutée émet une clé NEUVE (scénario 2.10)', () {
      final IdempotencyKeyHolder holder = IdempotencyKeyHolder();
      final IdempotencyKey before = holder.keyFor(
        bookingFingerprint(
          providerId: 'p-1',
          packId: 'pack-1',
          optionIds: const <String>[],
          scheduledAt: DateTime.utc(2026, 8, 3, 9),
          addressId: 'addr-1',
        ),
      );
      final IdempotencyKey after = holder.keyFor(
        bookingFingerprint(
          providerId: 'p-1',
          packId: 'pack-1',
          optionIds: const <String>['opt-1'],
          scheduledAt: DateTime.utc(2026, 8, 3, 9),
          addressId: 'addr-1',
        ),
      );

      expect(after.value, isNot(before.value));
    });
  });
}
