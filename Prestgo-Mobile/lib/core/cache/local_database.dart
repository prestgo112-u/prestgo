// Base locale de cache de **lecture** (R2, data-model §12).
//
// Chaque ligne porte son `fetchedAt` : c'est lui qui alimente « Mis à jour il y a
// N min » (FR-096) et qui rend le mode hors ligne une conséquence du même code
// plutôt qu'un chemin parallèle.
//
// Ce que cette base ne contient **jamais** :
//   - les jetons de session ni le jeton d'appareil (stockage sécurisé, porte G6) ;
//   - les contenus de fichiers `sensitive` — justificatifs (FR-098) ;
//   - les résultats de recherche et les fiches publiques, qui dépendent de la
//     position et de l'heure et restent en mémoire seulement.
//
// Le contenu applicatif est stocké en JSON dans `payload`, tandis que les colonnes
// nommées portent ce sur quoi on filtre et on trie. Le cache reste ainsi insensible
// à l'évolution des modèles, sans renoncer aux lectures filtrées qui ont justifié
// le choix d'une base relationnelle.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'local_database.g.dart';

/// Profil de l'utilisateur connecté — permet l'aiguillage au démarrage hors ligne.
@DataClassName('CachedProfileRow')
class CachedProfiles extends Table {
  /// Identifiant du compte ; une seule ligne à la fois en pratique.
  TextColumn get id => text()();
  TextColumn get payload => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Catalogue — catégories et types de service. Quasi statique, durée de vie 24 h.
@DataClassName('CachedCatalogRow')
class CachedCatalog extends Table {
  TextColumn get id => text()();
  IntColumn get displayOrder => integer().withDefault(const Constant<int>(0))();
  TextColumn get payload => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Zones d'intervention. Quasi statique, durée de vie 24 h.
@DataClassName('CachedZoneRow')
class CachedZones extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get payload => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Carnet d'adresses — peu volumineux, très consulté.
@DataClassName('CachedAddressRow')
class CachedAddresses extends Table {
  TextColumn get id => text()();
  BoolColumn get isDefault =>
      boolean().withDefault(const Constant<bool>(false))();
  TextColumn get payload => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Première page des missions, par rôle — agenda du jour hors ligne.
///
/// `role` distingue les deux surfaces : un même compte à double casquette voit deux
/// listes différentes, avec des tris par défaut opposés.
@DataClassName('CachedMissionRow')
class CachedMissions extends Table {
  TextColumn get id => text()();

  /// `client` ou `provider`.
  TextColumn get role => text()();

  TextColumn get status => text()();
  DateTimeColumn get scheduledAt => dateTime()();
  TextColumn get payload => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id, role};
}

/// Détail de mission — adresse et instructions consultables sur place.
@DataClassName('CachedMissionDetailRow')
class CachedMissionDetails extends Table {
  TextColumn get id => text()();
  TextColumn get payload => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Messages par fil — relecture hors ligne.
@DataClassName('CachedMessageRow')
class CachedMessages extends Table {
  TextColumn get id => text()();
  TextColumn get threadId => text()();

  /// Tri naturel du fil : croissant, comme le service.
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get payload => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

@DriftDatabase(
  tables: <Type>[
    CachedProfiles,
    CachedCatalog,
    CachedZones,
    CachedAddresses,
    CachedMissions,
    CachedMissionDetails,
    CachedMessages,
  ],
)
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase([QueryExecutor? executor])
    : super(executor ?? _openConnection());

  /// Base en mémoire, pour les tests : rien n'atteint le disque.
  LocalDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  /// Purge **totale** — déconnexion et désactivation de compte (SC-012).
  ///
  /// Aucune donnée du compte précédent ne doit rester consultable après un
  /// changement de compte sur le même appareil.
  Future<void> purgeEverything() => transaction(() async {
    for (final TableInfo<Table, Object?> table in allTables) {
      await delete(table).go();
    }
  });
}

QueryExecutor _openConnection() => LazyDatabase(() async {
  final Directory directory = await getApplicationSupportDirectory();
  final File file = File(p.join(directory.path, 'prestgo_cache.sqlite'));
  return NativeDatabase.createInBackground(file);
});
