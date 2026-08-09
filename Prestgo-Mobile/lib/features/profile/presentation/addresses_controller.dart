// Carnet d'adresses — état partagé par l'écran de liste et l'étape de réservation.
//
// Le cache est servi d'abord : l'étape « lieu d'intervention » d'une réservation ne
// doit pas attendre le réseau pour afficher un carnet qui n'a pas changé depuis le
// dernier démarrage.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/features/profile/data/address_repository.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';

class AddressesController extends AsyncNotifier<List<Address>> {
  @override
  Future<List<Address>> build() async {
    if (!ref.watch(sessionControllerProvider).isAuthenticated) {
      return const <Address>[];
    }

    final AddressRepository repository = ref.read(addressRepositoryProvider);
    final List<Address>? cached = await repository.cached();

    try {
      return await repository.list();
    } on ApiException catch (error) {
      // Hors ligne avec un carnet connu : on le sert. Toute écriture reste de
      // toute façon refusée sans réseau (§5 du contrat de rejeu).
      if (cached != null && error.isNetwork) {
        return cached;
      }
      rethrow;
    }
  }

  /// Adresse par défaut, ou la première du carnet, ou `null`.
  ///
  /// Le service trie déjà l'adresse par défaut en tête : le repli sur la première
  /// couvre un carnet dont aucune n'est marquée.
  Address? get defaultAddress {
    final List<Address>? addresses = state.value;
    if (addresses == null || addresses.isEmpty) {
      return null;
    }
    for (final Address address in addresses) {
      if (address.isDefault) {
        return address;
      }
    }
    return addresses.first;
  }

  /// Vrai quand le plafond du service est atteint : l'ajout est alors rendu
  /// indisponible **avec son motif**, plutôt que laissé actif pour échouer (FR-020).
  bool get isAtCapacity =>
      AddressRepository.isAtCapacity(state.value?.length ?? 0);

  Future<void> reload() async {
    state = await AsyncValue.guard<List<Address>>(
      ref.read(addressRepositoryProvider).list,
    );
  }

  Future<Address> create(AddressDraft draft) async {
    final Address created = await ref
        .read(addressRepositoryProvider)
        .create(draft);
    await reload();
    return created;
  }

  /// Nommée `edit` et non `update` : `AsyncNotifier` réserve déjà ce nom pour la
  /// transformation de son propre état.
  Future<Address> edit(String addressId, AddressDraft draft) async {
    final Address updated = await ref
        .read(addressRepositoryProvider)
        .update(addressId, draft);
    await reload();
    return updated;
  }

  /// Définit l'adresse par défaut.
  ///
  /// La réponse **est** la liste à jour : l'état s'alimente directement, sans le
  /// `GET` qu'un `reload()` provoquerait.
  Future<void> setDefault(String addressId) async {
    state = await AsyncValue.guard<List<Address>>(
      () => ref.read(addressRepositoryProvider).setDefault(addressId),
    );
  }

  /// Supprime, et renvoie **ce qui s'est réellement passé**.
  ///
  /// Les deux issues sont des succès : retrait, ou archivage quand l'adresse
  /// documente une mission passée. L'écran affiche le message correspondant.
  Future<AddressRemoval> remove(String addressId) async {
    final AddressRemoval result = await ref
        .read(addressRepositoryProvider)
        .remove(addressId);
    await reload();
    return result;
  }
}

final AsyncNotifierProvider<AddressesController, List<Address>>
addressesProvider = AsyncNotifierProvider<AddressesController, List<Address>>(
  AddressesController.new,
);
