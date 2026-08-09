// Accès au cache de lecture : écriture, lecture, invalidation par entité et purge
// globale (T028, data-model §12).
//
// Le contenu applicatif circule ici sous forme de `JsonMap` : le cache reste ainsi
// insensible à l'évolution des modèles, et chaque dépôt reste seul responsable de
// désérialiser ce qui le concerne.

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';

/// Rôle sous lequel une liste de missions a été mise en cache.
///
/// Les deux surfaces ont des tris par défaut opposés : elles ne partagent pas leur
/// cache, même pour un compte à double casquette.
enum MissionCacheRole { client, provider }

/// Valeur mise en cache, avec la date à laquelle elle a été obtenue.
class CachedValue<T> {
  const CachedValue({required this.value, required this.fetchedAt});

  final T value;
  final DateTime fetchedAt;

  /// Âge de la donnée — alimente « Mis à jour il y a N min » (FR-096).
  Duration ageAt(DateTime now) => now.difference(fetchedAt);

  /// Vrai au-delà de [ttl].
  bool isStaleAt(DateTime now, Duration ttl) => ageAt(now) >= ttl;

  CachedValue<R> map<R>(R Function(T value) transform) =>
      CachedValue<R>(value: transform(value), fetchedAt: fetchedAt);

  @override
  String toString() => 'CachedValue($value, $fetchedAt)';
}

/// Durées de vie des entités quasi statiques.
abstract final class CacheTtl {
  /// Catalogue et zones : quasi statiques (data-model §12).
  static const Duration catalog = Duration(hours: 24);
}

class CacheDao {
  const CacheDao(this._db);

  final LocalDatabase _db;

  // --- Profil -------------------------------------------------------------------

  Future<CachedValue<JsonMap>?> readProfile() async {
    final CachedProfileRow? row = await _db
        .select(_db.cachedProfiles)
        .getSingleOrNull();
    return row == null
        ? null
        : CachedValue<JsonMap>(
            value: _decodeObject(row.payload),
            fetchedAt: row.fetchedAt,
          );
  }

  /// Remplace le profil en cache.
  ///
  /// La table ne contient qu'une ligne : écrire un profil efface le précédent, ce
  /// qui évite qu'un changement de compte laisse deux identités en base.
  Future<void> writeProfile({
    required String id,
    required JsonMap payload,
    required DateTime fetchedAt,
  }) => _db.transaction(() async {
    await _db.delete(_db.cachedProfiles).go();
    await _db
        .into(_db.cachedProfiles)
        .insert(
          CachedProfilesCompanion.insert(
            id: id,
            payload: jsonEncode(payload),
            fetchedAt: fetchedAt,
          ),
        );
  });

  Future<void> invalidateProfile() => _db.delete(_db.cachedProfiles).go();

  // --- Catalogue et zones -------------------------------------------------------

  Future<CachedValue<List<JsonMap>>?> readCatalog() async {
    final List<CachedCatalogRow> rows =
        await (_db.select(_db.cachedCatalog)
              ..orderBy(<OrderClauseGenerator<$CachedCatalogTable>>[
                ($CachedCatalogTable t) => OrderingTerm.asc(t.displayOrder),
              ]))
            .get();
    return _collect(
      rows.map((CachedCatalogRow row) => (row.payload, row.fetchedAt)),
    );
  }

  Future<void> writeCatalog(
    List<({String id, int displayOrder, JsonMap payload})> entries, {
    required DateTime fetchedAt,
  }) => _db.transaction(() async {
    await _db.delete(_db.cachedCatalog).go();
    await _db.batch((Batch batch) {
      batch.insertAll(
        _db.cachedCatalog,
        entries.map(
          (({String id, int displayOrder, JsonMap payload}) e) =>
              CachedCatalogCompanion.insert(
                id: e.id,
                displayOrder: Value<int>(e.displayOrder),
                payload: jsonEncode(e.payload),
                fetchedAt: fetchedAt,
              ),
        ),
      );
    });
  });

  Future<void> invalidateCatalog() => _db.delete(_db.cachedCatalog).go();

  Future<CachedValue<List<JsonMap>>?> readZones() async {
    final List<CachedZoneRow> rows =
        await (_db.select(_db.cachedZones)
              ..orderBy(<OrderClauseGenerator<$CachedZonesTable>>[
                ($CachedZonesTable t) => OrderingTerm.asc(t.name),
              ]))
            .get();
    return _collect(
      rows.map((CachedZoneRow row) => (row.payload, row.fetchedAt)),
    );
  }

  Future<void> writeZones(
    List<({String id, String name, JsonMap payload})> entries, {
    required DateTime fetchedAt,
  }) => _db.transaction(() async {
    await _db.delete(_db.cachedZones).go();
    await _db.batch((Batch batch) {
      batch.insertAll(
        _db.cachedZones,
        entries.map(
          (({String id, String name, JsonMap payload}) e) =>
              CachedZonesCompanion.insert(
                id: e.id,
                name: e.name,
                payload: jsonEncode(e.payload),
                fetchedAt: fetchedAt,
              ),
        ),
      );
    });
  });

  Future<void> invalidateZones() => _db.delete(_db.cachedZones).go();

  // --- Carnet d'adresses --------------------------------------------------------

  Future<CachedValue<List<JsonMap>>?> readAddresses() async {
    final List<CachedAddressRow> rows =
        await (_db.select(_db.cachedAddresses)
              // L'adresse par défaut en tête, comme le service la renvoie.
              ..orderBy(<OrderClauseGenerator<$CachedAddressesTable>>[
                ($CachedAddressesTable t) => OrderingTerm.desc(t.isDefault),
              ]))
            .get();
    return _collect(
      rows.map((CachedAddressRow row) => (row.payload, row.fetchedAt)),
    );
  }

  Future<void> writeAddresses(
    List<({String id, bool isDefault, JsonMap payload})> entries, {
    required DateTime fetchedAt,
  }) => _db.transaction(() async {
    await _db.delete(_db.cachedAddresses).go();
    await _db.batch((Batch batch) {
      batch.insertAll(
        _db.cachedAddresses,
        entries.map(
          (({String id, bool isDefault, JsonMap payload}) e) =>
              CachedAddressesCompanion.insert(
                id: e.id,
                isDefault: Value<bool>(e.isDefault),
                payload: jsonEncode(e.payload),
                fetchedAt: fetchedAt,
              ),
        ),
      );
    });
  });

  Future<void> invalidateAddresses() => _db.delete(_db.cachedAddresses).go();

  // --- Missions -----------------------------------------------------------------

  /// Première page des missions du rôle demandé.
  ///
  /// L'ordre suit le tri par défaut du service : décroissant côté client,
  /// **croissant** côté prestataire (FR-038). Il n'est jamais recalculé ailleurs.
  Future<CachedValue<List<JsonMap>>?> readMissions(
    MissionCacheRole role,
  ) async {
    final bool ascending = role == MissionCacheRole.provider;
    final List<CachedMissionRow> rows =
        await (_db.select(_db.cachedMissions)
              ..where(($CachedMissionsTable t) => t.role.equals(role.name))
              ..orderBy(<OrderClauseGenerator<$CachedMissionsTable>>[
                ($CachedMissionsTable t) => ascending
                    ? OrderingTerm.asc(t.scheduledAt)
                    : OrderingTerm.desc(t.scheduledAt),
              ]))
            .get();
    return _collect(
      rows.map((CachedMissionRow row) => (row.payload, row.fetchedAt)),
    );
  }

  Future<void> writeMissions(
    MissionCacheRole role,
    List<({String id, String status, DateTime scheduledAt, JsonMap payload})>
    entries, {
    required DateTime fetchedAt,
  }) => _db.transaction(() async {
    await (_db.delete(
      _db.cachedMissions,
    )..where(($CachedMissionsTable t) => t.role.equals(role.name))).go();
    await _db.batch((Batch batch) {
      batch.insertAll(
        _db.cachedMissions,
        entries.map(
          (
            ({String id, String status, DateTime scheduledAt, JsonMap payload})
            e,
          ) => CachedMissionsCompanion.insert(
            id: e.id,
            role: role.name,
            status: e.status,
            scheduledAt: e.scheduledAt,
            payload: jsonEncode(e.payload),
            fetchedAt: fetchedAt,
          ),
        ),
      );
    });
  });

  Future<void> invalidateMissions([MissionCacheRole? role]) {
    if (role == null) {
      return _db.delete(_db.cachedMissions).go();
    }
    return (_db.delete(
      _db.cachedMissions,
    )..where(($CachedMissionsTable t) => t.role.equals(role.name))).go();
  }

  Future<CachedValue<JsonMap>?> readMissionDetail(String id) async {
    final CachedMissionDetailRow? row =
        await (_db.select(_db.cachedMissionDetails)
              ..where(($CachedMissionDetailsTable t) => t.id.equals(id)))
            .getSingleOrNull();
    return row == null
        ? null
        : CachedValue<JsonMap>(
            value: _decodeObject(row.payload),
            fetchedAt: row.fetchedAt,
          );
  }

  Future<void> writeMissionDetail({
    required String id,
    required JsonMap payload,
    required DateTime fetchedAt,
  }) => _db
      .into(_db.cachedMissionDetails)
      .insertOnConflictUpdate(
        CachedMissionDetailsCompanion.insert(
          id: id,
          payload: jsonEncode(payload),
          fetchedAt: fetchedAt,
        ),
      );

  /// Invalidation ciblée après une écriture sur une mission (T133).
  Future<void> invalidateMissionDetail(String id) => (_db.delete(
    _db.cachedMissionDetails,
  )..where(($CachedMissionDetailsTable t) => t.id.equals(id))).go();

  // --- Messagerie ---------------------------------------------------------------

  /// Messages d'un fil, dans l'ordre naturel du service (croissant).
  Future<CachedValue<List<JsonMap>>?> readMessages(String threadId) async {
    final List<CachedMessageRow> rows =
        await (_db.select(_db.cachedMessages)
              ..where(($CachedMessagesTable t) => t.threadId.equals(threadId))
              ..orderBy(<OrderClauseGenerator<$CachedMessagesTable>>[
                ($CachedMessagesTable t) => OrderingTerm.asc(t.createdAt),
              ]))
            .get();
    return _collect(
      rows.map((CachedMessageRow row) => (row.payload, row.fetchedAt)),
    );
  }

  Future<void> writeMessages(
    String threadId,
    List<({String id, DateTime createdAt, JsonMap payload})> entries, {
    required DateTime fetchedAt,
  }) => _db.batch((Batch batch) {
    batch.insertAllOnConflictUpdate(
      _db.cachedMessages,
      entries.map(
        (({String id, DateTime createdAt, JsonMap payload}) e) =>
            CachedMessagesCompanion.insert(
              id: e.id,
              threadId: threadId,
              createdAt: e.createdAt,
              payload: jsonEncode(e.payload),
              fetchedAt: fetchedAt,
            ),
      ),
    );
  });

  Future<void> invalidateThread(String threadId) => (_db.delete(
    _db.cachedMessages,
  )..where(($CachedMessagesTable t) => t.threadId.equals(threadId))).go();

  // --- Purge globale ------------------------------------------------------------

  /// Efface l'intégralité du cache — déconnexion, désactivation (SC-012).
  Future<void> purgeAll() => _db.purgeEverything();

  // --- Utilitaires --------------------------------------------------------------

  static JsonMap _decodeObject(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<Object?, Object?>) {
      throw FormatException('Charge utile de cache illisible', raw);
    }
    return decoded.cast<String, Object?>();
  }

  /// Assemble des lignes en une valeur datée.
  ///
  /// La date retenue est la **plus ancienne** du lot : l'âge affiché ne doit jamais
  /// paraître plus frais que la donnée la plus périmée de la liste.
  static CachedValue<List<JsonMap>>? _collect(
    Iterable<(String, DateTime)> rows,
  ) {
    final List<JsonMap> values = <JsonMap>[];
    DateTime? oldest;
    for (final (String payload, DateTime fetchedAt) in rows) {
      values.add(_decodeObject(payload));
      if (oldest == null || fetchedAt.isBefore(oldest)) {
        oldest = fetchedAt;
      }
    }
    if (oldest == null) {
      return null;
    }
    return CachedValue<List<JsonMap>>(value: values, fetchedAt: oldest);
  }
}
