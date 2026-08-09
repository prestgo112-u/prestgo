// Lecture des réglages publics au démarrage (opération 21).
//
// Route publique, appelée **une fois**, résultat conservé en mémoire pour la
// session. Elle n'est pas mise en cache sur disque : une modification faite au
// back-office doit ressortir au prochain démarrage (porte G3).

import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/settings/public_settings.dart';

class SettingsRepository {
  const SettingsRepository(this._client);

  static const String path = '/settings/public';

  final ApiClient _client;

  /// Lit les six réglages.
  ///
  /// Un échec — hors ligne, service indisponible — retombe sur
  /// [PublicSettings.fallback] : l'application démarre toujours, quitte à afficher
  /// des seuils approchés jusqu'au prochain lancement.
  Future<PublicSettings> fetch() async {
    try {
      final ApiEnvelope<PublicSettings> envelope = await _client
          .get<PublicSettings>(
            path,
            parse: parseObject<PublicSettings>(PublicSettings.fromJson),
          );
      return envelope.data ?? PublicSettings.fallback;
    } on ApiException {
      return PublicSettings.fallback;
    } on FormatException {
      return PublicSettings.fallback;
    }
  }
}
