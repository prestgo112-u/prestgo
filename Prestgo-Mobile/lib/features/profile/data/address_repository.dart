// Carnet d'adresses — opérations 13 à 17 (T096).
//
// Deux particularités du service donnent sa forme à ce dépôt :
//
//   • `POST /me/addresses/{id}/default` renvoie **la liste complète à jour**, pas
//     l'adresse modifiée. C'est une économie d'appel voulue : l'écran se réalimente
//     directement avec la réponse ;
//   • `DELETE /me/addresses/{id}` a **deux formes de succès** — retrait réel, ou
//     archivage lorsque l'adresse documente une mission passée. Traiter la seconde
//     comme un échec ferait croire à une suppression ratée alors qu'elle a fait
//     exactement ce qu'il fallait.
//
// Le cache est écrit à chaque lecture : le carnet doit rester consultable hors ligne,
// puisqu'il conditionne l'étape « lieu d'intervention » d'une réservation.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';

class AddressRepository {
  const AddressRepository(this._client, this._cache);

  final ApiClient _client;
  final CacheDao _cache;

  /// `GET /me/addresses` — non paginé, adresse par défaut en tête.
  Future<List<Address>> list() async {
    final ApiEnvelope<List<Address>> envelope = await _client
        .get<List<Address>>(
          '/me/addresses',
          parse: parseList<Address>(Address.fromJson),
        );
    final List<Address> addresses = envelope.data ?? const <Address>[];
    await _writeCache(addresses);
    return addresses;
  }

  /// Carnet du dernier chargement. `null` si rien n'a jamais été lu.
  Future<List<Address>?> cached() async {
    final CachedValue<List<JsonMap>>? cached = await _cache.readAddresses();
    return cached?.value.map(Address.fromJson).toList(growable: false);
  }

  /// `POST /me/addresses`.
  ///
  /// La première adresse d'un carnet devient automatiquement l'adresse par défaut :
  /// c'est le service qui le décide, l'application ne le force pas.
  Future<Address> create(AddressDraft draft) async {
    final ApiEnvelope<Address> envelope = await _client.post<Address>(
      '/me/addresses',
      body: draft.toJson(),
      parse: parseObject<Address>(Address.fromJson),
    );
    await _cache.invalidateAddresses();
    return envelope.requireData;
  }

  /// `PATCH /me/addresses/{id}`.
  Future<Address> update(String addressId, AddressDraft draft) async {
    final ApiEnvelope<Address> envelope = await _client.patch<Address>(
      '/me/addresses/$addressId',
      body: draft.toJson(),
      parse: parseObject<Address>(Address.fromJson),
    );
    await _cache.invalidateAddresses();
    return envelope.requireData;
  }

  /// `DELETE /me/addresses/{id}` — les deux issues sont des succès.
  Future<AddressRemoval> remove(String addressId) async {
    final ApiEnvelope<AddressRemoval> envelope = await _client
        .delete<AddressRemoval>(
          '/me/addresses/$addressId',
          parse: parseObject<AddressRemoval>(AddressRemoval.fromJson),
        );
    await _cache.invalidateAddresses();
    // Une réponse sans contenu reste un succès : on retombe sur un retrait.
    return envelope.data ??
        const AddressRemoval(removed: true, archived: false);
  }

  /// `POST /me/addresses/{id}/default` — renvoie **la liste**, pas l'adresse.
  Future<List<Address>> setDefault(String addressId) async {
    final ApiEnvelope<List<Address>> envelope = await _client
        .post<List<Address>>(
          '/me/addresses/$addressId/default',
          parse: parseList<Address>(Address.fromJson),
        );
    final List<Address> addresses = envelope.data ?? const <Address>[];
    await _writeCache(addresses);
    return addresses;
  }

  /// Vrai si le plafond du service est atteint.
  ///
  /// L'ajout est rendu indisponible **avec son motif** plutôt que laissé actif pour
  /// échouer ensuite (FR-020).
  static bool isAtCapacity(int count) =>
      count >= ContentLimits.addressesPerAccount;

  Future<void> _writeCache(List<Address> addresses) =>
      _cache.writeAddresses(<({String id, bool isDefault, JsonMap payload})>[
        for (final Address address in addresses)
          (
            id: address.id,
            isDefault: address.isDefault,
            payload: <String, Object?>{
              'id': address.id,
              'label': address.label,
              'city': address.city,
              'commune': address.commune,
              'details': address.details,
              'latitude': address.latitude,
              'longitude': address.longitude,
              'isDefault': address.isDefault,
              'createdAt': address.createdAt.toUtc().toIso8601String(),
            },
          ),
      ], fetchedAt: DateTime.now());
}

final Provider<AddressRepository> addressRepositoryProvider =
    Provider<AddressRepository>(
      (Ref ref) => AddressRepository(
        ref.watch(apiClientProvider),
        ref.watch(cacheDaoProvider),
      ),
    );
