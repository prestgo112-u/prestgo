// Stockage des jetons de session (porte G6, data-model §1.1).
//
// Les deux jetons sont conservés **dans une seule entrée** : c'est ce qui rend leur
// écriture atomique. Un remplacement partiel — jeton d'accès mis à jour, jeton de
// renouvellement resté ancien — déconnecte l'utilisateur au renouvellement suivant,
// puisque la rotation révoque systématiquement l'ancien jeton de renouvellement.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Couple de jetons de session.
class AuthTokens {
  const AuthTokens({required this.accessToken, required this.refreshToken});

  factory AuthTokens.fromJson(Map<String, Object?> json) => AuthTokens(
    accessToken: json['accessToken'] as String? ?? '',
    refreshToken: json['refreshToken'] as String? ?? '',
  );

  /// JWT de 15 minutes.
  final String accessToken;

  /// Chaîne opaque de 7 jours, **tournante** : remplacée à chaque renouvellement.
  final String refreshToken;

  bool get isComplete => accessToken.isNotEmpty && refreshToken.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'accessToken': accessToken,
    'refreshToken': refreshToken,
  };

  @override
  bool operator ==(Object other) =>
      other is AuthTokens &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken);

  /// Volontairement muet : ces valeurs ne doivent apparaître dans aucun journal.
  @override
  String toString() => 'AuthTokens(<masqués>)';
}

/// Lecture, écriture atomique et purge des secrets de session.
class SecureTokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock,
            ),
          );

  /// Entrée unique portant les deux jetons — garantit l'atomicité.
  static const String tokensKey = 'prestgo.session.tokens';

  /// Jeton d'appareil courant : conservé pour pouvoir le désenregistrer **avant**
  /// la déconnexion et lors d'un changement de jeton (data-model §1.3).
  static const String deviceTokenKey = 'prestgo.device.token';

  final FlutterSecureStorage _storage;

  /// Jetons de session, ou `null` si aucune session n'est ouverte.
  ///
  /// Une entrée illisible ou incomplète est traitée comme une absence de session et
  /// purgée : mieux vaut une reconnexion qu'une session à moitié valide.
  Future<AuthTokens?> read() async {
    final String? raw = await _storage.read(key: tokensKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<Object?, Object?>) {
        await clearTokens();
        return null;
      }
      final AuthTokens tokens = AuthTokens.fromJson(
        decoded.cast<String, Object?>(),
      );
      if (!tokens.isComplete) {
        await clearTokens();
        return null;
      }
      return tokens;
    } on FormatException {
      await clearTokens();
      return null;
    }
  }

  /// Écrit les deux jetons en une seule opération.
  Future<void> write(AuthTokens tokens) {
    if (!tokens.isComplete) {
      throw ArgumentError.value(
        tokens,
        'tokens',
        'Les deux jetons sont requis : une écriture partielle casse la rotation',
      );
    }
    return _storage.write(key: tokensKey, value: jsonEncode(tokens.toJson()));
  }

  Future<void> clearTokens() => _storage.delete(key: tokensKey);

  Future<String?> readDeviceToken() => _storage.read(key: deviceTokenKey);

  Future<void> writeDeviceToken(String token) =>
      _storage.write(key: deviceTokenKey, value: token);

  Future<void> clearDeviceToken() => _storage.delete(key: deviceTokenKey);

  /// Purge complète — appelée à la déconnexion et à la désactivation (SC-012).
  Future<void> clearAll() async {
    await clearTokens();
    await clearDeviceToken();
  }
}
