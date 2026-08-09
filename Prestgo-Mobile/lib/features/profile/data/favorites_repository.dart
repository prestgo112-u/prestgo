// Favoris — opérations 18 à 20 (T104, FR-021).
//
// Les deux écritures sont **idempotentes par construction** : rappuyer sur le cœur ne
// produit jamais d'erreur, et retirer un favori absent est un succès. C'est ce qui
// autorise la politique de rejeu à les réessayer une fois, et ce qui rend l'affichage
// optimiste sans risque.
//
// Un prestataire devenu non réservable **reste** dans la liste, avec `available` à
// faux : le faire disparaître laisserait croire à une perte.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

/// Prestataire mis en favori.
class FavoriteProvider {
  const FavoriteProvider({
    required this.id,
    required this.publicName,
    required this.score,
    required this.reviewsCount,
    required this.available,
    required this.favoritedAt,
    this.bio,
    this.categories = const <String>[],
  });

  factory FavoriteProvider.fromJson(JsonMap json) => FavoriteProvider(
    id: json['id'] as String? ?? '',
    publicName: json['publicName'] as String? ?? '',
    bio: json['bio'] as String?,
    score: switch (json['score']) {
      final num v => v.toDouble(),
      _ => 0.0,
    },
    reviewsCount: switch (json['reviewsCount']) {
      final num v => v.toInt(),
      _ => 0,
    },
    categories: switch (json['categories']) {
      final List<Object?> list => list.whereType<String>().toList(
        growable: false,
      ),
      _ => const <String>[],
    },
    available: json['available'] as bool? ?? false,
    favoritedAt:
        MissionDates.fromApiOrNull(json['favoritedAt'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  final String id;
  final String publicName;
  final String? bio;
  final double score;
  final int reviewsCount;
  final List<String> categories;

  /// Agrège les deux conditions que le client comprend : dossier encore validé,
  /// et prestataire déclaré joignable.
  final bool available;

  final DateTime favoritedAt;

  bool get isNew => reviewsCount == 0;
}

class FavoritesRepository {
  const FavoritesRepository(this._client);

  final ApiClient _client;

  /// `GET /me/favorites` — non paginé.
  Future<List<FavoriteProvider>> list() async {
    final ApiEnvelope<List<FavoriteProvider>> envelope = await _client
        .get<List<FavoriteProvider>>(
          '/me/favorites',
          parse: parseList<FavoriteProvider>(FavoriteProvider.fromJson),
        );
    return envelope.data ?? const <FavoriteProvider>[];
  }

  /// `POST /me/favorites/{providerId}` — idempotent.
  Future<void> add(String providerId) =>
      _client.post<void>('/me/favorites/$providerId', parse: parseNothing());

  /// `DELETE /me/favorites/{providerId}` — idempotent, jamais d'erreur métier.
  Future<void> remove(String providerId) =>
      _client.delete<void>('/me/favorites/$providerId', parse: parseNothing());
}

final Provider<FavoritesRepository> favoritesRepositoryProvider =
    Provider<FavoritesRepository>(
      (Ref ref) => FavoritesRepository(ref.watch(apiClientProvider)),
    );
