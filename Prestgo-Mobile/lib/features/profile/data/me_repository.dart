// Opérations 9 à 12 de contracts/api-consumption.md, et cache du profil (T080).
//
// Le profil est la seule donnée que l'application met en cache **avant** d'en avoir
// besoin à l'écran : c'est lui qui pilote l'aiguillage au démarrage. Sans lui, une
// ouverture hors ligne resterait bloquée sur l'écran de démarrage faute de savoir
// quel espace ouvrir (FR-013, US10).
//
// Ce que le cache ne contient pas : ni jeton, ni mot de passe, ni `pendingVerifications`
// (porte G6). Seuls des champs déjà affichés à l'écran y figurent.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/api/request_markers.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';

/// Résultat de `POST /me/password`.
class PasswordChangeResult {
  const PasswordChangeResult({
    required this.revokedSessions,
    required this.message,
  });

  /// Nombre d'**autres** sessions fermées. La session courante est épargnée : c'est
  /// la différence avec la réinitialisation, qui les coupe toutes (FR-018).
  final int revokedSessions;

  /// Message du service, chiffre compris — affiché tel quel (FR-088).
  final String message;
}

class MeRepository {
  const MeRepository(this._client, this._cache);

  final ApiClient _client;
  final CacheDao _cache;

  // --- 9. Profil ----------------------------------------------------------------

  /// `GET /me` — et mise en cache dans la foulée.
  Future<Me> fetch() async {
    final ApiEnvelope<Me> envelope = await _client.get<Me>(
      '/me',
      parse: parseObject<Me>(Me.fromJson),
    );
    final Me me = envelope.requireData;
    await _writeCache(me);
    return me;
  }

  /// Profil du dernier démarrage, ou `null`.
  ///
  /// Sert l'aiguillage immédiatement, y compris sans réseau. La valeur peut être
  /// périmée — un dossier prestataire approuvé entre-temps, par exemple : `GET /me`
  /// la remplace dès qu'il aboutit, et le gardien réévalue.
  Future<Me?> cached() async {
    try {
      final CachedValue<JsonMap>? row = await _cache.readProfile();
      return row == null ? null : Me.fromJson(row.value);
    } on FormatException {
      // Cache écrit par une version antérieure du modèle : on repart de zéro
      // plutôt que de faire échouer le démarrage.
      await _cache.invalidateProfile();
      return null;
    }
  }

  // --- 10. Édition du profil ----------------------------------------------------

  /// `PATCH /me`.
  ///
  /// Ne transmet que les champs réellement fournis : le service applique
  /// `whitelist: true`, et un `null` explicite n'a pas le même sens qu'une absence.
  ///
  /// ⚠️ Modifier un contact le repasse en non vérifié et déclenche un code. La
  /// réponse porte alors `pendingVerifications` : l'appelant doit enchaîner sur la
  /// vérification (FR-017), sans quoi l'utilisateur se retrouve avec un contact
  /// définitivement marqué « non vérifié ».
  Future<Me> updateProfile({
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
  }) async {
    final ApiEnvelope<Me> envelope = await _client.patch<Me>(
      '/me',
      body: <String, Object?>{
        'firstName': ?firstName,
        'lastName': ?lastName,
        'email': ?email,
        'phone': ?phone,
      },
      parse: parseObject<Me>(Me.fromJson),
    );
    final Me me = envelope.requireData;
    await _writeCache(me);
    return me;
  }

  // --- 11. Changement de mot de passe -------------------------------------------

  /// `POST /me/password` — la session courante survit.
  ///
  /// `kSkipRefreshExtra` : un mot de passe actuel erroné renvoie **401**, sans que la
  /// session soit en cause. Sans ce marqueur, l'intercepteur y verrait une session
  /// périmée et déconnecterait l'utilisateur pour une faute de frappe.
  Future<PasswordChangeResult> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final ApiEnvelope<int> envelope = await _client.post<int>(
      '/me/password',
      body: <String, Object?>{
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
      extra: const <String, Object?>{kSkipRefreshExtra: true},
      parse: parseObject<int>(
        (JsonMap json) => switch (json['revokedSessions']) {
          final int value => value,
          final num value => value.toInt(),
          _ => 0,
        },
      ),
    );
    return PasswordChangeResult(
      revokedSessions: envelope.data ?? 0,
      message: envelope.message ?? 'Mot de passe mis à jour.',
    );
  }

  // --- 12. Désactivation du compte ----------------------------------------------

  /// `DELETE /me` — le compte passe à `deleted`, **rien n'est effacé**.
  ///
  /// Refusée tant qu'une mission est confirmée ou en cours : le message du service
  /// porte alors leur nombre et s'affiche tel quel.
  ///
  /// `kSkipRefreshExtra` pour la même raison qu'au changement de mot de passe : un
  /// mot de passe erroné répond 401.
  Future<void> deactivate({required String password}) async {
    await _client.delete<void>(
      '/me',
      body: <String, Object?>{'password': password},
      extra: const <String, Object?>{kSkipRefreshExtra: true},
      parse: parseNothing(),
    );
  }

  Future<void> _writeCache(Me me) => _cache.writeProfile(
    id: me.id,
    payload: me.toJson(),
    fetchedAt: DateTime.now(),
  );
}

final Provider<MeRepository> meRepositoryProvider = Provider<MeRepository>(
  (Ref ref) =>
      MeRepository(ref.watch(apiClientProvider), ref.watch(cacheDaoProvider)),
);
