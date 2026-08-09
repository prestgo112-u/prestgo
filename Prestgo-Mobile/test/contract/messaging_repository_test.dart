// T179 — Contrat de la messagerie (opérations 48 à 53).
//
// Les singularités de cette famille de routes, toutes vérifiées ici :
//   • le tri par défaut de `GET /messages/threads/{id}/messages` est **croissant** —
//     la page 1 est le DÉBUT du fil ; l'écran demande `sort=-createdAt` pour ouvrir
//     sur les messages récents (écart n°12 clos, FR-075) ;
//   • le compteur global vient de sa route dédiée (écart n°4 clos), jamais d'une
//     somme de première page ;
//   • les plafonds d'envoi (1–4000, ≤ 3 pièces jointes uniques) sont appliqués
//     **avant** tout appel réseau (FR-090) ;
//   • `POST .../messages` n'est **jamais** rejoué automatiquement — la politique de
//     rejeu l'exclut nommément (retry-and-idempotency.md) ;
//   • 400 « Conversation clôturée » : le service est le filet, la saisie est masquée
//     en amont (FR-078) ;
//   • chaque page lue alimente le cache persistant du fil (T189, data-model §12).

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/features/messaging/data/messaging_repository.dart';
import 'package:prestgo_mobile/features/messaging/domain/message.dart';
import 'package:prestgo_mobile/features/messaging/domain/thread.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

late LocalDatabase database;
late CacheDao cache;

/// Identité du compte client des captures (`auth/me`, cas `client`).
const String kMeId = 'c4f8a2e1-9d3b-4e5a-8f6c-1a2b3c4d5e6f';

/// L'interlocuteur des captures — le compte du prestataire.
const String kCounterpartId = '71e88780-d204-4145-b06d-b9e3acdbb365';

const String kThreadId = 'e6499753-89c6-4a9f-bdc9-b3ff4508be47';
const String kMissionId = 'b86332d9-14a0-4ec8-b5d0-d0158ae1824d';

ApiHarness harnessFor(String file, String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'messaging/$file',
    caseName,
  );
  return ApiHarness.always(status, body);
}

MessagingRepository repositoryOn(ApiHarness harness) =>
    MessagingRepository(harness.client, cache);

void main() {
  setUp(() {
    database = LocalDatabase.memory();
    cache = CacheDao(database);
  });

  tearDown(() => database.close());

  group('Opération 48 — GET /me/threads', () {
    test(
      'la liste arrive paginée, l’interlocuteur déjà résolu du bon côté',
      () async {
        final ApiHarness harness = harnessFor('threads', 'firstPage');

        final PagedPage<Thread> page = await repositoryOn(harness).threads();

        expect(harness.lastCall.uri.path, endsWith('/me/threads'));
        expect(harness.lastCall.uri.queryParameters['page'], '1');
        expect(page.items, hasLength(2));
        expect(page.meta?.total, 2);

        final Thread open = page.items.first;
        expect(
          open.counterpartName,
          'Kofi Plomberie',
          reason: 'aucune logique conditionnelle par rôle côté application',
        );
        expect(open.isOpen, isTrue);
        expect(open.unreadCount, 1);
        expect(open.missionId, kMissionId);
        expect(
          open.lastMessage?.message,
          'Bonjour, à quelle heure passez-vous ?',
        );
      },
    );

    test(
      'un fil non ouvert est reconnu — la saisie sera masquée en amont',
      () async {
        final PagedPage<Thread> page = await repositoryOn(
          harnessFor('threads', 'firstPage'),
        ).threads();

        final Thread closed = page.items.last;
        expect(closed.isOpen, isFalse);
        expect(closed.unreadCount, 0);
      },
    );
  });

  group('Opération 49 — GET /me/threads/unread-count', () {
    test(
      'le compteur global vient de sa route dédiée, jamais d’une somme',
      () async {
        final ApiHarness harness = harnessFor('unread_count', 'three');

        final int unread = await repositoryOn(harness).unreadCount();

        expect(unread, 3);
        expect(
          harness.lastUrl,
          '$kTestBaseUrl/me/threads/unread-count',
          reason: 'écart n°4 clos : plus de somme manuelle de /me/threads',
        );
      },
    );
  });

  group('Opération 50 — GET /missions/{id}/thread', () {
    test(
      'la conversation d’une mission s’atteint sans charger /me/threads',
      () async {
        final ApiHarness harness = harnessFor('mission_thread', 'open');

        final MissionThread thread = await repositoryOn(
          harness,
        ).threadForMission(kMissionId);

        expect(
          harness.lastCall.uri.path,
          endsWith('/missions/$kMissionId/thread'),
        );
        expect(thread.id, kThreadId);
        expect(thread.isOpen, isTrue);
        expect(thread.messageCount, 47);
      },
    );

    test('404 — une mission sans conversation', () async {
      await expectLater(
        repositoryOn(
          harnessFor('mission_thread', 'notFound'),
        ).threadForMission('m-sans-fil'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.isNotFound, 'isNotFound', isTrue)
              .having(
                (ApiException e) => e.message,
                'message',
                'Conversation ou mission introuvable',
              ),
        ),
      );
    });
  });

  group('Opération 51 — GET /messages/threads/{id}/messages', () {
    test(
      'l’écran ouvre sur les RÉCENTS : il demande sort=-createdAt',
      () async {
        final ApiHarness harness = harnessFor('messages', 'recentDesc');

        final PagedPage<Message> page = await repositoryOn(
          harness,
        ).messages(kThreadId);

        expect(
          harness.lastCall.uri.queryParameters['sort'],
          '-createdAt',
          reason: 'la page 1 du tri par défaut est le DÉBUT du fil, pas sa fin',
        );
        expect(page.items.first.id, 'm-47');
        expect(page.meta?.total, 47);
        expect(page.meta?.hasMore, isTrue);
      },
    );

    test(
      'le tri par défaut du service reste croissant — page 1 = début du fil',
      () async {
        final ApiHarness harness = harnessFor('messages', 'defaultAsc');

        final PagedPage<Message> page = await repositoryOn(
          harness,
        ).messages(kThreadId, newestFirst: false);

        expect(
          harness.lastCall.uri.queryParameters.containsKey('sort'),
          isFalse,
          reason: 'sans paramètre, l’ordre est celui d’avant la pagination',
        );
        expect(
          page.items.first.message,
          'Bonjour, à quelle heure passez-vous ?',
        );
      },
    );

    test('système, moi, l’autre : les trois auteurs se distinguent', () async {
      final PagedPage<Message> page = await repositoryOn(
        harnessFor('messages', 'recentDesc'),
      ).messages(kThreadId);

      final Message system = page.items.firstWhere(
        (Message m) => m.id == 'm-45',
      );
      expect(
        system.isSystem,
        isTrue,
        reason: 'senderId null = message système',
      );

      final Message mine = page.items.firstWhere((Message m) => m.id == 'm-46');
      expect(mine.isSystem, isFalse);
      expect(mine.isMine(kMeId), isTrue);

      final Message theirs = page.items.firstWhere(
        (Message m) => m.id == 'm-47',
      );
      expect(theirs.isMine(kMeId), isFalse);
      expect(theirs.readAt, isNull);
    });

    test('les pièces jointes arrivent imbriquées `{ file: {...} }` et sont '
        'dépliées en références', () async {
      final PagedPage<Message> page = await repositoryOn(
        harnessFor('messages', 'recentDesc'),
      ).messages(kThreadId);

      final Message withFile = page.items.firstWhere(
        (Message m) => m.id == 'm-44',
      );
      expect(withFile.files, hasLength(1));
      expect(withFile.files.single.id, 'file-plan-1');
      expect(withFile.files.single.mimeType, 'image/jpeg');
      expect(withFile.files.single.originalName, 'compteur.jpg');
    });

    test(
      'chaque page lue alimente le cache du fil, rendu en ordre croissant',
      () async {
        final MessagingRepository repository = repositoryOn(
          harnessFor('messages', 'recentDesc'),
        );

        expect(await repository.cachedMessages(kThreadId), isNull);
        await repository.messages(kThreadId);

        final List<Message>? cached = (await repository.cachedMessages(
          kThreadId,
        ))?.value;
        expect(cached, hasLength(4));
        expect(
          cached!.first.id,
          'm-44',
          reason: 'la relecture hors ligne rend le fil dans son ordre naturel',
        );
        expect(cached.last.id, 'm-47');
      },
    );

    test('l’historique remonté s’AJOUTE au cache — jamais de doublon', () async {
      await repositoryOn(
        harnessFor('messages', 'recentDesc'),
      ).messages(kThreadId);
      // La même page relue puis une page plus ancienne : 4 + 2, pas 4 + 4 + 2.
      await repositoryOn(
        harnessFor('messages', 'recentDesc'),
      ).messages(kThreadId);
      final MessagingRepository repository = repositoryOn(
        harnessFor('messages', 'olderDesc'),
      );
      await repository.messages(kThreadId, page: 2);

      final List<Message>? cached = (await repository.cachedMessages(
        kThreadId,
      ))?.value;
      expect(cached, hasLength(6));
      expect(cached!.first.id, 'm-26');
    });

    test('403 — un fil d’autrui ne se lit pas', () async {
      await expectLater(
        repositoryOn(harnessFor('messages', 'notParty')).messages(kThreadId),
        throwsA(
          isA<ApiException>().having(
            (ApiException e) => e.isForbidden,
            'isForbidden',
            isTrue,
          ),
        ),
      );
    });
  });

  group('Opération 52 — POST /messages/threads/{id}/messages', () {
    test(
      '201 — le message créé revient dans `data` et rejoint le cache du fil',
      () async {
        final ApiHarness harness = harnessFor('send', 'created');
        final MessagingRepository repository = repositoryOn(harness);

        final Message sent = await repository.send(
          kThreadId,
          text: 'Bonjour, je serai là vers 14h.',
        );

        expect(harness.lastCall.method, 'POST');
        expect(harness.lastBody, <String, Object?>{
          'message': 'Bonjour, je serai là vers 14h.',
        });
        expect(sent.isMine(kMeId), isTrue);

        final List<Message>? cached = (await repository.cachedMessages(
          kThreadId,
        ))?.value;
        expect(
          cached?.single.id,
          sent.id,
          reason: 'un message envoyé se relit hors ligne comme les autres',
        );
      },
    );

    test(
      'les pièces jointes partent en `fileIds` — envoyées AU PRÉALABLE',
      () async {
        final ApiHarness harness = harnessFor('send', 'createdWithFiles');

        final Message sent = await repositoryOn(harness).send(
          kThreadId,
          text: "Voici l'emplacement exact.",
          fileIds: const <String>['file-plan-1'],
        );

        expect(harness.lastBody['fileIds'], <String>['file-plan-1']);
        expect(sent.files.single.id, 'file-plan-1');
      },
    );

    test('plafonds appliqués AVANT tout appel réseau', () async {
      final ApiHarness harness = harnessFor('send', 'created');
      final MessagingRepository repository = repositoryOn(harness);

      await expectLater(
        repository.send(kThreadId, text: ''),
        throwsArgumentError,
      );
      await expectLater(
        repository.send(kThreadId, text: 'x' * 4001),
        throwsArgumentError,
      );
      await expectLater(
        repository.send(
          kThreadId,
          text: 'Quatre pièces jointes.',
          fileIds: const <String>['f-1', 'f-2', 'f-3', 'f-4'],
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.send(
          kThreadId,
          text: 'Doublon.',
          fileIds: const <String>['f-1', 'f-1'],
        ),
        throwsArgumentError,
      );

      expect(
        harness.callCount,
        0,
        reason: 'un refus local ne coûte jamais un aller-retour (FR-090)',
      );
    });

    test(
      '400 — fil clôturé : le message du service est corrigeable et affiché',
      () async {
        await expectLater(
          repositoryOn(
            harnessFor('send', 'closed'),
          ).send(kThreadId, text: 'Trop tard ?'),
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
                  'Conversation clôturée',
                ),
          ),
        );
      },
    );
  });

  group('Opération 53 — PATCH /messages/threads/{id}/read', () {
    test(
      'sans corps, à l’ouverture — le service rend le nombre marqué',
      () async {
        final ApiHarness harness = harnessFor('mark_read', 'two');

        final int updated = await repositoryOn(harness).markRead(kThreadId);

        expect(updated, 2);
        expect(harness.lastCall.method, 'PATCH');
        expect(harness.lastUrl, endsWith('/messages/threads/$kThreadId/read'));
        expect(harness.lastCall.data, isNull);
      },
    );

    test('rien à marquer est un succès ordinaire', () async {
      final int updated = await repositoryOn(
        harnessFor('mark_read', 'none'),
      ).markRead(kThreadId);

      expect(updated, 0);
    });
  });
}
