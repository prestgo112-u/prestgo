// L'aperçu du dossier — l'état **unique** que lisent le hub P8, le suivi P9 et
// l'écran de profil de l'espace prestataire.
//
// Un seul état, pas trois : la checklist, le statut et `canSubmit` viennent tous
// du même `GET /providers/me`, et deux copies finiraient par diverger — l'une
// afficherait « Soumettre » quand l'autre saurait le dossier déjà soumis.
//
// C'est aussi le point de partage entre les deux fonctionnalités prestataire :
// `provider_space` lit ce provider (couche présentation) plutôt que le dépôt de
// `provider_onboarding` — la couche `data/` d'une fonctionnalité lui appartient
// (règle cross_feature_data de la porte G5).
//
// Invalidation (FR-050) : toute écriture du dossier — profil, service, formule,
// zones, agenda, justificatif — rend la checklist fausse. Les écritures qui
// répondent l'aperçu à jour l'**adoptent** (un GET de moins) ; les autres
// invalident, et le prochain lecteur rechargera.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';

class ProviderOverviewController extends AsyncNotifier<ProviderProfile> {
  @override
  Future<ProviderProfile> build() =>
      ref.read(providerSelfRepositoryProvider).overview();

  /// Relit `GET /providers/me` — après un dépôt de justificatif (FR-059), au
  /// retour au premier plan du suivi P9, au geste de rafraîchissement.
  Future<void> reload() async {
    state = const AsyncValue<ProviderProfile>.loading();
    state = await AsyncValue.guard<ProviderProfile>(
      () => ref.read(providerSelfRepositoryProvider).overview(),
    );
  }

  /// Adopte un aperçu déjà obtenu — la réponse d'un `POST`, `PATCH` ou `submit`,
  /// qui renvoient précisément ce DTO.
  void adopt(ProviderProfile profile) =>
      state = AsyncValue<ProviderProfile>.data(profile);

  // --- Écritures relayées --------------------------------------------------------
  //
  // L'espace prestataire passe par ces méthodes plutôt que par le dépôt : la
  // couche `data/` d'une fonctionnalité ne s'importe pas depuis une autre
  // (règle cross_feature_data), et la réponse — l'aperçu à jour — est adoptée
  // ici même, au seul endroit qui porte l'état.

  /// `PATCH /providers/me` — identité du profil. Relaie l'`ApiException` du
  /// service, verrou de `pending_review` compris.
  Future<ProviderProfile> updateIdentity({
    String? publicName,
    String? bio,
    int? experienceYears,
    String? avatarFileId,
  }) async {
    final ProviderProfile updated = await ref
        .read(providerSelfRepositoryProvider)
        .updateProfile(
          publicName: publicName,
          bio: bio,
          experienceYears: experienceYears,
          avatarFileId: avatarFileId,
        );
    adopt(updated);
    return updated;
  }

  /// `PATCH /providers/me` avec `availabilityStatus` seul — le champ qui
  /// traverse le verrou (scénario 4.8).
  Future<ProviderProfile> setAvailability(AvailabilityStatus status) async {
    final ProviderProfile updated = await ref
        .read(providerSelfRepositoryProvider)
        .setAvailability(status);
    adopt(updated);
    return updated;
  }
}

final AsyncNotifierProvider<ProviderOverviewController, ProviderProfile>
providerOverviewProvider =
    AsyncNotifierProvider<ProviderOverviewController, ProviderProfile>(
      ProviderOverviewController.new,
    );
