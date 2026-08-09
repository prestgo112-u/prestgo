// T191 — Parcours US6 de bout en bout : scénarios 6.1 à 6.4 de quickstart.md.
//
// La messagerie sans temps réel : ouverture sur les récents, historique chargé en
// remontant, marquage lu répercuté sur les compteurs, envoi optimiste avec renvoi
// **manuel**. Le service simulé porte un fil de 47 messages — assez pour trois
// pages — et peut couper le réseau sur l'envoi seul (6.3).
//
// Comme pour US1 à US5, les scénarios sont exposés par [runUs6Scenarios] et
// déroulés par deux points d'entrée : sur appareil (`integration_test/`) et sans
// appareil (`test/flows/`), ce dernier étant le seul que `flutter test` atteint —
// donc le seul que l'intégration continue exécute.
//
// Le scénario 6.3 traverse la **chaîne d'intercepteurs de production** : le POST
// échoue au transport, et le compte d'appels prouve que la politique de rejeu
// épargne cette route (aucune clé d'idempotence — un rejeu dupliquerait).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/app/router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';

import '../../test/support/fixtures.dart';
import '../../test/support/recording_adapter.dart';
import '../../test/support/screen_harness.dart';
import '../support/app_harness.dart';

const String kMeId = 'c4f8a2e1-9d3b-4e5a-8f6c-1a2b3c4d5e6f';
const String kProviderUserId = '71e88780-d204-4145-b06d-b9e3acdbb365';
const String kThreadId = 't-1';
const String kMissionId = 'b86332d9-14a0-4ec8-b5d0-d0158ae1824d';
const String kMessagesPath = '/messages/threads/$kThreadId/messages';

/// Service simulé de la messagerie.
class MessagingBackend {
  MessagingBackend() {
    // Un fil de 47 messages — trois pages de 20. Le dernier vient de
    // l'interlocuteur et n'est pas lu : c'est lui que portent les compteurs.
    final DateTime base = DateTime.utc(2026, 7, 20, 8);
    for (int i = 1; i <= 47; i++) {
      _messages.add(<String, Object?>{
        'id': 'm-$i',
        'senderId': i.isEven ? kMeId : kProviderUserId,
        'message': 'Message n°$i',
        'createdAt': base.add(Duration(minutes: i)).toIso8601String(),
        'readAt': i == 47
            ? null
            : base.add(Duration(minutes: i + 1)).toIso8601String(),
        'files': const <Object?>[],
      });
    }
  }

  final List<JsonMap> _messages = <JsonMap>[];

  /// Statut du fil — `closed` pour le scénario 6.4.
  String threadStatus = 'open';

  /// Coupe le réseau sur l'envoi **seulement** (6.3).
  bool postDown = false;

  int _sent = 0;

  /// Non-lus : les messages de l'autre partie sans date de lecture.
  int get _unread => _messages
      .where((JsonMap m) => m['senderId'] != kMeId && m['readAt'] == null)
      .length;

  AdapterResponse handle(RequestOptions options, int index) {
    final String path = options.path;

    switch (path) {
      case '/me':
        return fixture('auth/me', 'client');

      case '/me/threads':
        return (
          200,
          <String, Object?>{
            'success': true,
            'message': 'OK',
            'data': <Object?>[_threadPayload()],
            'meta': <String, Object?>{'page': 1, 'limit': 20, 'total': 1},
          },
        );

      case '/me/threads/unread-count':
        return envelope(<String, Object?>{'unread': _unread});

      case '/missions/$kMissionId/thread':
        return envelope(<String, Object?>{
          'id': kThreadId,
          'missionId': kMissionId,
          'status': threadStatus,
          'messageCount': _messages.length,
          'createdAt': _messages.first['createdAt'],
        });

      case '/messages/threads/$kThreadId/read':
        int updated = 0;
        for (final JsonMap m in _messages) {
          if (m['senderId'] != kMeId && m['readAt'] == null) {
            m['readAt'] = DateTime.now().toUtc().toIso8601String();
            updated++;
          }
        }
        return (
          200,
          <String, Object?>{
            'success': true,
            'message': '$updated message(s) marqué(s) lu(s)',
            'data': <String, Object?>{'updated': updated},
          },
        );

      case kMessagesPath:
        if (options.method == 'POST') {
          return _send(options);
        }
        return _page(options);

      default:
        return (
          404,
          <String, Object?>{
            'success': false,
            'message': 'Route non simulée : $path',
          },
        );
    }
  }

  /// Une page de messages, selon `page`, `limit` et `sort` — comme le service.
  AdapterResponse _page(RequestOptions options) {
    final Map<String, String> query = options.uri.queryParameters;
    final int page = int.tryParse(query['page'] ?? '') ?? 1;
    final int limit = int.tryParse(query['limit'] ?? '') ?? 20;
    final bool newestFirst = query['sort'] == '-createdAt';

    final List<JsonMap> ordered = newestFirst
        ? _messages.reversed.toList()
        : _messages;
    final int from = (page - 1) * limit;
    final List<JsonMap> slice = from >= ordered.length
        ? const <JsonMap>[]
        : ordered.sublist(
            from,
            (from + limit) > ordered.length ? ordered.length : from + limit,
          );

    return (
      200,
      <String, Object?>{
        'success': true,
        'message': 'OK',
        'data': slice,
        'meta': <String, Object?>{
          'page': page,
          'limit': limit,
          'total': _messages.length,
        },
      },
    );
  }

  AdapterResponse _send(RequestOptions options) {
    if (postDown) {
      throw const NetworkDown();
    }
    final Map<String, Object?> body = options.data is Map<Object?, Object?>
        ? (options.data as Map<Object?, Object?>).cast<String, Object?>()
        : <String, Object?>{};
    final JsonMap created = <String, Object?>{
      'id': 'm-envoyé-${++_sent}',
      'senderId': kMeId,
      'message': body['message'],
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'readAt': null,
      'files': const <Object?>[],
    };
    _messages.add(created);
    return (
      201,
      <String, Object?>{
        'success': true,
        'message': 'Message envoyé',
        'data': created,
      },
    );
  }

  JsonMap _threadPayload() {
    final JsonMap last = _messages.last;
    return <String, Object?>{
      'id': kThreadId,
      'missionId': kMissionId,
      'missionStatus': threadStatus == 'open' ? 'confirmed' : 'closed',
      'scheduledAt': '2026-08-03T14:00:00.000Z',
      'status': threadStatus,
      'counterpartName': 'Kofi Plomberie',
      'counterpartAvatarFileId': null,
      'lastMessage': <String, Object?>{
        'id': last['id'],
        'message': last['message'],
        'senderId': last['senderId'],
        'createdAt': last['createdAt'],
      },
      'unreadCount': _unread,
      'createdAt': _messages.first['createdAt'],
    };
  }
}

/// Déroule les scénarios 6.1 à 6.4.
void runUs6Scenarios() {
  late MessagingBackend backend;
  late RecordingAdapter adapter;
  late LocalDatabase database;
  late InMemoryTokenStore tokenStore;
  late ProviderContainer container;

  setUp(() {
    backend = MessagingBackend();
    adapter = RecordingAdapter(backend.handle);
    database = LocalDatabase.memory();
    tokenStore = InMemoryTokenStore();
    container = buildAppContainer(
      adapter: adapter,
      database: database,
      tokenStore: tokenStore,
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  void signIn() => tokenStore.tokens = const AuthTokens(
    accessToken: 'access',
    refreshToken: 'refresh',
  );

  Future<void> start(WidgetTester tester, {String? at}) async {
    await tester.pumpWidget(FlowApp(container: container));
    await tester.pumpAndSettle();
    if (at != null) {
      container.read(goRouterProvider).go(at);
      await tester.pumpAndSettle();
    }
  }

  int postCount() => adapter
      .callsToPath(kMessagesPath)
      .where((RequestOptions o) => o.method == 'POST')
      .length;

  // --- 6.1 — Récents d'emblée, historique en remontant --------------------------

  testWidgets('6.1 — le fil ouvre sur les récents, l’historique se charge en '
      'remontant', (WidgetTester tester) async {
    signIn();
    await start(tester, at: Routes.threads);

    await tester.tap(find.text('Kofi Plomberie'));
    await tester.pumpAndSettle();

    // Les plus récents sont visibles d'emblée ; la page 27 n'est pas là.
    expect(find.text('Message n°47'), findsOneWidget);
    expect(find.text('Message n°27'), findsNothing);

    final RequestOptions firstLoad = adapter.callsToPath(kMessagesPath).first;
    expect(
      firstLoad.uri.queryParameters['sort'],
      '-createdAt',
      reason:
          'le tri par défaut du service est croissant — sans ce paramètre, '
          'la page 1 serait le DÉBUT du fil',
    );
    expect(firstLoad.uri.queryParameters['page'], '1');

    // Remonter l'historique : dans une liste inversée, tirer vers le bas.
    for (
      int i = 0;
      i < 8 && find.text('Message n°27').evaluate().isEmpty;
      i++
    ) {
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
    }

    expect(find.text('Message n°27'), findsOneWidget);
    expect(
      adapter
          .callsToPath(kMessagesPath)
          .any((RequestOptions o) => o.uri.queryParameters['page'] == '2'),
      isTrue,
      reason: 'l’historique arrive par pages, jamais le fil entier (6.1)',
    );
  });

  // --- 6.2 — Compteurs remis à zéro en quittant ----------------------------------

  testWidgets('6.2 — quitter la conversation : compteur du fil à zéro, '
      'pastille globale décrémentée', (WidgetTester tester) async {
    signIn();
    await start(tester, at: Routes.threads);

    // Avant : le badge du fil ET la pastille globale portent le même « 1 ».
    expect(find.text('1'), findsNWidgets(2));

    await tester.tap(find.text('Kofi Plomberie'));
    await tester.pumpAndSettle();

    expect(
      adapter.callsToPath('/messages/threads/$kThreadId/read'),
      hasLength(1),
      reason: 'le marquage lu part à l’ouverture (FR-079)',
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(
      find.text('1'),
      findsNothing,
      reason: 'compteur du fil à zéro et pastille globale décrémentée (6.2)',
    );
  });

  // --- 6.3 — Envoi coupé : échec visible, renvoi manuel, aucun doublon -----------

  testWidgets('6.3 — envoi réseau coupé : bulle en échec, renvoi manuel, '
      'aucun doublon', (WidgetTester tester) async {
    signIn();
    await start(
      tester,
      at: Routes.conversationFor(kThreadId, missionId: kMissionId),
    );
    expect(find.text('Message n°47'), findsOneWidget);

    backend.postDown = true;
    await tester.enterText(
      find.byType(TextField),
      'Bonjour, arrivée prévue à 14h.',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.pumpAndSettle();

    // La bulle est en échec, le renvoi est offert — et UN SEUL appel est parti :
    // la chaîne d'intercepteurs de production n'a pas rejoué cette route.
    expect(find.text('Échec de l’envoi'), findsOneWidget);
    expect(find.text('Renvoyer'), findsOneWidget);
    expect(
      postCount(),
      1,
      reason: 'aucun rejeu automatique — un rejeu créerait un doublon (6.3)',
    );

    backend.postDown = false;
    await tester.tap(find.text('Renvoyer'));
    await tester.pumpAndSettle();

    expect(postCount(), 2);
    expect(find.text('Échec de l’envoi'), findsNothing);
    expect(
      find.text('Bonjour, arrivée prévue à 14h.'),
      findsOneWidget,
      reason: 'la bulle livrée remplace la bulle en échec — aucun doublon',
    );
  });

  // --- 6.4 — Fil clôturé : saisie masquée avec explication -----------------------

  testWidgets('6.4 — un fil clôturé masque la saisie et l’explique', (
    WidgetTester tester,
  ) async {
    backend.threadStatus = 'closed';
    signIn();
    await start(tester, at: Routes.threads);

    await tester.tap(find.text('Kofi Plomberie'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('Conversation clôturée'), findsOneWidget);
    expect(
      find.text('Message n°47'),
      findsOneWidget,
      reason: 'le fil reste consultable — seul l’envoi est retiré (6.4)',
    );
  });
}
