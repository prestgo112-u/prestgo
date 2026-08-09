// T089 — Calculs de réservation (FR-029 à FR-032).
//
// Ces règles ont une raison d'être précise : ne proposer à l'écran que des créneaux
// que le service acceptera. Chacune reproduit une vérification de
// `mission-booking.service.ts`, et le test la confronte aux mêmes bornes.
//
// ⚠️ Le référentiel de l'agenda est **UTC** : le service dérive jour et heure des
// composantes UTC de l'instant réservé. Les instants construits ici le sont donc avec
// `DateTime.utc`, exactement comme le fait `BookingRules.instantFor`.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_draft.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_rules.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';

import '../support/fixtures.dart';

ProviderPublicProfile profileFrom(String caseName) =>
    ProviderPublicProfile.fromJson(
      fixtureData('booking/provider_public', caseName),
    );

final Address address = Address.fromJson(
  fixtureData('booking/addresses', 'created'),
);

void main() {
  late ProviderPublicProfile provider;
  late ServicePack diagnostic;
  late PackOption joint;
  late PackOption horsHoraires;

  setUp(() {
    provider = profileFrom('complete');
    diagnostic = provider.packs.first;
    joint = diagnostic.options.first;
    horsHoraires = diagnostic.options.last;
  });

  group('Prix et durée totaux (FR-030)', () {
    test('sans option, la formule seule fait foi', () {
      expect(
        BookingRules.totalPrice(
          pack: diagnostic,
          options: const <PackOption>[],
        ),
        5000,
      );
      expect(
        BookingRules.totalDurationMinutes(
          pack: diagnostic,
          options: const <PackOption>[],
        ),
        45,
      );
    });

    test('les options s’ajoutent aux deux totaux', () {
      expect(
        BookingRules.totalPrice(pack: diagnostic, options: <PackOption>[joint]),
        6500,
      );
      expect(
        BookingRules.totalDurationMinutes(
          pack: diagnostic,
          options: <PackOption>[joint],
        ),
        60,
      );
    });

    test('une option peut coûter sans allonger la durée', () {
      expect(
        BookingRules.totalPrice(
          pack: diagnostic,
          options: <PackOption>[horsHoraires],
        ),
        7000,
      );
      expect(
        BookingRules.totalDurationMinutes(
          pack: diagnostic,
          options: <PackOption>[horsHoraires],
        ),
        45,
      );
    });

    test('le total du brouillon correspond au montant figé par le service', () {
      final BookingDraft draft = BookingDraft(
        provider: provider,
        pack: diagnostic,
        optionIds: <String>{joint.id},
        scheduledAt: DateTime.utc(2026, 8, 3, 9),
        address: address,
      );

      // `quotedAmount` de la capture `booking/booking:created`.
      expect(draft.totalPrice, 6500);
      expect(draft.totalDurationMinutes, 60);
    });
  });

  group('Délai minimum (FR-032, scénario 2.6)', () {
    final DateTime now = DateTime.utc(2026, 8, 1, 8);

    test('le premier instant réservable suit le réglage en vigueur', () {
      expect(
        BookingRules.earliestStart(now: now, minLeadTimeMinutes: 60),
        DateTime.utc(2026, 8, 1, 9),
      );
    });

    test('un horaire trop proche est refusé', () {
      expect(
        BookingRules.respectsLeadTime(
          scheduledAt: DateTime.utc(2026, 8, 1, 8, 59),
          now: now,
          minLeadTimeMinutes: 60,
        ),
        isFalse,
      );
      expect(
        BookingRules.respectsLeadTime(
          scheduledAt: DateTime.utc(2026, 8, 1, 9),
          now: now,
          minLeadTimeMinutes: 60,
        ),
        isTrue,
      );
    });

    test('le délai vient du réglage, pas d’une constante d’écran', () {
      // Avec un réglage différent, la borne bouge : c'est ce que la porte G3 exige.
      expect(
        BookingRules.respectsLeadTime(
          scheduledAt: DateTime.utc(2026, 8, 1, 9),
          now: now,
          minLeadTimeMinutes: 120,
        ),
        isFalse,
      );
    });
  });

  group('Composition de l’instant — référentiel UTC', () {
    test('l’instant est construit sur les composantes UTC', () {
      final DateTime instant = BookingRules.instantFor(
        day: DateTime.utc(2026, 8, 3),
        time: ClockTime.parse('09:00'),
      );

      expect(instant.isUtc, isTrue);
      expect(instant.toIso8601String(), '2026-08-03T09:00:00.000Z');
      expect(
        MissionDates.toApi(instant),
        '2026-08-03T09:00:00.000Z',
        reason:
            'le service compare `getUTCHours()` aux chaînes HH:MM de l’agenda : '
            'un instant local décalerait l’heure et ferait échouer la réservation',
      );
    });

    test(
      'le jour de la semaine suit la convention du service (0 = dimanche)',
      () {
        // 2026-08-02 est un dimanche.
        expect(BookingRules.weekdayOf(DateTime.utc(2026, 8, 2, 9)), 0);
        expect(BookingRules.weekdayOf(DateTime.utc(2026, 8, 3, 9)), 1);
        expect(BookingRules.weekdayOf(DateTime.utc(2026, 8, 8, 9)), 6);
      },
    );
  });

  group('Créneaux proposables (FR-031, scénario 2.7)', () {
    // 2026-08-03 est un lundi : agenda 08:00–12:00 puis 14:00–18:00.
    final DateTime monday = DateTime.utc(2026, 8, 3);
    final DateTime now = DateTime.utc(2026, 8, 1, 8);

    List<String> startsFor(int durationMinutes) =>
        BookingRules.availableStartTimes(
          provider: provider,
          day: monday,
          durationMinutes: durationMinutes,
          now: now,
          minLeadTimeMinutes: 60,
        ).map((ClockTime time) => time.value).toList();

    test('une intervention courte remplit les deux créneaux du lundi', () {
      final List<String> starts = startsFor(60);

      expect(starts.first, '08:00');
      expect(
        starts,
        contains('11:00'),
        reason: '11:00 + 1 h = 12:00, la borne exacte du créneau',
      );
      expect(
        starts,
        isNot(contains('11:30')),
        reason: 'une heure à partir de 11:30 déborderait de 12:00',
      );
      expect(starts, contains('14:00'));
      expect(starts, contains('17:00'));
      expect(starts, isNot(contains('17:30')));
    });

    test('les débuts sont triés, sans doublon entre les deux créneaux', () {
      final List<String> starts = startsFor(60);

      expect(starts, equals(<String>[...starts]..sort()));
      expect(starts.toSet(), hasLength(starts.length));
    });

    test('une durée qui ne tient dans aucun créneau ne propose rien', () {
      expect(
        startsFor(300),
        isEmpty,
        reason: 'aucun créneau du lundi ne fait cinq heures',
      );
    });

    test('la durée totale — options comprises — recule la dernière borne', () {
      // Les débuts sont sur une grille de 30 minutes depuis l'ouverture du créneau.
      // Sur 08:00–12:00 : 90 min tiennent encore à 10:30, 120 min seulement
      // jusqu'à 10:00.
      expect(startsFor(90).last, '16:30');
      expect(
        startsFor(90),
        contains('10:30'),
        reason: '10:30 + 1 h 30 = 12:00, la borne exacte du créneau du matin',
      );
      expect(startsFor(120), isNot(contains('10:30')));
      expect(startsFor(120), contains('10:00'));
    });

    test('une durée nulle ou négative ne propose rien', () {
      expect(startsFor(0), isEmpty);
      expect(startsFor(-30), isEmpty);
    });

    test('un jour sans agenda ne propose rien', () {
      final ProviderPublicProfile bare = profileFrom('newProvider');

      expect(
        BookingRules.availableStartTimes(
          provider: bare,
          day: monday,
          durationMinutes: 60,
          now: now,
          minLeadTimeMinutes: 60,
        ),
        isEmpty,
      );
    });
  });

  group('Absences et délai écartent des débuts', () {
    final DateTime now = DateTime.utc(2026, 8, 1, 8);

    test('une absence annoncée retire toute la journée', () {
      // L'absence court du 2026-08-05 au 2026-08-07 : le mercredi 5 est couvert.
      expect(
        BookingRules.hasAvailability(
          provider: provider,
          day: DateTime.utc(2026, 8, 5),
          durationMinutes: 60,
          now: now,
          minLeadTimeMinutes: 60,
        ),
        isFalse,
      );
      expect(
        BookingRules.hasAvailability(
          provider: provider,
          day: DateTime.utc(2026, 8, 3),
          durationMinutes: 60,
          now: now,
          minLeadTimeMinutes: 60,
        ),
        isTrue,
      );
    });

    test('le délai minimum ampute le début de la journée courante', () {
      // Lundi 3 août, il est 08:00 ; avec 60 minutes de délai, rien avant 09:00.
      final List<ClockTime> starts = BookingRules.availableStartTimes(
        provider: provider,
        day: DateTime.utc(2026, 8, 3),
        durationMinutes: 60,
        now: DateTime.utc(2026, 8, 3, 8),
        minLeadTimeMinutes: 60,
      );

      expect(starts.first.value, '09:00');
      expect(starts.map((ClockTime t) => t.value), isNot(contains('08:00')));
    });
  });

  group('Cohérence du brouillon', () {
    test('changer de formule remet les options et la date à zéro', () {
      final BookingDraft draft = BookingDraft(
        provider: provider,
        pack: diagnostic,
        optionIds: <String>{joint.id},
        scheduledAt: DateTime.utc(2026, 8, 3, 9),
        address: address,
      );

      final BookingDraft next = draft.withPack(provider.packs.last);

      expect(next.optionIds, isEmpty);
      expect(
        next.scheduledAt,
        isNull,
        reason: 'la durée a changé : le créneau retenu peut ne plus tenir',
      );
      expect(
        next.address,
        isNotNull,
        reason: 'l’adresse, elle, reste valable (FR-035)',
      );
    });

    test('cocher une option efface la date, pour la même raison', () {
      final BookingDraft draft = BookingDraft(
        provider: provider,
        pack: diagnostic,
        scheduledAt: DateTime.utc(2026, 8, 3, 9),
        address: address,
      );

      expect(draft.toggleOption(joint.id).scheduledAt, isNull);
    });

    test('une option devenue caduque disparaît d’elle-même', () {
      final BookingDraft draft = BookingDraft(
        provider: provider,
        pack: provider.packs.last,
        optionIds: <String>{joint.id},
      );

      expect(
        draft.selectedOptions,
        isEmpty,
        reason: 'le service refuserait « Option inconnue pour cette formule »',
      );
      expect(draft.totalPrice, provider.packs.last.price);
    });

    test('l’étape suivante est la première case manquante', () {
      final BookingDraft empty = BookingDraft(provider: provider);
      expect(empty.nextStep, BookingStep.pack);

      final BookingDraft withPack = empty.withPack(diagnostic);
      expect(withPack.nextStep, BookingStep.schedule);

      final BookingDraft scheduled = withPack.copyWith(
        scheduledAt: DateTime.utc(2026, 8, 3, 9),
      );
      expect(scheduled.nextStep, BookingStep.address);

      final BookingDraft complete = scheduled.copyWith(address: address);
      expect(complete.nextStep, BookingStep.summary);
      expect(complete.isComplete, isTrue);
    });

    test('le corps de requête part en UTC, options triées', () {
      final BookingDraft draft = BookingDraft(
        provider: provider,
        pack: diagnostic,
        optionIds: <String>{horsHoraires.id, joint.id},
        scheduledAt: DateTime.utc(2026, 8, 3, 9),
        address: address,
        instructions: '  Portail bleu.  ',
      );

      final Map<String, Object?> body = draft.toRequestBody();
      expect(body['scheduledAt'], '2026-08-03T09:00:00.000Z');
      expect(body['optionIds'], <String>[joint.id, horsHoraires.id]..sort());
      expect(body['instructions'], 'Portail bleu.');
      expect(body['providerId'], provider.id);
    });

    test('un brouillon incomplet refuse de produire un corps', () {
      expect(
        () => BookingDraft(provider: provider).toRequestBody(),
        throwsA(isA<StateError>()),
      );
    });

    test('des instructions vides ne sont pas transmises', () {
      final BookingDraft draft = BookingDraft(
        provider: provider,
        pack: diagnostic,
        scheduledAt: DateTime.utc(2026, 8, 3, 9),
        address: address,
        instructions: '   ',
      );

      expect(draft.toRequestBody().containsKey('instructions'), isFalse);
    });
  });

  group('Formatage des durées', () {
    test(
      'sous une heure',
      () => expect(BookingRules.formatDuration(45), '45 min'),
    );
    test('heure ronde', () => expect(BookingRules.formatDuration(120), '2 h'));
    test('heure et minutes', () {
      expect(BookingRules.formatDuration(75), '1 h 15');
      expect(BookingRules.formatDuration(65), '1 h 05');
    });
  });
}
