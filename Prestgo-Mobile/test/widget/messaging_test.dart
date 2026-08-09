// T190 — Écrans de messagerie : conversation, fil clôturé, bulle en échec.
//
// Ce que ces tests protègent :
//   • **la conversation ouvre sur les récents** — la première page demandée porte
//     `sort=-createdAt` (scénario 6.1) ;
//   • **le marquage lu part à l'ouverture** (FR-079) ;
//   • **la saisie est masquée en amont sur un fil non ouvert**, avec explication
//     (FR-078, scénario 6.4) ;
//   • **un envoi échoué reste une bulle en échec** avec « Renvoyer » manuel — un
//     seul POST est parti, rien ne repart tout seul (FR-077, scénario 6.3).

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/messaging/presentation/conversation_screen.dart';
import 'package:prestgo_mobile/features/messaging/presentation/message_composer.dart';
import 'package:prestgo_mobile/features/messaging/presentation/threads_screen.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';

import '../support/fixtures.dart';
import '../support/recording_adapter.dart';
import '../support/screen_harness.dart';

const String kThreadId = 'e6499753-89c6-4a9f-bdc9-b3ff4508be47';
const String kClosedThreadId = 'f7b00864-97d7-4b0a-9cd0-c4005619cf58';
const String kMessagesPath = '/messages/threads/$kThreadId/messages';

/// Profil client des captures — l'identité de « moi » dans les tests.
Me get meClient => Me.fromJson(fixtureData('auth/me', 'client'));

class StubMeController extends MeController {
  StubMeController(this._me);

  final Me? _me;

  @override
  Future<Me?> build() async => _me;
}

/// Coupure réseau simulée sur l'envoi.
class _NetworkDown implements Exception {
  const _NetworkDown();
}

/// Service simulé de la messagerie.
///
/// [sendDownOnce] fait échouer le **premier** envoi seulement : le renvoi manuel
/// du scénario 6.3 doit aboutir. Le drapeau se consomme au POST — l'indice de
/// scénario ne convient pas ici, GET et POST partagent le même chemin.
AdapterScenario messagingBackend({
  bool sendDownOnce = false,
  String messagesCase = 'recentDesc',
}) {
  bool sendDown = sendDownOnce;
  return (RequestOptions options, int index) {
    final String path = options.path;
    if (path == '/me/threads') {
      return fixture('messaging/threads', 'firstPage');
    }
    if (path == '/me/threads/unread-count') {
      return fixture('messaging/unread_count', 'one');
    }
    if (path.endsWith('/read')) {
      return fixture('messaging/mark_read', 'two');
    }
    if (path.contains('/messages/threads/')) {
      if (options.method == 'POST') {
        if (sendDown) {
          sendDown = false;
          throw const _NetworkDown();
        }
        return fixture('messaging/send', 'created');
      }
      return fixture('messaging/messages', messagesCase);
    }
    return (
      404,
      <String, Object?>{
        'success': false,
        'message': 'Route non simulée : $path',
      },
    );
  };
}

Future<ScreenHarness> pumpConversation(
  WidgetTester tester, {
  required AdapterScenario backend,
  String threadId = kThreadId,
}) async {
  final ScreenHarness harness = ScreenHarness(backend);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...harness.overrides,
        meControllerProvider.overrideWith(() => StubMeController(meClient)),
      ],
      child: MaterialApp(home: ConversationScreen(threadId: threadId)),
    ),
  );
  await tester.pumpAndSettle();
  return harness;
}

void main() {
  setUpAll(() => initializeDateFormatting(AppFormats.locale));

  group('Conversation — ouverture sur les récents (6.1)', () {
    testWidgets('la première page demandée est la FIN du fil, saisie visible', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpConversation(
        tester,
        backend: messagingBackend(),
      );

      final RequestOptions firstLoad = harness.adapter.calls.firstWhere(
        (RequestOptions o) => o.path == kMessagesPath,
      );
      expect(
        firstLoad.uri.queryParameters['sort'],
        '-createdAt',
        reason:
            'le tri par défaut du service est croissant : sans ce '
            'paramètre, la page 1 serait le DÉBUT de la conversation',
      );

      // Les récents sont là, la saisie aussi (fil ouvert).
      expect(find.text('Parfait, à demain.'), findsOneWidget);
      expect(find.byType(MessageComposer), findsOneWidget);

      // Le message système est rendu comme tel, sans bulle d'auteur.
      expect(find.text('Mission confirmée.'), findsOneWidget);

      await harness.dispose(tester);
    });

    testWidgets('le marquage lu part à l’ouverture (FR-079)', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpConversation(
        tester,
        backend: messagingBackend(),
      );

      expect(
        harness.adapter.countFor('/messages/threads/$kThreadId/read'),
        1,
        reason: 'ouvrir la conversation marque le fil lu, une fois',
      );

      await harness.dispose(tester);
    });
  });

  group('Fil clôturé (6.4)', () {
    testWidgets('la saisie est masquée, avec explication — le fil se lit', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpConversation(
        tester,
        backend: messagingBackend(messagesCase: 'defaultAsc'),
        threadId: kClosedThreadId,
      );

      expect(find.byType(MessageComposer), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.textContaining('Conversation clôturée'),
        findsOneWidget,
        reason: 'jamais un champ muet : l’explication accompagne le masquage',
      );
      // Les messages restent consultables.
      expect(
        find.text('Bonjour, à quelle heure passez-vous ?'),
        findsOneWidget,
      );

      await harness.dispose(tester);
    });
  });

  group('Bulle en échec et renvoi manuel (6.3)', () {
    testWidgets('un envoi coupé devient une bulle en échec — UN seul POST', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpConversation(
        tester,
        backend: messagingBackend(sendDownOnce: true),
      );

      await tester.enterText(
        find.byType(TextField),
        'Bonjour, je serai là vers 14h.',
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();

      expect(find.text('Échec de l’envoi'), findsOneWidget);
      expect(find.text('Renvoyer'), findsOneWidget);
      expect(
        harness.adapter.calls
            .where(
              (RequestOptions o) =>
                  o.path == kMessagesPath && o.method == 'POST',
            )
            .length,
        1,
        reason: 'aucun rejeu automatique : un rejeu créerait des doublons',
      );

      // Renvoi MANUEL : le réseau est revenu, le message part une seconde fois.
      await tester.tap(find.text('Renvoyer'));
      await tester.pumpAndSettle();

      expect(
        harness.adapter.calls
            .where(
              (RequestOptions o) =>
                  o.path == kMessagesPath && o.method == 'POST',
            )
            .length,
        2,
      );
      expect(find.text('Échec de l’envoi'), findsNothing);
      expect(
        find.text('Bonjour, je serai là vers 14h.'),
        findsOneWidget,
        reason: 'la bulle livrée remplace la bulle en échec — pas de doublon',
      );

      await harness.dispose(tester);
    });

    testWidgets('« Abandonner » retire la bulle sans renvoyer', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = await pumpConversation(
        tester,
        backend: messagingBackend(sendDownOnce: true),
      );

      await tester.enterText(find.byType(TextField), 'Message abandonné');
      await tester.pump();
      await tester.tap(find.byTooltip('Envoyer'));
      await tester.pumpAndSettle();
      expect(find.text('Échec de l’envoi'), findsOneWidget);

      await tester.tap(find.text('Abandonner'));
      await tester.pumpAndSettle();

      expect(find.text('Message abandonné'), findsNothing);
      expect(
        harness.adapter.calls
            .where(
              (RequestOptions o) =>
                  o.path == kMessagesPath && o.method == 'POST',
            )
            .length,
        1,
        reason: 'abandonner n’envoie rien',
      );

      await harness.dispose(tester);
    });
  });

  group('Liste des conversations (T182)', () {
    testWidgets('interlocuteur, dernier message, non-lus par fil et pastille '
        'globale', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(messagingBackend());
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...harness.overrides,
            meControllerProvider.overrideWith(() => StubMeController(meClient)),
          ],
          child: const MaterialApp(home: ThreadsScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Kofi Plomberie'), findsNWidgets(2));
      expect(
        find.text('Bonjour, à quelle heure passez-vous ?'),
        findsOneWidget,
      );
      // Le badge du fil non lu ET la pastille globale (route dédiée).
      expect(find.text('1'), findsNWidgets(2));
      // Le fil clôturé reste listé, verrou visible — jamais masqué.
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      await harness.dispose(tester);
    });
  });
}
