// Montage d'un écran sous test, avec un service simulé.
//
// Trois providers du socle sont remplacés, et seulement ceux-là :
//   • `apiClientProvider`     — branché sur `RecordingAdapter` ;
//   • `localDatabaseProvider` — base en mémoire, rien n'atteint le disque ;
//   • `secureTokenStoreProvider` — les canaux de plateforme n'existent pas dans un
//     test de widget ; un stockage en mémoire évite d'avoir à les simuler.
//
// Tout le reste — dépôts, contrôleurs, gardien — est le code réel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/connectivity/offline_gate.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';

import 'api_harness.dart';
import 'recording_adapter.dart';

/// Stockage de session en mémoire.
///
/// Étend le vrai magasin plutôt que de l'imiter : les invariants qui comptent — refus
/// d'une écriture partielle, purge complète — restent ceux du code de production.
class InMemoryTokenStore extends SecureTokenStore {
  InMemoryTokenStore();

  AuthTokens? tokens;
  String? deviceToken;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async {
    if (!value.isComplete) {
      throw ArgumentError.value(value, 'tokens', 'Les deux jetons sont requis');
    }
    tokens = value;
  }

  @override
  Future<void> clearTokens() async => tokens = null;

  @override
  Future<String?> readDeviceToken() async => deviceToken;

  @override
  Future<void> writeDeviceToken(String token) async => deviceToken = token;

  @override
  Future<void> clearDeviceToken() async => deviceToken = null;
}

/// Portier réseau muet — toujours en ligne, aucun canal de plateforme.
///
/// Le greffon de connectivité n'existe pas dans un test : le laisser
/// s'activer lèverait une `MissingPluginException` dans chaque test qui
/// affiche la bannière hors ligne ou un verrou d'écriture (US10).
class StubOfflineGate extends OfflineGate {
  StubOfflineGate();

  @override
  Future<bool> isOnline() async => true;

  @override
  Stream<bool> onlineChanges() => const Stream<bool>.empty();
}

class ScreenHarness {
  ScreenHarness(AdapterScenario respond)
    : api = ApiHarness(respond),
      database = LocalDatabase.memory(),
      tokenStore = InMemoryTokenStore();

  final ApiHarness api;
  final LocalDatabase database;
  final InMemoryTokenStore tokenStore;

  RecordingAdapter get adapter => api.adapter;

  List<Override> get overrides => <Override>[
    apiClientProvider.overrideWithValue(api.client),
    localDatabaseProvider.overrideWithValue(database),
    secureTokenStoreProvider.overrideWithValue(tokenStore),
    offlineGateProvider.overrideWithValue(StubOfflineGate()),
  ];

  /// Monte [screen] dans un `MaterialApp` minimal.
  ///
  /// Pas de `GoRouter` : les écrans testés ici ne naviguent qu'après un succès, et
  /// les cas vérifiés sont ceux où la navigation n'a pas lieu.
  Future<void> pump(WidgetTester tester, Widget screen) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pump();
  }

  /// Démonte l'écran et libère ses minuteries.
  ///
  /// Les comptes à rebours (débit, renvoi de code, expiration) tournent à la
  /// seconde : sans démontage explicite, le test échouerait sur une minuterie encore
  /// active.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await database.close();
  }
}

/// Réponse unique, quel que soit l'appel.
AdapterScenario always(int status, Object? body) =>
    (dynamic options, int index) => (status, body);
