// T237 — Politique de cache : durées de vie, purge, AUCUNE écriture différée.
//
// Ce que ces tests protègent :
//   • **les durées de vie** : un cache frais épargne la requête, un cache
//     périmé revalide — et l'échec de revalidation SERT le cache avec son âge
//     et sa raison, jamais une erreur bloquante ;
//   • **la purge à la déconnexion** (SC-012) : tout le cache disparaît, table
//     par table — aucune donnée du compte précédent ne survit ;
//   • **aucune mise en file** (FR-097) : une écriture refusée hors ligne est
//     refusée DÉFINITIVEMENT — le retour du réseau ne rejoue rien ;
//   • **la persistance des fichiers** (FR-098) : `public` cacheable sur
//     disque, `restricted` et `sensitive` jamais.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/cache/stale_while_revalidate.dart';
import 'package:prestgo_mobile/core/connectivity/offline_gate.dart';
import 'package:prestgo_mobile/core/files/file_cache_policy.dart';
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/widgets/data_age_label.dart';

import '../support/screen_harness.dart';

/// Portier réseau piloté par le test — aucune plateforme en jeu.
class FakeOfflineGate extends OfflineGate {
  FakeOfflineGate({required this.online});

  bool online;

  // Fermé par le test qui l'utilise.
  // ignore: close_sinks
  final StreamController<bool> changes = StreamController<bool>.broadcast();

  @override
  Future<bool> isOnline() async => online;

  @override
  Stream<bool> onlineChanges() => changes.stream;
}

ApiException networkFailure() => const ApiException(
  message: 'Connexion impossible',
  kind: ApiFailureKind.network,
);

void main() {
  setUpAll(() => initializeDateFormatting(AppFormats.locale));

  group('Durées de vie (CachedValue)', () {
    final DateTime fetchedAt = DateTime.utc(2026, 8, 1, 10);
    const Duration ttl = Duration(hours: 24);

    test('frais avant le TTL, périmé au seuil exact', () {
      final CachedValue<int> value = CachedValue<int>(
        value: 1,
        fetchedAt: fetchedAt,
      );

      expect(
        value.isStaleAt(fetchedAt.add(const Duration(hours: 23)), ttl),
        isFalse,
      );
      expect(value.isStaleAt(fetchedAt.add(ttl), ttl), isTrue);
      expect(
        value.ageAt(fetchedAt.add(const Duration(minutes: 5))),
        const Duration(minutes: 5),
      );
    });
  });

  group('Servir le cache puis revalider', () {
    test('cache frais sous TTL : AUCUNE requête ne part', () async {
      int fetches = 0;
      final DateTime now = DateTime.utc(2026, 8, 1, 12);

      final List<CacheSnapshot<String>> emitted =
          await staleWhileRevalidate<String>(
            readCache: () async => CachedValue<String>(
              value: 'en-cache',
              fetchedAt: now.subtract(const Duration(hours: 1)),
            ),
            fetch: () async {
              fetches += 1;
              return 'frais';
            },
            writeCache: (String _) async {},
            ttl: const Duration(hours: 24),
            clock: () => now,
          ).toList();

      expect(fetches, 0);
      expect(emitted.single.value, 'en-cache');
      expect(emitted.single.isFromCache, isTrue);
    });

    test('cache périmé : il est servi PUIS revalidé', () async {
      final DateTime now = DateTime.utc(2026, 8, 1, 12);

      final List<CacheSnapshot<String>> emitted =
          await staleWhileRevalidate<String>(
            readCache: () async => CachedValue<String>(
              value: 'périmé',
              fetchedAt: now.subtract(const Duration(hours: 25)),
            ),
            fetch: () async => 'frais',
            writeCache: (String _) async {},
            ttl: const Duration(hours: 24),
            clock: () => now,
          ).toList();

      expect(emitted, hasLength(2));
      expect(emitted.first.value, 'périmé');
      expect(emitted.last.value, 'frais');
      expect(emitted.last.isFromCache, isFalse);
    });

    test('réseau coupé : le cache est servi avec son âge et sa raison — pas '
        'une erreur bloquante', () async {
      final DateTime fetchedAt = DateTime.utc(2026, 8, 1, 9);

      final List<CacheSnapshot<String>> emitted =
          await staleWhileRevalidate<String>(
            readCache: () async =>
                CachedValue<String>(value: 'hors-ligne', fetchedAt: fetchedAt),
            fetch: () async => throw networkFailure(),
            writeCache: (String _) async {},
          ).toList();

      final CacheSnapshot<String> last = emitted.last;
      expect(last.value, 'hors-ligne');
      expect(last.isStale, isTrue);
      expect(last.fetchedAt, fetchedAt);
      expect(last.revalidationError?.isNetwork, isTrue);
    });

    test(
      'ni cache ni réseau : l’erreur remonte — il n’y a rien à afficher',
      () async {
        await expectLater(
          staleWhileRevalidate<String>(
            readCache: () async => null,
            fetch: () async => throw networkFailure(),
            writeCache: (String _) async {},
          ).toList(),
          throwsA(isA<ApiException>()),
        );
      },
    );
  });

  group('Purge à la déconnexion (SC-012)', () {
    test('purgeAll vide TOUTES les tables', () async {
      final LocalDatabase db = LocalDatabase.memory();
      final CacheDao dao = CacheDao(db);
      final DateTime now = DateTime.utc(2026, 8, 1, 12);

      await dao.writeProfile(
        id: 'u-1',
        payload: <String, Object?>{'id': 'u-1'},
        fetchedAt: now,
      );
      await dao.writeAddresses(<({String id, bool isDefault, JsonMap payload})>[
        (id: 'a-1', isDefault: true, payload: <String, Object?>{'id': 'a-1'}),
      ], fetchedAt: now);
      await dao.writeMissionDetail(
        id: 'm-1',
        payload: <String, Object?>{'id': 'm-1'},
        fetchedAt: now,
      );
      await dao.writeMessages(
        't-1',
        <({String id, DateTime createdAt, JsonMap payload})>[
          (
            id: 'msg-1',
            createdAt: now,
            payload: <String, Object?>{'id': 'msg-1'},
          ),
        ],
        fetchedAt: now,
      );

      await dao.purgeAll();

      expect(await dao.readProfile(), isNull);
      expect(await dao.readAddresses(), isNull);
      expect(await dao.readMissionDetail('m-1'), isNull);
      expect(await dao.readMessages('t-1'), isNull);

      await db.close();
    });

    test('signIn purge le cache avant d’ouvrir la session — un compte peut '
        'en remplacer un autre (T245)', () async {
      final LocalDatabase db = LocalDatabase.memory();
      final InMemoryTokenStore tokenStore = InMemoryTokenStore();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          localDatabaseProvider.overrideWithValue(db),
          secureTokenStoreProvider.overrideWithValue(tokenStore),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      // Données laissées par le compte précédent.
      final CacheDao dao = container.read(cacheDaoProvider);
      await dao.writeProfile(
        id: 'ancien-compte',
        payload: <String, Object?>{'id': 'ancien-compte'},
        fetchedAt: DateTime.utc(2026, 8, 1, 12),
      );

      final SessionController controller = container.read<SessionController>(
        sessionControllerProvider.notifier,
      );
      await controller.signIn(
        const AuthTokens(accessToken: 'accès', refreshToken: 'renouv'),
      );

      expect(
        await dao.readProfile(),
        isNull,
        reason: 'rien du compte précédent ne doit rester lisible (SC-012)',
      );
      expect(tokenStore.tokens?.accessToken, 'accès');
      expect(
        container.read<SessionState>(sessionControllerProvider).isAuthenticated,
        isTrue,
      );
    });
  });

  group('Aucune écriture différée (FR-097)', () {
    test(
      'hors ligne : refus définitif ; le retour du réseau ne rejoue RIEN',
      () async {
        final FakeOfflineGate gate = FakeOfflineGate(online: false);
        int executions = 0;

        await expectLater(
          gate.guardWrite<void>(() async {
            executions += 1;
          }),
          throwsA(isA<OfflineWriteBlocked>()),
        );
        expect(executions, 0);

        // Le réseau revient : rien n'a été mémorisé, rien ne part tout seul.
        gate.online = true;
        gate.changes.add(true);
        await Future<void>.delayed(Duration.zero);
        expect(executions, 0);

        // Relancée EXPLICITEMENT, l'action passe.
        await gate.guardWrite<void>(() async {
          executions += 1;
        });
        expect(executions, 1);

        await gate.changes.close();
      },
    );

    test('le message d’explication accompagne le refus', () {
      expect(
        const OfflineWriteBlocked().message,
        'Action indisponible hors ligne. Reconnectez-vous au réseau pour '
        'continuer.',
      );
    });
  });

  group('Persistance des fichiers (FR-098)', () {
    test('public cacheable sur disque, restricted et sensitive JAMAIS', () {
      expect(FileCachePolicy.mayPersistOnDisk(FileVisibility.public), isTrue);
      expect(
        FileCachePolicy.mayPersistOnDisk(FileVisibility.restricted),
        isFalse,
      );
      expect(
        FileCachePolicy.mayPersistOnDisk(FileVisibility.sensitive),
        isFalse,
      );
    });

    test('la lecture protégée exige un jeton', () {
      expect(
        FileCachePolicy.requiresAccessToken(FileVisibility.public),
        isFalse,
      );
      expect(
        FileCachePolicy.requiresAccessToken(FileVisibility.sensitive),
        isTrue,
      );
    });
  });

  group('Âge des données (FR-096)', () {
    test('l’imprécision croît avec l’âge', () {
      final DateTime now = DateTime(2026, 8, 1, 12);

      expect(
        dataAgeLabel(now.subtract(const Duration(seconds: 30)), now: now),
        'Mis à jour à l’instant',
      );
      expect(
        dataAgeLabel(now.subtract(const Duration(minutes: 12)), now: now),
        'Mis à jour il y a 12 min',
      );
      expect(
        dataAgeLabel(now.subtract(const Duration(hours: 3)), now: now),
        'Mis à jour il y a 3 h',
      );
      expect(
        dataAgeLabel(now.subtract(const Duration(days: 2)), now: now),
        startsWith('Mis à jour le '),
      );
    });
  });
}
