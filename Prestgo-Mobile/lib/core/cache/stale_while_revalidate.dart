// « Servir le cache, puis revalider » (R10).
//
// Ce motif donne un premier écran instantané au démarrage **et** fait du mode hors
// ligne (US10) une conséquence du même code, plutôt qu'un chemin parallèle : quand
// le réseau manque, la valeur en cache est simplement la dernière émise, avec son
// âge et la raison de l'échec.

import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';

/// Une valeur servie à l'écran, avec sa provenance.
class CacheSnapshot<T> {
  const CacheSnapshot({
    required this.value,
    required this.isFromCache,
    this.fetchedAt,
    this.revalidationError,
  });

  /// Valeur fraîche, arrivée du service.
  const CacheSnapshot.fresh(this.value)
    : isFromCache = false,
      fetchedAt = null,
      revalidationError = null;

  final T value;

  /// Vrai tant que la valeur vient du disque et non du service.
  final bool isFromCache;

  /// Date d'obtention de la donnée en cache — alimente « Mis à jour il y a N min ».
  final DateTime? fetchedAt;

  /// Échec de la revalidation, quand une valeur en cache a pu être servie malgré
  /// tout. L'écran affiche la donnée **et** signale qu'elle n'a pas pu être
  /// rafraîchie ; il ne présente pas une erreur bloquante.
  final ApiException? revalidationError;

  /// Vrai si la donnée affichée n'a pas pu être rafraîchie.
  bool get isStale => isFromCache && revalidationError != null;

  @override
  String toString() =>
      'CacheSnapshot(cache: $isFromCache, $fetchedAt, erreur: $revalidationError)';
}

/// Sert le cache puis la valeur fraîche.
///
/// Émet une fois si aucun cache n'existe (valeur réseau), deux fois sinon (cache
/// puis réseau). Quand [ttl] est fourni et que le cache est encore frais, aucune
/// requête n'est faite : c'est le cas du catalogue et des zones, quasi statiques.
///
/// Le seul cas où une exception remonte est l'absence simultanée de cache **et** de
/// réseau : il n'y a alors rien à afficher.
Stream<CacheSnapshot<T>> staleWhileRevalidate<T>({
  required Future<CachedValue<T>?> Function() readCache,
  required Future<T> Function() fetch,
  required Future<void> Function(T value) writeCache,
  Duration? ttl,
  DateTime Function() clock = DateTime.now,
}) async* {
  CachedValue<T>? cached;
  try {
    cached = await readCache();
  } on FormatException {
    // Cache illisible (modèle qui a évolué) : on repart du réseau plutôt que de
    // faire échouer l'écran.
    cached = null;
  }

  if (cached != null) {
    yield CacheSnapshot<T>(
      value: cached.value,
      isFromCache: true,
      fetchedAt: cached.fetchedAt,
    );

    if (ttl != null && !cached.isStaleAt(clock(), ttl)) {
      return;
    }
  }

  try {
    final T fresh = await fetch();
    await writeCache(fresh);
    yield CacheSnapshot<T>.fresh(fresh);
  } on ApiException catch (error) {
    final CachedValue<T>? fallback = cached;
    if (fallback == null) {
      rethrow;
    }
    yield CacheSnapshot<T>(
      value: fallback.value,
      isFromCache: true,
      fetchedAt: fallback.fetchedAt,
      revalidationError: error,
    );
  }
}
