// T142 — Contrat de l'agenda hebdomadaire (opérations 79 et 80).
//
// Les pièges de cette paire :
//   • les heures sont des **chaînes** `HH:MM`, interprétées en UTC par le
//     service : elles partent et reviennent TELLES QUELLES, sans l'ombre d'une
//     conversion de fuseau ;
//   • la lecture est le **miroir exact** de l'écriture — pas de re-tri, pas de
//     fusion côté client ;
//   • plafond de **50** créneaux ; chevauchement et ordre des heures sont
//     contrôlés côté service avec des messages non contractualisés — d'où les
//     contrôles locaux de `validateWeeklySlots`, testés à part (T145).

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_space/domain/weekly_slot.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const List<WeeklySlot> kMondayAndTuesday = <WeeklySlot>[
  WeeklySlot(weekday: 1, startTime: '08:00', endTime: '12:00'),
  WeeklySlot(weekday: 1, startTime: '14:00', endTime: '18:00'),
  WeeklySlot(weekday: 2, startTime: '08:00', endTime: '18:00'),
];

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'provider/availabilities',
    caseName,
  );
  return ApiHarness.always(status, body);
}

ProviderSelfRepository repositoryOn(ApiHarness harness) =>
    ProviderSelfRepository(harness.client);

void main() {
  group('Opération 79 — GET /providers/me/availabilities', () {
    test(
      'la lecture rend les créneaux tels quels, heures NON converties',
      () async {
        final ApiHarness harness = harnessFor('mirror');

        final List<WeeklySlot> slots = await repositoryOn(
          harness,
        ).availabilities();

        expect(harness.lastUrl, endsWith('/providers/me/availabilities'));
        expect(slots, kMondayAndTuesday);
        expect(
          slots.first.startTime,
          '08:00',
          reason: 'la chaîne du service, pas une TimeOfDay reformatée',
        );
      },
    );

    test('agenda jamais renseigné : liste vide, pas d’erreur', () async {
      expect(
        await repositoryOn(harnessFor('mirrorEmpty')).availabilities(),
        isEmpty,
      );
    });
  });

  group('Opération 80 — PUT /providers/me/availabilities', () {
    test(
      'remplacement intégral : {slots: […]} avec les trois champs seuls',
      () async {
        final ApiHarness harness = harnessFor('replaced');

        final AvailabilitiesUpdate update = await repositoryOn(
          harness,
        ).replaceAvailabilities(kMondayAndTuesday);

        expect(harness.lastCall.method, 'PUT');
        expect(harness.lastBody, <String, Object?>{
          'slots': <Object?>[
            <String, Object?>{
              'weekday': 1,
              'startTime': '08:00',
              'endTime': '12:00',
            },
            <String, Object?>{
              'weekday': 1,
              'startTime': '14:00',
              'endTime': '18:00',
            },
            <String, Object?>{
              'weekday': 2,
              'startTime': '08:00',
              'endTime': '18:00',
            },
          ],
        });
        expect(update.message, 'Disponibilités mises à jour');
      },
    );

    test(
      'la lecture qui suit une écriture rend EXACTEMENT ce qui a été écrit',
      () async {
        // PUT puis GET sur le même service simulé : le miroir se vérifie en
        // enchaînant réellement les deux appels.
        final ApiHarness harness = ApiHarness(
          (RequestOptions options, int _) => fixture(
            'provider/availabilities',
            options.method == 'PUT' ? 'replaced' : 'mirror',
          ),
        );
        final ProviderSelfRepository repository = repositoryOn(harness);

        final AvailabilitiesUpdate written = await repository
            .replaceAvailabilities(kMondayAndTuesday);
        final List<WeeklySlot> read = await repository.availabilities();

        expect(read, written.slots);
        expect(read, kMondayAndTuesday);
      },
    );

    test('400 — plafond de 50 créneaux, l’erreur désigne le champ', () async {
      await expectLater(
        repositoryOn(harnessFor('tooManySlots')).replaceAvailabilities(
          List<WeeklySlot>.generate(
            51,
            (int i) => WeeklySlot(
              weekday: i % 7,
              startTime: '08:00',
              endTime: '09:00',
            ),
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.messageForField('slots'),
            'champ slots',
            'Un agenda hebdomadaire ne peut pas dépasser 50 créneaux',
          ),
        ),
      );
    });

    test(
      '400 — refus métier (ordre, chevauchement) : message affiché tel quel',
      () async {
        await expectLater(
          repositoryOn(harnessFor('invalid')).replaceAvailabilities(
            const <WeeklySlot>[
              WeeklySlot(weekday: 1, startTime: '18:00', endTime: '08:00'),
            ],
          ),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.message,
              'message',
              'Jour hors 0-6, heure de fin avant l\'heure de début, ou créneaux '
                  'qui se chevauchent',
            ),
          ),
        );
      },
    );
  });
}
