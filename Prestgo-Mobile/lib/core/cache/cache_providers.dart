// Providers du cache de lecture.
//
// Volontairement dépourvu de dépendance vers la couche réseau : la purge de session
// doit pouvoir atteindre la base locale sans passer par le client d'API.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';

/// Base locale — une seule instance pour toute l'application.
final Provider<LocalDatabase> localDatabaseProvider = Provider<LocalDatabase>((
  Ref ref,
) {
  final LocalDatabase database = LocalDatabase();
  ref.onDispose(database.close);
  return database;
});

final Provider<CacheDao> cacheDaoProvider = Provider<CacheDao>(
  (Ref ref) => CacheDao(ref.watch(localDatabaseProvider)),
);
