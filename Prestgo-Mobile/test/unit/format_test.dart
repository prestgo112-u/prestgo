// T049 — Formateur XOF et utilitaires de date.
//
// Deux invariants coûteux à découvrir en production (§6 de quickstart.md) :
//   • les dates d'intervention partent en **UTC** — envoyer l'heure locale fait
//     refuser un créneau pourtant valide ;
//   • les heures d'agenda `HH:MM` ne sont **jamais** converties de fuseau — sinon
//     l'agenda d'un prestataire en déplacement se décale.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/format/money.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting(AppFormats.locale);
  });

  group('Montants XOF', () {
    test('n’affiche aucune décimale — le franc CFA n’a pas de sous-unité', () {
      expect(Money.format(15000), isNot(contains(',')));
      expect(Money.format(15000.4), isNot(contains(',')));
      expect(Money.format(15000), contains('XOF'));
    });

    test('sépare les milliers', () {
      final String formatted = Money.format(1250000);
      // Le séparateur de la locale française est une espace insécable.
      expect(formatted.replaceAll(RegExp(r'[\s  ]'), ''), '1250000XOF');
    });

    test('un montant absent affiche « — », jamais « 0 XOF »', () {
      expect(Money.formatOrAbsent(null), Money.absent);
      expect(Money.formatOrAbsent(null), isNot(contains('0')));
      expect(Money.formatOrAbsent(0), contains('0'));
    });

    test('le total reproduit le calcul du service', () {
      expect(
        Money.total(packPrice: 10000, optionPrices: <num>[2500, 1500]),
        14000,
      );
      expect(Money.total(packPrice: 10000, optionPrices: <num>[]), 10000);
    });
  });

  group('Dates d’intervention — UTC', () {
    test('l’envoi convertit systématiquement en UTC', () {
      final DateTime local = DateTime(2026, 8, 12, 9, 30);
      final String sent = MissionDates.toApi(local);

      expect(sent, endsWith('Z'));
      expect(DateTime.parse(sent).isUtc, isTrue);
      expect(
        DateTime.parse(sent).millisecondsSinceEpoch,
        local.millisecondsSinceEpoch,
      );
    });

    test('une date déjà en UTC traverse sans décalage', () {
      final DateTime utc = DateTime.utc(2026, 8, 12, 9, 30);
      expect(MissionDates.toApi(utc), '2026-08-12T09:30:00.000Z');
    });

    test('la lecture ramène en heure locale pour l’affichage', () {
      final DateTime read = MissionDates.fromApi('2026-08-12T09:30:00.000Z');
      expect(read.isUtc, isFalse);
      expect(read.toUtc(), DateTime.utc(2026, 8, 12, 9, 30));
    });

    test('une date absente reste absente', () {
      expect(MissionDates.fromApiOrNull(null), isNull);
      expect(MissionDates.fromApiOrNull(''), isNull);
    });

    test('le filtre de recherche attend AAAA-MM-JJ', () {
      expect(MissionDates.toApiDate(DateTime(2026, 8, 3)), '2026-08-03');
    });
  });

  group('Heures d’agenda — chaînes, sans conversion de fuseau', () {
    test('la valeur transmise est identique à la valeur saisie', () {
      for (final String raw in <String>['00:00', '08:30', '23:59']) {
        expect(ClockTime.parse(raw).value, raw);
      }
    });

    test('l’analyse refuse tout ce qui n’est pas HH:MM sur 24 h', () {
      expect(ClockTime.tryParse('24:00'), isNull);
      expect(ClockTime.tryParse('9:30'), isNull);
      expect(ClockTime.tryParse('09:60'), isNull);
      expect(ClockTime.tryParse('09h30'), isNull);
      expect(() => ClockTime.parse('nope'), throwsFormatException);
    });

    test('la comparaison porte sur les minutes de la journée', () {
      final ClockTime morning = ClockTime.parse('08:00');
      final ClockTime noon = ClockTime.parse('12:00');

      expect(morning < noon, isTrue);
      expect(noon > morning, isTrue);
      expect(morning <= ClockTime.parse('08:00'), isTrue);
      expect(morning, ClockTime.parse('08:00'));
      expect(ClockTime.parse('08:30').minutesOfDay, 510);
    });

    test('une heure d’agenda ne dépend d’aucun instant — rien à convertir', () {
      // Le type ne porte volontairement ni date ni fuseau : il est
      // structurellement impossible de lui appliquer un décalage.
      final ClockTime slot = ClockTime.parse('08:00');
      expect(slot.value, '08:00');
      expect(slot.hour, 8);
      expect(slot.minute, 0);
    });
  });

  group('Jours de la semaine — 0 = dimanche', () {
    test('la convention du service est respectée', () {
      expect(Weekdays.label(0), 'Dimanche');
      expect(Weekdays.label(1), 'Lundi');
      expect(Weekdays.label(6), 'Samedi');
    });

    test('les bornes sont contrôlées', () {
      expect(Weekdays.isValid(0), isTrue);
      expect(Weekdays.isValid(6), isTrue);
      expect(Weekdays.isValid(7), isFalse);
      expect(Weekdays.isValid(-1), isFalse);
      expect(() => Weekdays.label(7), throwsRangeError);
    });

    test(
      'la traduction depuis DateTime décale bien lundi=1 vers dimanche=0',
      () {
        // 2026-08-16 est un dimanche.
        expect(Weekdays.fromDateTime(DateTime.utc(2026, 8, 16)), 0);
        expect(Weekdays.fromDateTime(DateTime.utc(2026, 8, 17)), 1);
        expect(Weekdays.fromDateTime(DateTime.utc(2026, 8, 22)), 6);
      },
    );
  });

  group('Âge des données', () {
    test('les paliers d’affichage', () {
      expect(DateLabels.age(const Duration(seconds: 30)), 'à l’instant');
      expect(DateLabels.age(const Duration(minutes: 5)), 'il y a 5 min');
      expect(DateLabels.age(const Duration(hours: 3)), 'il y a 3 h');
      expect(DateLabels.age(const Duration(days: 1)), 'hier');
      expect(DateLabels.age(const Duration(days: 4)), 'il y a 4 jours');
    });
  });
}
