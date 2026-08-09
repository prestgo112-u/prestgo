// Bannière interne au premier plan (T202, contracts/push-payloads.md §3).
//
// Au premier plan, un push ne navigue jamais de force : il s'affiche en bannière
// locale (notification système sur Android via `flutter_local_notifications`).
// Le **tap** sur la bannière, lui, passe par la même fonction de routage que tout
// le reste (FR-083) — la charge utile voyage dans le `payload` de la notification
// locale, encodée en JSON.
//
// Comme le transport, l'affichage est **au mieux** : greffon absent (tests,
// environnement sans plateforme), initialisation refusée — l'application
// continue, les compteurs se rafraîchissent quand même.

import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/push/push_service.dart';

abstract interface class ForegroundPresenter {
  /// Prépare l'affichage ; [onSelect] reçoit la charge utile au tap.
  Future<void> initialize({
    required void Function(Map<String, Object?> data) onSelect,
  });

  /// Affiche [message] en bannière, sans naviguer.
  Future<void> show(PushMessage message);
}

class LocalNotificationsForegroundPresenter implements ForegroundPresenter {
  LocalNotificationsForegroundPresenter();

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
        'prestgo_messages',
        'Notifications PRESTGO',
        channelDescription:
            'Missions, messages, reports et avis reçus pendant l’utilisation.',
        importance: Importance.high,
        priority: Priority.high,
      );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  int _sequence = 0;

  @override
  Future<void> initialize({
    required void Function(Map<String, Object?> data) onSelect,
  }) async {
    try {
      final bool? initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            // Les autorisations sont demandées par le transport, après la
            // connexion (T199) — jamais ici, au premier lancement.
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final Map<String, Object?> data = _decodePayload(response.payload);
          onSelect(data);
        },
      );
      _ready = initialized ?? false;
    } on Object {
      _ready = false;
    }
  }

  @override
  Future<void> show(PushMessage message) async {
    if (!_ready) {
      return;
    }
    try {
      await _plugin.show(
        id: _sequence++,
        title: message.title ?? 'PRESTGO',
        body: message.body,
        notificationDetails: const NotificationDetails(
          android: _androidDetails,
        ),
        payload: jsonEncode(message.data),
      );
    } on Object {
      // Bannière au mieux : son absence ne casse ni compteurs ni routage.
    }
  }

  static Map<String, Object?> _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      return const <String, Object?>{};
    }
    try {
      final Object? decoded = jsonDecode(payload);
      return decoded is Map<Object?, Object?>
          ? decoded.cast<String, Object?>()
          : const <String, Object?>{};
    } on FormatException {
      return const <String, Object?>{};
    }
  }
}

final Provider<ForegroundPresenter> foregroundPresenterProvider =
    Provider<ForegroundPresenter>(
      (Ref ref) => LocalNotificationsForegroundPresenter(),
    );
