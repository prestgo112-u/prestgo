// T145 — Règles locales de l'agenda hebdomadaire (data-model §4.4).
//
// Ces règles existent côté client parce que les messages serveur correspondants
// ne sont pas contractualisés (Swagger muet sur l'ordre et le chevauchement) : il
// faut pouvoir refuser AVANT l'envoi avec un message stable (scénario 4.5). Le
// service reste l'autorité — c'est un confort de saisie, pas une décision.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/features/provider_space/domain/weekly_slot.dart';

void main() {
  group('validateWeeklySlots — cas valides', () {
    test('agenda vide : rien à redire (c’est la checklist qui exigera un '
        'créneau)', () {
      expect(validateWeeklySlots(const <WeeklySlot>[]), isNull);
    });

    test('journée coupée en deux + jour plein : valide', () {
      expect(
        validateWeeklySlots(const <WeeklySlot>[
          WeeklySlot(weekday: 1, startTime: '08:00', endTime: '12:00'),
          WeeklySlot(weekday: 1, startTime: '14:00', endTime: '18:00'),
          WeeklySlot(weekday: 2, startTime: '08:00', endTime: '18:00'),
        ]),
        isNull,
      );
    });

    test('se TOUCHER n’est pas se chevaucher : 08–12 puis 12–14 passe', () {
      expect(
        validateWeeklySlots(const <WeeklySlot>[
          WeeklySlot(weekday: 3, startTime: '08:00', endTime: '12:00'),
          WeeklySlot(weekday: 3, startTime: '12:00', endTime: '14:00'),
        ]),
        isNull,
      );
    });

    test(
      'les mêmes heures sur deux jours différents ne se chevauchent pas',
      () {
        expect(
          validateWeeklySlots(const <WeeklySlot>[
            WeeklySlot(weekday: 1, startTime: '08:00', endTime: '18:00'),
            WeeklySlot(weekday: 2, startTime: '08:00', endTime: '18:00'),
          ]),
          isNull,
        );
      },
    );

    test('exactement 50 créneaux : au plafond, pas au-delà', () {
      final List<WeeklySlot> fifty = List<WeeklySlot>.generate(
        50,
        (int i) => WeeklySlot(
          weekday: i % 7,
          // 7 créneaux d'une minute par jour au plus : jamais de chevauchement.
          startTime: '0${i ~/ 7}:${(i % 7).toString().padLeft(2, '0')}',
          endTime: '0${i ~/ 7}:${(i % 7 + 1).toString().padLeft(2, '0')}',
        ),
      );
      expect(validateWeeklySlots(fifty), isNull);
    });
  });

  group('validateWeeklySlots — refus', () {
    test('fin avant début', () {
      expect(
        validateWeeklySlots(const <WeeklySlot>[
          WeeklySlot(weekday: 1, startTime: '18:00', endTime: '08:00'),
        ]),
        contains('L’heure de fin doit être après l’heure de début'),
      );
    });

    test('fin égale au début : un créneau vide est refusé aussi', () {
      expect(
        validateWeeklySlots(const <WeeklySlot>[
          WeeklySlot(weekday: 1, startTime: '08:00', endTime: '08:00'),
        ]),
        contains('L’heure de fin doit être après l’heure de début'),
      );
    });

    test('chevauchement sur le même jour, signalé AVANT l’envoi (4.5)', () {
      final String? error = validateWeeklySlots(const <WeeklySlot>[
        WeeklySlot(weekday: 1, startTime: '08:00', endTime: '12:00'),
        WeeklySlot(weekday: 1, startTime: '11:00', endTime: '15:00'),
      ]);
      expect(error, contains('se chevauchent'));
      expect(error, contains('lundi'));
    });

    test('un créneau qui en contient un autre est un chevauchement', () {
      expect(
        validateWeeklySlots(const <WeeklySlot>[
          WeeklySlot(weekday: 5, startTime: '08:00', endTime: '18:00'),
          WeeklySlot(weekday: 5, startTime: '10:00', endTime: '11:00'),
        ]),
        contains('se chevauchent'),
      );
    });

    test('jour hors 0-6', () {
      expect(
        validateWeeklySlots(const <WeeklySlot>[
          WeeklySlot(weekday: 7, startTime: '08:00', endTime: '12:00'),
        ]),
        'Le jour va de 0 (dimanche) à 6 (samedi).',
      );
      expect(
        validateWeeklySlots(const <WeeklySlot>[
          WeeklySlot(weekday: -1, startTime: '08:00', endTime: '12:00'),
        ]),
        'Le jour va de 0 (dimanche) à 6 (samedi).',
      );
    });

    test('heure mal formée', () {
      expect(
        validateWeeklySlots(const <WeeklySlot>[
          WeeklySlot(weekday: 1, startTime: '8h00', endTime: '12:00'),
        ]),
        'Les heures doivent être au format HH:MM.',
      );
      expect(
        validateWeeklySlots(const <WeeklySlot>[
          WeeklySlot(weekday: 1, startTime: '24:00', endTime: '25:00'),
        ]),
        'Les heures doivent être au format HH:MM.',
      );
    });

    test('51 créneaux : plafond dépassé', () {
      final List<WeeklySlot> tooMany = List<WeeklySlot>.generate(
        51,
        (int i) => WeeklySlot(
          weekday: i % 7,
          startTime: '${(i ~/ 7).toString().padLeft(2, '0')}:00',
          endTime: '${(i ~/ 7).toString().padLeft(2, '0')}:30',
        ),
      );
      expect(
        validateWeeklySlots(tooMany),
        'Un agenda hebdomadaire ne peut pas dépasser 50 créneaux.',
      );
    });
  });

  group('Ordre d’affichage', () {
    test('dimanche en premier — la convention du service (0 = dimanche)', () {
      expect(weekdayLabels.first, 'Dimanche');
      expect(weekdayLabels.last, 'Samedi');
      expect(weekdayLabel(0), 'Dimanche');
      expect(weekdayLabel(6), 'Samedi');
      expect(weekdayLabel(9), 'Jour 9');
    });
  });
}
