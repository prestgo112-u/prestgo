// Boutons d'action du prestataire, par état (T170, FR-041, FR-046).
//
// La table est celle de data-model §5.3, et deux règles la verrouillent :
//   • **« Refuser » et « Annuler la mission » ne coexistent jamais** — refus
//     avant acceptation (`pending_provider`), annulation après (`confirmed`).
//     Appeler l'un à la place de l'autre est refusé par le service (5.2) ;
//   • **aucune action sur un état terminal** — `closed` et `cancelled` se
//     consultent, `disputed` se suit, un statut inconnu de cette version
//     n'offre rien (mieux vaut aucun bouton qu'un bouton qui échouera).
//
// La machine à états reste au service (porte G1) : au pire, une action affichée
// à tort est refusée avec son message — jamais l'inverse silencieux. Et une
// transition n'est **jamais** rejouée (porte G4) : réponse non reçue → l'état
// réel est rechargé, l'utilisateur décide (scénario 5.5).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/features/missions/data/mission_transition_controller.dart';
import 'package:prestgo_mobile/features/missions/domain/cancellation.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_detail.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_providers.dart';
import 'package:prestgo_mobile/features/missions/presentation/reason_dialog.dart';
import 'package:prestgo_mobile/features/missions/presentation/start_action.dart';

/// Affiché quand la réponse d'une transition n'est jamais parvenue (FR-046).
const String kTransitionOutcomeUnknownMessage =
    'Votre action n’a peut-être pas été reçue : l’état réel de la mission a '
    'été rechargé. Vérifiez-le avant de recommencer.';

class MissionActionsBar extends ConsumerStatefulWidget {
  const MissionActionsBar({required this.mission, super.key});

  final MissionDetail mission;

  @override
  ConsumerState<MissionActionsBar> createState() => _MissionActionsBarState();
}

class _MissionActionsBarState extends ConsumerState<MissionActionsBar> {
  bool _busy = false;

  /// Exécute une transition en appliquant la conduite de T174 : succès →
  /// invalidation + message du service ; réponse non reçue → rechargement,
  /// jamais de rejeu ; réalité changée → rechargement + message du service.
  Future<void> _run(
    Future<MissionTransitionResult> Function(MissionTransitionController)
    action,
  ) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    MissionTransitionResult? result;
    ApiException? failure;
    try {
      result = await action(ref.read(missionTransitionControllerProvider));
    } on ApiException catch (error) {
      failure = error;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    if (!mounted) {
      return;
    }

    if (result != null) {
      invalidateAfterMissionWrite(ref, widget.mission.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }

    final ApiException error = failure!;
    if (MissionTransitionController.outcomeUnknown(error)) {
      // Issue inconnue : le cache est déjà purgé (T174) — recharger et laisser
      // l'utilisateur décider. Aucun rejeu (scénario 5.5).
      invalidateAfterMissionWrite(ref, widget.mission.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(kTransitionOutcomeUnknownMessage)),
      );
      return;
    }
    if (MissionTransitionController.stateChanged(error)) {
      // Le statut a changé entre l'affichage et l'envoi : insister serait
      // mentir — on recharge la réalité.
      invalidateAfterMissionWrite(ref, widget.mission.id);
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
  }

  Future<void> _refuse() async {
    final String? reason = await showReasonDialog(
      context,
      title: 'Refuser la mission',
      confirmLabel: 'Refuser la mission',
    );
    if (reason == null) {
      return;
    }
    await _run(
      (MissionTransitionController c) =>
          c.refuse(widget.mission.id, reason: reason),
    );
  }

  Future<void> _cancel() async {
    // L'avertissement de tardiveté se donne AVANT l'envoi — seuil lu auprès du
    // service (porte G3) ; le verdict affiché ensuite est le sien (FR-045).
    final bool lateWarning = isLateCancellation(
      scheduledAt: widget.mission.scheduledAt,
      now: DateTime.now(),
      notice: ref.read(publicSettingsProvider).cancellationNotice,
    );
    final String? reason = await showReasonDialog(
      context,
      title: 'Annuler la mission',
      confirmLabel: 'Confirmer l’annulation',
      warning: lateWarning
          ? 'Cette annulation sera enregistrée comme tardive.'
          : null,
    );
    if (reason == null) {
      return;
    }
    await _run(
      (MissionTransitionController c) =>
          c.cancel(widget.mission.id, reason: reason),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return switch (widget.mission.status) {
      // Avant acceptation : accepter ou refuser — jamais « Annuler » (5.2).
      MissionStatus.pendingProvider => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                    (MissionTransitionController c) =>
                        c.accept(widget.mission.id),
                  ),
            icon: const Icon(Icons.check),
            label: const Text('Accepter'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _refuse,
            icon: const Icon(Icons.close),
            label: const Text('Refuser'),
          ),
        ],
      ),
      // Après acceptation : démarrer (fenêtre) ou annuler — plus de refus.
      MissionStatus.confirmed => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          StartMissionButton(
            scheduledAt: widget.mission.scheduledAt,
            busy: _busy,
            onStart: () => _run(
              (MissionTransitionController c) => c.start(widget.mission.id),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _busy ? null : _cancel,
            icon: Icon(Icons.cancel_outlined, color: theme.colorScheme.error),
            label: Text(
              'Annuler la mission',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
      MissionStatus.inProgress => FilledButton.icon(
        onPressed: _busy
            ? null
            : () => _run(
                (MissionTransitionController c) =>
                    c.complete(widget.mission.id),
              ),
        icon: const Icon(Icons.task_alt),
        label: const Text('Terminer la mission'),
      ),
      // États terminaux, litige, statut inconnu : aucune action (FR-041).
      _ => const SizedBox.shrink(),
    };
  }
}
