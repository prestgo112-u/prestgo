// T123 — Contrat des reports (opérations 41 à 44).
//
// Trois règles à ne pas rater, toutes vérifiées ici :
//   • **une seule demande en attente par mission** — le 400 « déjà en attente »
//     existe, l'écran grise l'action avant de l'atteindre (scénario 3.3) ;
//   • le créneau est **revalidé à l'acceptation** — le 400 « n'est plus
//     disponible » ouvre une contre-proposition (scénario 3.5) ;
//   • répondre à **sa propre** demande est un 403 — jamais atteint, les boutons
//     étant masqués sur `createdBy == me.id` (scénario 3.4).

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/missions/data/reschedule_repository.dart';
import 'package:prestgo_mobile/features/missions/domain/reschedule_request.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const String kMissionId = 'b86332d9-14a0-4ec8-b5d0-d0158ae1824d';
const String kRescheduleId = 'r-17c2fa86-be40-4c51-d6f8-0a1b2c3d4e5f';

/// Identité du compte client des captures (`auth/me`, cas `client`).
const String kMeId = 'c4f8a2e1-9d3b-4e5a-8f6c-1a2b3c4d5e6f';

/// Le prestataire de la mission des captures.
const String kProviderId = '66cb6dd8-f882-4944-91ab-b5c052e01b3d';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'missions/reschedules',
    caseName,
  );
  return ApiHarness.always(status, body);
}

RescheduleRepository repositoryOn(ApiHarness harness) =>
    RescheduleRepository(harness.client);

void main() {
  group('Opération 41 — GET /missions/{id}/reschedules', () {
    test('l’historique COMPLET arrive, tous statuts confondus', () async {
      final ApiHarness harness = harnessFor('historyAll');

      final List<RescheduleRequest> history = await repositoryOn(
        harness,
      ).history(kMissionId);

      expect(harness.lastUrl, '$kTestBaseUrl/missions/$kMissionId/reschedules');
      expect(history, hasLength(3));
      expect(history[0].status, RescheduleStatus.requested);
      expect(history[1].status, RescheduleStatus.accepted);
      expect(history[2].status, RescheduleStatus.rejected);
      expect(
        history[2].decisionReason,
        'Je ne suis pas disponible ce soir-là.',
        reason: 'le motif de refus est porté par la décision',
      );
    });

    test('seul `requested` est une demande en attente', () async {
      final List<RescheduleRequest> history = await repositoryOn(
        harnessFor('historyAll'),
      ).history(kMissionId);

      expect(history.where((RescheduleRequest r) => r.isPending), hasLength(1));
    });
  });

  group('Opération 42 — POST /missions/{id}/reschedule', () {
    test('la proposition part en UTC, le motif seulement s’il existe', () async {
      final ApiHarness harness = harnessFor('requested');

      final RescheduleSubmission submission = await repositoryOn(harness)
          .propose(
            kMissionId,
            newDate: DateTime.utc(2026, 8, 6, 10),
            reason: 'Je ne serai pas là mercredi.',
          );

      expect(harness.lastCall.method, 'POST');
      expect(harness.lastUrl, endsWith('/reschedule'));
      expect(harness.lastBody['newDate'], '2026-08-06T10:00:00.000Z');
      expect(harness.lastBody['reason'], 'Je ne serai pas là mercredi.');
      expect(submission.request.status, RescheduleStatus.requested);
      expect(
        submission.request.newScheduledAt,
        DateTime.utc(2026, 8, 6, 10).toLocal(),
      );
      expect(
        submission.message,
        "Demande de report envoyée. Elle doit être acceptée par l'autre partie.",
        reason: 'le message serveur accompagne la demande, affiché tel quel',
      );
    });

    test('sans motif, le champ n’est pas envoyé', () async {
      final ApiHarness harness = harnessFor('requested');

      await repositoryOn(
        harness,
      ).propose(kMissionId, newDate: DateTime.utc(2026, 8, 6, 10));

      expect(harness.lastBody.containsKey('reason'), isFalse);
    });

    test(
      '400 — UNE SEULE demande en attente à la fois (scénario 3.3)',
      () async {
        await expectLater(
          repositoryOn(
            harnessFor('alreadyPending'),
          ).propose(kMissionId, newDate: DateTime.utc(2026, 8, 6, 10)),
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
                  'Une demande de report est déjà en attente de réponse',
                ),
          ),
        );
      },
    );

    test(
      '400 — créneau hors agenda du prestataire : rouvrir le sélecteur',
      () async {
        await expectLater(
          repositoryOn(
            harnessFor('slotUnavailable'),
          ).propose(kMissionId, newDate: DateTime.utc(2026, 8, 6, 10)),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.message,
              'message',
              'Le prestataire ne travaille pas sur ce créneau',
            ),
          ),
        );
      },
    );

    test(
      '400 — le message interpolé du délai minimum est affiché tel quel',
      () async {
        await expectLater(
          repositoryOn(
            harnessFor('tooSoon'),
          ).propose(kMissionId, newDate: DateTime.utc(2026, 8, 1, 9, 30)),
          throwsA(
            isA<ApiException>().having(
              (ApiException e) => e.message,
              'message',
              'La nouvelle date doit être au moins 60 minutes dans le futur',
            ),
          ),
        );
      },
    );

    test('400 — une mission terminée ne se reprogramme plus', () async {
      await expectLater(
        repositoryOn(
          harnessFor('notReschedulable'),
        ).propose(kMissionId, newDate: DateTime.utc(2026, 8, 6, 10)),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            'Une mission au statut « completed » ne peut plus être reprogrammée',
          ),
        ),
      );
    });
  });

  group('Opération 43 — accept : le créneau est REVALIDÉ', () {
    test('200 — la mission est déplacée sur la nouvelle date', () async {
      final ApiHarness harness = harnessFor('accepted');

      final RescheduleDecision decision = await repositoryOn(
        harness,
      ).accept(kMissionId, kRescheduleId);

      expect(harness.lastUrl, endsWith('/reschedule/$kRescheduleId/accept'));
      expect(decision.status, RescheduleStatus.accepted);
      expect(
        decision.scheduledAt,
        DateTime.utc(2026, 8, 6, 10).toLocal(),
        reason: 'la réponse porte la nouvelle date de la mission',
      );
    });

    test(
      '400 — créneau devenu indisponible : contre-proposition (3.5)',
      () async {
        await expectLater(
          repositoryOn(
            harnessFor('slotGone'),
          ).accept(kMissionId, kRescheduleId),
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
                  "Le prestataire n'est plus disponible sur ce créneau",
                ),
          ),
        );
      },
    );

    test('400 — demande déjà traitée : rafraîchir le détail', () async {
      await expectLater(
        repositoryOn(
          harnessFor('alreadyDecided'),
        ).accept(kMissionId, kRescheduleId),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.message,
            'message',
            'Cette demande a déjà été traitée (statut « accepted »)',
          ),
        ),
      );
    });

    test(
      '403 — sa propre demande : un état que l’UI ne doit jamais atteindre',
      () async {
        await expectLater(
          repositoryOn(
            harnessFor('ownRequest'),
          ).accept(kMissionId, kRescheduleId),
          throwsA(
            isA<ApiException>()
                .having(
                  (ApiException e) => e.isForbidden,
                  'isForbidden',
                  isTrue,
                )
                .having(
                  (ApiException e) => e.message,
                  'message',
                  'Vous ne pouvez pas répondre à votre propre demande de report',
                ),
          ),
        );
      },
    );
  });

  group('Opération 44 — reject', () {
    test(
      '200 — la date d’origine tient, le motif part dans le corps',
      () async {
        final ApiHarness harness = harnessFor('rejected');

        final RescheduleDecision decision = await repositoryOn(harness).reject(
          kMissionId,
          kRescheduleId,
          reason: 'Je ne suis pas disponible ce soir-là.',
        );

        expect(harness.lastUrl, endsWith('/reschedule/$kRescheduleId/reject'));
        expect(
          harness.lastBody['reason'],
          'Je ne suis pas disponible ce soir-là.',
        );
        expect(decision.status, RescheduleStatus.rejected);
        expect(decision.scheduledAt, isNull);
      },
    );

    test('400 — le motif de refus est obligatoire', () async {
      await expectLater(
        repositoryOn(
          harnessFor('rejectMissingReason'),
        ).reject(kMissionId, kRescheduleId, reason: ''),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.messageForField('reason'),
            'champ reason',
            'Un motif est obligatoire pour refuser un report',
          ),
        ),
      );
    });
  });

  group('Règles d’affichage portées par le modèle (scénario 3.4)', () {
    test('les actions sont masquées sur SA PROPRE demande', () {
      final RescheduleRequest mine = RescheduleRequest(
        id: 'r-1',
        status: RescheduleStatus.requested,
        createdBy: kMeId,
        createdAt: DateTime.utc(2026, 7, 31),
      );
      final RescheduleRequest theirs = RescheduleRequest(
        id: 'r-2',
        status: RescheduleStatus.requested,
        createdBy: kProviderId,
        createdAt: DateTime.utc(2026, 7, 31),
      );

      expect(mine.isMine(kMeId), isTrue);
      expect(mine.canRespond(kMeId), isFalse);
      expect(theirs.canRespond(kMeId), isTrue);
    });

    test('une demande traitée n’appelle plus aucune réponse', () {
      final RescheduleRequest decided = RescheduleRequest(
        id: 'r-3',
        status: RescheduleStatus.accepted,
        createdBy: kProviderId,
        createdAt: DateTime.utc(2026, 7, 31),
      );

      expect(decided.canRespond(kMeId), isFalse);
    });
  });
}
