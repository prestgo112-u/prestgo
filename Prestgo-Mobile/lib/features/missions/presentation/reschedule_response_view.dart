// Réponse à une demande de report (T132, FR-048, scénarios 3.4 et 3.5).
//
// Deux règles font toute la carte :
//
//   • Accepter/Refuser sont **masqués sur ses propres demandes** — la décision se
//     lit sur `createdBy`, jamais sur le rôle : chaque partie peut proposer, donc
//     chaque partie peut être l'auteur (scénario 3.4). Le 403 « votre propre
//     demande » ne doit jamais partir.
//
//   • Le créneau est **revalidé au moment de l'acceptation** : « n'est plus
//     disponible » n'est pas une impasse — la carte propose immédiatement une
//     contre-proposition, pré-contextualisée (scénario 3.5).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/missions/data/reschedule_repository.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_detail.dart';
import 'package:prestgo_mobile/features/missions/domain/reschedule_request.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_providers.dart';
import 'package:prestgo_mobile/features/missions/presentation/provider_message_rewriter.dart';
import 'package:prestgo_mobile/features/missions/presentation/reschedule_request_screen.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';

/// Message serveur qui déclenche la proposition d'une contre-proposition.
const String kSlotGoneMessage =
    "Le prestataire n'est plus disponible sur ce créneau";

class RescheduleResponseView extends ConsumerStatefulWidget {
  const RescheduleResponseView({
    required this.mission,
    required this.reschedule,
    super.key,
  });

  final MissionDetail mission;
  final RescheduleRequest reschedule;

  @override
  ConsumerState<RescheduleResponseView> createState() =>
      _RescheduleResponseViewState();
}

class _RescheduleResponseViewState
    extends ConsumerState<RescheduleResponseView> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    RescheduleDecision? decision;
    ApiException? failure;
    try {
      decision = await ref
          .read(rescheduleRepositoryProvider)
          .accept(widget.mission.id, widget.reschedule.id);
    } on ApiException catch (error) {
      failure = error;
    } finally {
      // L'occupation s'arrête à la réponse : la suite — dialogue de
      // contre-proposition, écran poussé — ne doit pas laisser le bouton
      // tourner en arrière-plan.
      if (mounted) {
        setState(() => _busy = false);
      }
    }
    if (!mounted) {
      return;
    }

    if (decision != null) {
      invalidateAfterMissionWrite(ref, widget.mission.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(decision.message)));
      return;
    }

    final ApiException error = failure!;
    if (error.message == kSlotGoneMessage) {
      // Revalidation échouée : le parcours continue en contre-proposition. Le
      // message est reformulé à la deuxième personne quand le lecteur EST le
      // prestataire qu'il désigne (FR-049) — la comparaison, elle, reste sur
      // le message brut.
      final bool asProvider =
          ref.read(meControllerProvider).value?.providerId ==
          widget.mission.provider.id;
      await _offerCounterProposal(
        availabilityMessage(error.message, asProvider: asProvider),
      );
    } else {
      // « Déjà traitée », transition invalide… : la réalité a changé.
      invalidateAfterMissionWrite(ref, widget.mission.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _offerCounterProposal(String serverMessage) async {
    final bool? counter = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Créneau indisponible'),
        content: Text(
          '$serverMessage. Vous pouvez proposer une autre date à la place.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Proposer une autre date'),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    invalidateAfterMissionWrite(ref, widget.mission.id);
    if (counter ?? false) {
      await openRescheduleRequest(
        context,
        mission: widget.mission,
        notice:
            'Le créneau accepté n’est plus disponible : proposez une autre '
            'date.',
      );
    }
  }

  Future<void> _reject() async {
    final String? reason = await _askRejectionReason();
    if (reason == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final RescheduleDecision decision = await ref
          .read(rescheduleRepositoryProvider)
          .reject(widget.mission.id, widget.reschedule.id, reason: reason);
      if (!mounted) {
        return;
      }
      invalidateAfterMissionWrite(ref, widget.mission.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(decision.message)));
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      invalidateAfterMissionWrite(ref, widget.mission.id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String?> _askRejectionReason() => showDialog<String>(
    context: context,
    builder: (BuildContext context) => const _RejectionReasonDialog(),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String meId = ref.watch(meControllerProvider).value?.id ?? '';
    final RescheduleRequest reschedule = widget.reschedule;
    final bool mine = reschedule.isMine(meId);
    // Tant que le profil n'est pas connu, aucune action : montrer Accepter sur
    // ce qui pourrait être sa propre demande serait pire qu'attendre un instant.
    final bool canAct = meId.isNotEmpty && reschedule.canRespond(meId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.update, color: theme.colorScheme.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mine
                        ? 'Votre demande de report est en attente de réponse'
                        : 'L’autre partie propose un report',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (reschedule.oldScheduledAt case final DateTime oldDate)
              Text('Date actuelle : ${DateLabels.dayAndTime(oldDate)}'),
            if (reschedule.newScheduledAt case final DateTime newDate)
              Text(
                'Date proposée : ${DateLabels.dayAndTime(newDate)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (reschedule.reason case final String reason)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Motif : $reason',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            // Sur SA demande : aucun bouton — on attend l'autre partie (3.4).
            if (canAct) ...<Widget>[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _busy ? null : _reject,
                    child: const Text('Refuser'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _accept,
                    child: _busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accepter'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Motif de refus — obligatoire, 3 caractères au minimum (FR-044).
class _RejectionReasonDialog extends StatefulWidget {
  const _RejectionReasonDialog();

  @override
  State<_RejectionReasonDialog> createState() => _RejectionReasonDialogState();
}

class _RejectionReasonDialogState extends State<_RejectionReasonDialog> {
  final TextEditingController _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final String reason = _reason.text.trim();
    if (reason.length < ContentLimits.reasonMinLength) {
      setState(
        () => _error =
            'Indiquez un motif d’au moins ${ContentLimits.reasonMinLength} '
            'caractères.',
      );
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Refuser le report'),
    content: TextField(
      controller: _reason,
      autofocus: true,
      maxLength: ContentLimits.reasonMaxLength,
      decoration: InputDecoration(
        labelText: 'Motif (obligatoire)',
        border: const OutlineInputBorder(),
        errorText: _error,
      ),
      onChanged: (String _) => setState(() => _error = null),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Annuler'),
      ),
      FilledButton(onPressed: _confirm, child: const Text('Refuser le report')),
    ],
  );
}
