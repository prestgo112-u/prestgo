// Notifications poussées : initialisation, autorisation, cycle de vie du jeton
// (T199, T200, FR-084, FR-085).
//
// Trois décisions structurantes :
//
//   • **l'autorisation se demande APRÈS la connexion** — jamais au premier
//     lancement : une demande sans contexte est refusée, et un refus ne bloque
//     aucun parcours (FR-085), le centre de notifications restant le canal de
//     référence ;
//   • **le jeton identifie une installation, pas un compte** : l'enregistrement a
//     lieu à CHAQUE connexion — le service réaffecte le jeton au nouveau compte,
//     ce qui coupe les notifications de l'ancien (téléphone prêté, scénario 7.4) ;
//   • **tout est au mieux** : Firebase absent (environnement de test, saveur sans
//     identifiants d'envoi), réseau coupé, permission refusée — aucun de ces cas
//     ne remonte à l'utilisateur ni ne bloque une connexion ou une déconnexion.
//
// Le socle ne connaît pas le dépôt des appareils (`features/notifications/data`) :
// il déclare [DeviceRegistrar], que le dépôt implémente — l'assemblage se fait
// dans la couche applicative (`lib/app/push_driver.dart`).

import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';

/// Message poussé, réduit à ce que l'application consomme.
class PushMessage {
  const PushMessage({
    this.title,
    this.body,
    this.data = const <String, Object?>{},
  });

  final String? title;
  final String? body;

  /// Charge utile de routage — la même qu'une notification interne (FR-083).
  final Map<String, Object?> data;
}

/// Frontière du transport de push (Firebase en production).
///
/// Derrière une interface pour la même raison que les sélecteurs de fichier :
/// les greffons n'existent ni en test de widget ni dans les parcours sans
/// appareil, et les charges utiles s'y injectent simulées (T205).
abstract interface class PushMessenger {
  /// Demande l'autorisation ; vrai si les notifications peuvent être affichées.
  Future<bool> requestPermission();

  /// Jeton d'appareil courant, ou `null` si indisponible.
  Future<String?> currentToken();

  /// Rotations du jeton décidées par le transport.
  Stream<String> get tokenChanges;

  /// Messages reçus l'application au premier plan.
  Stream<PushMessage> get foregroundMessages;

  /// Notification touchée, application en arrière-plan.
  Stream<PushMessage> get openedMessages;

  /// Notification qui a ouvert l'application tuée, s'il y en a une.
  Future<PushMessage?> initialMessage();
}

/// Enregistrement des appareils auprès du service (opérations 59 et 60).
///
/// Implémenté par `DeviceRepository` (`features/notifications/data`) ; le socle
/// n'en connaît que ce contrat.
abstract interface class DeviceRegistrar {
  Future<void> register({required String platform, required String token});

  /// Idempotent et tolérant : jamais d'erreur métier.
  Future<void> unregister(String token);
}

/// Transport Firebase réel.
///
/// Toute l'initialisation est **paresseuse et au mieux** : sans configuration
/// Firebase (tests, poste de développement, saveur sans identifiants), chaque
/// méthode devient un non-évènement — l'application vit sans push (FR-085).
class FirebasePushMessenger implements PushMessenger {
  FirebasePushMessenger();

  Future<bool>? _ready;

  Future<bool> _ensureReady() => _ready ??= _initialize();

  Future<bool> _initialize() async {
    try {
      await Firebase.initializeApp();
      return true;
    } on Object {
      // Configuration absente : le push est un complément, jamais un préalable.
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!await _ensureReady()) {
      return false;
    }
    try {
      final NotificationSettings settings = await FirebaseMessaging.instance
          .requestPermission();
      return settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
    } on Object {
      return false;
    }
  }

  @override
  Future<String?> currentToken() async {
    if (!await _ensureReady()) {
      return null;
    }
    try {
      return await FirebaseMessaging.instance.getToken();
    } on Object {
      return null;
    }
  }

  @override
  Stream<String> get tokenChanges async* {
    if (!await _ensureReady()) {
      return;
    }
    yield* FirebaseMessaging.instance.onTokenRefresh;
  }

  @override
  Stream<PushMessage> get foregroundMessages async* {
    if (!await _ensureReady()) {
      return;
    }
    yield* FirebaseMessaging.onMessage.map(_convert);
  }

  @override
  Stream<PushMessage> get openedMessages async* {
    if (!await _ensureReady()) {
      return;
    }
    yield* FirebaseMessaging.onMessageOpenedApp.map(_convert);
  }

  @override
  Future<PushMessage?> initialMessage() async {
    if (!await _ensureReady()) {
      return null;
    }
    try {
      final RemoteMessage? message = await FirebaseMessaging.instance
          .getInitialMessage();
      return message == null ? null : _convert(message);
    } on Object {
      return null;
    }
  }

  static PushMessage _convert(RemoteMessage message) => PushMessage(
    title: message.notification?.title,
    body: message.notification?.body,
    data: Map<String, Object?>.from(message.data),
  );
}

/// Transport de production.
final Provider<PushMessenger> pushMessengerProvider = Provider<PushMessenger>(
  (Ref ref) => FirebasePushMessenger(),
);

/// Cycle de vie du jeton d'appareil (T200, contracts/push-payloads.md §4).
class PushService {
  const PushService({
    required PushMessenger messenger,
    required DeviceRegistrar registrar,
    required SecureTokenStore tokenStore,
  }) : _messenger = messenger,
       _registrar = registrar,
       _tokenStore = tokenStore;

  final PushMessenger _messenger;
  final DeviceRegistrar _registrar;
  final SecureTokenStore _tokenStore;

  /// Plateforme déclarée au service — `web` n'est pas visé en V1.
  static String get platformName {
    try {
      return Platform.isIOS ? 'ios' : 'android';
    } on Object {
      return 'android';
    }
  }

  /// Après chaque connexion réussie — et au démarrage sur session restaurée.
  ///
  /// L'enregistrement est idempotent côté service (upsert sur le jeton) : le
  /// ré-enregistrement au démarrage coûte un appel et garantit la réaffectation
  /// après réinstallation ou changement de compte (scénario 7.4).
  Future<void> registerForCurrentSession() async {
    if (!await _messenger.requestPermission()) {
      // Refusé : aucun parcours n'est bloqué (FR-085, scénario 7.1) —
      // le rappel vit dans les réglages, pas ici.
      return;
    }
    final String? token = await _messenger.currentToken();
    if (token == null) {
      return;
    }
    try {
      await _registrar.register(platform: platformName, token: token);
    } on ApiException {
      // Au mieux : hors ligne ou débit atteint (30/jour) — le prochain
      // démarrage réessaiera.
      return;
    }
    await _tokenStore.writeDeviceToken(token);
  }

  /// Rotation décidée par le transport : l'ancien jeton part, le nouveau arrive.
  Future<void> rotateToken(String newToken) async {
    final String? previous = await _tokenStore.readDeviceToken();
    if (previous != null && previous != newToken) {
      try {
        await _registrar.unregister(previous);
      } on ApiException {
        // L'ancien jeton est de toute façon invalide côté fournisseur.
      }
    }
    try {
      await _registrar.register(platform: platformName, token: newToken);
    } on ApiException {
      return;
    }
    await _tokenStore.writeDeviceToken(newToken);
  }

  /// **Avant** la déconnexion — la route exige une session valide.
  ///
  /// Sans ce désenregistrement, l'appareil continuerait de recevoir les
  /// notifications du compte quitté (scénario 7.5). L'échec réseau n'empêche
  /// jamais la déconnexion ; la mémoire locale est purgée dans tous les cas.
  Future<void> unregisterBeforeLogout() async {
    final String? token = await _tokenStore.readDeviceToken();
    if (token == null) {
      return;
    }
    try {
      await _registrar.unregister(token);
    } on ApiException {
      // Au mieux — ne jamais retenir l'utilisateur sur un compte qu'il quitte.
    }
    await _tokenStore.clearDeviceToken();
  }
}
