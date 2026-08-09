// T205 — Parcours US7 de bout en bout : scénarios 7.1 à 7.5 de quickstart.md.
//
// Aucun fournisseur d'envoi n'existe sur l'environnement de développement
// (contracts/push-payloads.md §6) : le transport et la bannière sont **simulés**
// — deux fausses implémentations des interfaces du socle — et les charges
// utiles s'injectent dans leurs flux. Tout le reste est le code livré : pilote
// push, routeur de notification, cycle de vie du jeton, chaîne d'intercepteurs,
// dépôts, gardien, écrans.
//
// Comme pour US1 à US6, les scénarios sont exposés par [runUs7Scenarios] et
// déroulés par deux points d'entrée : sur appareil (`integration_test/`) et
// sans appareil (`test/flows/`) — le seul que l'intégration continue exécute.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/app/router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/push/foreground_presenter.dart';
import 'package:prestgo_mobile/core/push/push_service.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/features/auth/presentation/logout_controller.dart';
import 'package:prestgo_mobile/features/messaging/presentation/conversation_screen.dart';
import 'package:prestgo_mobile/features/notifications/presentation/notifications_screen.dart';

import '../../test/support/fixtures.dart';
import '../../test/support/recording_adapter.dart';
import '../../test/support/screen_harness.dart';
import '../support/app_harness.dart';

const String kMissionId = 'b86332d9-14a0-4ec8-b5d0-d0158ae1824d';
const String kThreadId = 't-1';
const String kDeviceToken = 'jeton-fcm-0123456789abcdef';
const String kMessagesPath = '/messages/threads/$kThreadId/messages';

/// Charge utile `chat`, telle qu'un push la livre : des **chaînes** (FCM).
const Map<String, Object?> kChatPayload = <String, String>{
  'type': 'chat',
  'missionId': kMissionId,
  'threadId': kThreadId,
};

/// Transport simulé — les charges utiles s'injectent dans ses flux.
class FakePushMessenger implements PushMessenger {
  bool permissionGranted = true;
  String? token = kDeviceToken;
  PushMessage? initial;

  final StreamController<String> tokens = StreamController<String>.broadcast();
  final StreamController<PushMessage> foreground =
      StreamController<PushMessage>.broadcast();
  final StreamController<PushMessage> opened =
      StreamController<PushMessage>.broadcast();

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  Future<String?> currentToken() async => token;

  @override
  Stream<String> get tokenChanges => tokens.stream;

  @override
  Stream<PushMessage> get foregroundMessages => foreground.stream;

  @override
  Stream<PushMessage> get openedMessages => opened.stream;

  @override
  Future<PushMessage?> initialMessage() async => initial;

  Future<void> dispose() async {
    await tokens.close();
    await foreground.close();
    await opened.close();
  }
}

/// Bannière simulée : elle enregistre au lieu d'afficher.
class RecordingPresenter implements ForegroundPresenter {
  final List<PushMessage> shown = <PushMessage>[];
  void Function(Map<String, Object?> data)? onSelect;

  @override
  Future<void> initialize({
    required void Function(Map<String, Object?> data) onSelect,
  }) async {
    this.onSelect = onSelect;
  }

  @override
  Future<void> show(PushMessage message) async => shown.add(message);
}

/// Service simulé — il tient le registre des appareils par compte (7.4).
class NotificationsFlowBackend {
  /// Compte « propriétaire » des enregistrements à venir.
  String currentOwner = 'compte-A';

  /// Jeton → compte, comme le ferait l'upsert du service.
  final Map<String, String> tokenOwners = <String, String>{};

  AdapterResponse handle(RequestOptions options, int index) {
    final String path = options.path;

    if (path == '/me') {
      return fixture('auth/me', 'client');
    }
    if (path == '/auth/logout') {
      return envelope(null, message: 'Déconnecté');
    }
    if (path == '/me/devices' && options.method == 'POST') {
      final Object? body = options.data;
      final String token = body is Map<Object?, Object?>
          ? body['token']?.toString() ?? ''
          : '';
      // L'upsert du service : le jeton change simplement de propriétaire.
      tokenOwners[token] = currentOwner;
      return fixture('notifications/devices', 'registered');
    }
    if (path.startsWith('/me/devices/') && options.method == 'DELETE') {
      return fixture('notifications/devices', 'unregistered');
    }
    if (path == '/me/notifications') {
      return fixture('notifications/notifications', 'empty');
    }
    if (path == '/me/notifications/unread-count') {
      return fixture('notifications/unread_count', 'zero');
    }
    if (path == '/me/threads') {
      return (
        200,
        <String, Object?>{
          'success': true,
          'message': 'OK',
          'data': <Object?>[_threadPayload()],
          'meta': <String, Object?>{'page': 1, 'limit': 20, 'total': 1},
        },
      );
    }
    if (path == '/me/threads/unread-count') {
      return envelope(<String, Object?>{'unread': 1});
    }
    if (path == '/missions/$kMissionId/thread') {
      return envelope(<String, Object?>{
        'id': kThreadId,
        'missionId': kMissionId,
        'status': 'open',
        'messageCount': 3,
        'createdAt': '2026-07-20T08:01:00.000Z',
      });
    }
    if (path == '/messages/threads/$kThreadId/read') {
      return envelope(<String, Object?>{'updated': 1});
    }
    if (path == kMessagesPath) {
      final bool newestFirst =
          options.uri.queryParameters['sort'] == '-createdAt';
      final List<JsonMap> ordered = newestFirst
          ? _messages.reversed.toList()
          : _messages;
      return (
        200,
        <String, Object?>{
          'success': true,
          'message': 'OK',
          'data': ordered,
          'meta': <String, Object?>{
            'page': 1,
            'limit': 20,
            'total': _messages.length,
          },
        },
      );
    }
    return (
      404,
      <String, Object?>{
        'success': false,
        'message': 'Route non simulée : $path',
      },
    );
  }

  static final List<JsonMap> _messages = <JsonMap>[
    for (int i = 1; i <= 3; i++)
      <String, Object?>{
        'id': 'm-$i',
        'senderId': i.isEven
            ? 'c4f8a2e1-9d3b-4e5a-8f6c-1a2b3c4d5e6f'
            : '71e88780-d204-4145-b06d-b9e3acdbb365',
        'message': 'Message n°$i',
        'createdAt': '2026-07-20T08:0$i:00.000Z',
        'readAt': i == 3 ? null : '2026-07-20T08:0$i:30.000Z',
        'files': const <Object?>[],
      },
  ];

  JsonMap _threadPayload() => <String, Object?>{
    'id': kThreadId,
    'missionId': kMissionId,
    'missionStatus': 'confirmed',
    'scheduledAt': '2026-08-03T14:00:00.000Z',
    'status': 'open',
    'counterpartName': 'Kofi Plomberie',
    'counterpartAvatarFileId': null,
    'lastMessage': <String, Object?>{
      'id': 'm-3',
      'message': 'Message n°3',
      'senderId': '71e88780-d204-4145-b06d-b9e3acdbb365',
      'createdAt': '2026-07-20T08:03:00.000Z',
    },
    'unreadCount': 1,
    'createdAt': '2026-07-20T08:01:00.000Z',
  };
}

/// Déroule les scénarios 7.1 à 7.5.
void runUs7Scenarios() {
  late NotificationsFlowBackend backend;
  late RecordingAdapter adapter;
  late LocalDatabase database;
  late InMemoryTokenStore tokenStore;
  late FakePushMessenger messenger;
  late RecordingPresenter presenter;
  late ProviderContainer container;

  setUp(() {
    backend = NotificationsFlowBackend();
    adapter = RecordingAdapter(backend.handle);
    database = LocalDatabase.memory();
    tokenStore = InMemoryTokenStore();
    messenger = FakePushMessenger();
    presenter = RecordingPresenter();
    container = buildAppContainer(
      adapter: adapter,
      database: database,
      tokenStore: tokenStore,
      extraOverrides: <Override>[
        pushMessengerProvider.overrideWithValue(messenger),
        foregroundPresenterProvider.overrideWithValue(presenter),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await messenger.dispose();
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

  List<RequestOptions> deviceRegistrations() => adapter
      .callsToPath('/me/devices')
      .where((RequestOptions o) => o.method == 'POST')
      .toList();

  // --- 7.1 — Refuser l'autorisation ne bloque rien ------------------------------

  testWidgets('7.1 — autorisation refusée : aucun enregistrement, tous les '
      'parcours disponibles', (WidgetTester tester) async {
    messenger.permissionGranted = false;
    signIn();
    await start(tester, at: Routes.threads);

    // Rien n'est parti au service — et rien n'a bloqué le démarrage.
    expect(deviceRegistrations(), isEmpty);
    expect(find.text('Kofi Plomberie'), findsOneWidget);

    // Le centre de notifications reste le canal de référence.
    unawaited(
      container.read(goRouterProvider).push<Object?>(Routes.notifications),
    );
    await tester.pumpAndSettle();
    expect(find.text('Aucune notification'), findsOneWidget);
  });

  // --- 7.2 — La charge `chat` dans les trois états de l'application -------------

  testWidgets('7.2 — premier plan : bannière et compteurs, JAMAIS de '
      'navigation forcée', (WidgetTester tester) async {
    signIn();
    await start(tester, at: Routes.threads);
    final int badgeCallsBefore = adapter.countFor('/me/threads/unread-count');

    messenger.foreground.add(
      const PushMessage(
        title: 'Nouveau message',
        body: 'Kofi Plomberie : Message n°3',
        data: kChatPayload,
      ),
    );
    await tester.pumpAndSettle();

    expect(presenter.shown, hasLength(1), reason: 'bannière interne affichée');
    expect(
      find.byType(ConversationScreen),
      findsNothing,
      reason: 'au premier plan, un push ne navigue jamais de force',
    );
    expect(
      adapter.countFor('/me/threads/unread-count'),
      greaterThan(badgeCallsBefore),
      reason: 'les compteurs se rafraîchissent à la réception (FR-082)',
    );
  });

  testWidgets('7.2 — arrière-plan : le tap route immédiatement vers la '
      'conversation', (WidgetTester tester) async {
    signIn();
    await start(tester, at: Routes.threads);

    messenger.opened.add(const PushMessage(data: kChatPayload));
    await tester.pumpAndSettle();

    expect(find.byType(ConversationScreen), findsOneWidget);
    expect(find.text('Message n°3'), findsOneWidget);
  });

  testWidgets('7.2 — application tuée : le message initial route APRÈS '
      'l’aiguillage', (WidgetTester tester) async {
    // La notification existe AVANT le premier rendu : c'est elle qui ouvre
    // l'application. La destination attend la restauration de session.
    messenger.initial = const PushMessage(data: kChatPayload);
    signIn();
    await start(tester);

    expect(find.byType(ConversationScreen), findsOneWidget);
    expect(find.text('Message n°3'), findsOneWidget);
  });

  // --- 7.3 — Type inconnu : le centre, jamais un plantage ------------------------

  testWidgets('7.3 — un type inconnu ouvre le centre de notifications', (
    WidgetTester tester,
  ) async {
    signIn();
    await start(tester, at: Routes.threads);

    messenger.opened.add(
      const PushMessage(data: <String, Object?>{'type': 'promo.summer'}),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsScreen), findsOneWidget);
  });

  // --- 7.4 — Second compte sur le même appareil ----------------------------------

  testWidgets('7.4 — l’appareil est réaffecté au second compte : '
      'enregistrement à CHAQUE connexion', (WidgetTester tester) async {
    signIn();
    await start(tester, at: Routes.threads);

    expect(deviceRegistrations(), hasLength(1));
    expect(backend.tokenOwners[kDeviceToken], 'compte-A');

    // Déconnexion, puis connexion d'un second compte sur le même appareil.
    await tester.runAsync(
      () => container.read(logoutControllerProvider).signOut(),
    );
    await tester.pumpAndSettle();

    backend.currentOwner = 'compte-B';
    signIn();
    // Pas de `runAsync` ici : l'enregistrement déclenché par la transition de
    // session doit se dérouler sous l'horloge simulée, que `pumpAndSettle`
    // draine — une zone réelle le laisserait inachevé.
    unawaited(
      container
          .read(sessionControllerProvider.notifier)
          .signIn(
            const AuthTokens(
              accessToken: 'access-b',
              refreshToken: 'refresh-b',
            ),
          ),
    );
    await tester.pumpAndSettle();

    expect(
      deviceRegistrations(),
      hasLength(2),
      reason:
          'le jeton identifie une installation, pas un compte : il part '
          'à chaque connexion',
    );
    expect(
      backend.tokenOwners[kDeviceToken],
      'compte-B',
      reason: 'réaffecté — l’ancien compte ne reçoit plus rien (7.4)',
    );
  });

  // --- 7.5 — Désenregistrement AVANT la fermeture de session ---------------------

  testWidgets('7.5 — à la déconnexion, l’appareil part avant la session', (
    WidgetTester tester,
  ) async {
    signIn();
    await start(tester, at: Routes.threads);
    expect(
      tokenStore.deviceToken,
      kDeviceToken,
      reason: 'le jeton est mémorisé localement après l’enregistrement',
    );

    await tester.runAsync(
      () => container.read(logoutControllerProvider).signOut(),
    );
    await tester.pumpAndSettle();

    final List<String> journal = adapter.calls
        .map((RequestOptions o) => '${o.method} ${o.path}')
        .toList();
    final int unregisterIndex = journal.indexWhere(
      (String call) => call.startsWith('DELETE /me/devices/'),
    );
    final int logoutIndex = journal.indexOf('POST /auth/logout');

    expect(unregisterIndex, isNonNegative);
    expect(
      logoutIndex,
      greaterThan(unregisterIndex),
      reason:
          'la route de désenregistrement exige un jeton encore valide : '
          'elle part IMPÉRATIVEMENT avant la fermeture de session (7.5)',
    );
    expect(tokenStore.deviceToken, isNull, reason: 'mémoire locale purgée');
  });
}
