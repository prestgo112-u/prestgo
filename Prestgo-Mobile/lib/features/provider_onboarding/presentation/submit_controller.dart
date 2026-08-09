// Soumission du dossier (T157, FR-060, FR-061, FR-063).
//
// Le refus « dossier incomplet » (400) porte `errors[].field` = des clés de
// checklist. Ce contrôleur les traduit en `ChecklistStep` et les garde dans son
// état : le hub passe en rouge **exactement** ces lignes-là, avec le libellé du
// service sous chacune — jamais une ligne devinée localement (scénario 4.7).
//
// Le 403 « re-soumission bloquée » n'a pas de ligne à désigner : l'issue est un
// écran de contact support, et le bouton disparaît pour de bon. L'aperçu est
// rechargé pour que `resubmissionBlocked` reflète la réalité.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_overview_controller.dart';

/// Ce que la dernière tentative de soumission a laissé à l'écran.
class SubmitState {
  const SubmitState({
    this.submitting = false,
    this.failedSteps = const <ChecklistStep>{},
    this.fieldMessages = const <String, String>{},
    this.banner,
    this.blocked = false,
  });

  final bool submitting;

  /// Lignes désignées par le service — rouges, et elles seules (4.7).
  final Set<ChecklistStep> failedSteps;

  /// Libellé officiel par clé de checklist, affiché sous la ligne.
  final Map<String, String> fieldMessages;

  /// Message hors champ : « rien à soumettre », re-soumission bloquée, réseau.
  final String? banner;

  /// Vrai après un 403 : le bouton ne doit plus jamais réapparaître.
  final bool blocked;

  String? messageFor(ChecklistStep step) => fieldMessages[step.key];
}

class SubmitController extends Notifier<SubmitState> {
  @override
  SubmitState build() => const SubmitState();

  /// `POST /providers/me/submit`. Rend l'aperçu à jour en cas de succès, `null`
  /// sinon — l'échec est déjà dans l'état.
  Future<ProviderProfile?> submit() async {
    if (state.submitting) {
      return null;
    }
    state = const SubmitState(submitting: true);

    try {
      final ProviderProfile profile = await ref
          .read(providerSelfRepositoryProvider)
          .submit();
      // La réponse EST l'aperçu à jour (pending_review, submittedAt posé) :
      // l'adopter épargne le GET et fait basculer le gardien vers le suivi.
      ref.read(providerOverviewProvider.notifier).adopt(profile);
      state = const SubmitState();
      return profile;
    } on ApiException catch (error) {
      final Set<ChecklistStep> failed = ChecklistStep.fromSubmitError(error);
      state = SubmitState(
        failedSteps: failed,
        fieldMessages: error.fieldMessages,
        // Quand des lignes sont désignées, elles portent déjà l'explication :
        // une bannière répéterait « Votre dossier n'est pas complet ».
        banner: failed.isEmpty ? error.message : null,
        blocked: error.isForbidden,
      );
      if (failed.isEmpty) {
        // « Rien à soumettre », re-soumission bloquée : le statut réel a changé
        // ou n'est pas celui affiché — recharger l'aperçu (§2.2 P8).
        await ref.read(providerOverviewProvider.notifier).reload();
      }
      return null;
    }
  }

  /// Efface le verdict d'une ligne dès que l'étape correspondante a été rouverte.
  void clearStep(ChecklistStep step) {
    if (!state.failedSteps.contains(step)) {
      return;
    }
    state = SubmitState(
      failedSteps: Set<ChecklistStep>.of(state.failedSteps)..remove(step),
      fieldMessages: Map<String, String>.of(state.fieldMessages)
        ..remove(step.key),
      banner: state.banner,
      blocked: state.blocked,
    );
  }
}

final NotifierProvider<SubmitController, SubmitState> submitControllerProvider =
    NotifierProvider<SubmitController, SubmitState>(SubmitController.new);
