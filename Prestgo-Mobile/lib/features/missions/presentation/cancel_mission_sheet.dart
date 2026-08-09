// Parcours d'annulation (T130, FR-044, FR-045, scénario 3.2).
//
// L'ordre des choses est le cœur de cette feuille : l'avertissement de tardiveté
// se donne **avant** l'envoi — seuil lu auprès du service (porte G3) — parce que
// le service, lui, n'avertit pas : il accepte et marque `late`. Après l'appel,
// c'est **son** message qui est affiché tel quel, y compris quand le verdict
// diffère de l'estimation locale.
//
// Une transition n'est jamais rejouée (porte G4) : sur « Transition de mission
// invalide », le statut a changé entre-temps — la feuille se ferme et le détail
// est rechargé.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/missions/data/mission_repository.dart';
import 'package:prestgo_mobile/features/missions/domain/cancellation.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_detail.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_providers.dart';

/// Ouvre la feuille d'annulation. Sur succès, le message **du service** est
/// affiché en snackbar et les lectures de la mission sont invalidées.
Future<void> showCancelMissionSheet(
  BuildContext context, {
  required MissionDetail mission,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: CancelMissionSheet(mission: mission),
  ),
);

class CancelMissionSheet extends ConsumerStatefulWidget {
  const CancelMissionSheet({required this.mission, super.key});

  final MissionDetail mission;

  @override
  ConsumerState<CancelMissionSheet> createState() => _CancelMissionSheetState();
}

class _CancelMissionSheetState extends ConsumerState<CancelMissionSheet>
    with FormSubmissionMixin<CancelMissionSheet> {
  final TextEditingController _reason = TextEditingController();
  final TextEditingController _details = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String reason = _reason.text.trim();
    if (reason.length < ContentLimits.reasonMinLength) {
      showFormError(
        'Indiquez un motif d’au moins ${ContentLimits.reasonMinLength} '
        'caractères.',
      );
      return;
    }

    final String details = _details.text.trim();
    final CancellationResult? result = await submit<CancellationResult>(
      () => ref
          .read(missionRepositoryProvider)
          .cancel(
            widget.mission.id,
            reason: reason,
            details: details.isEmpty ? null : details,
          ),
    );

    if (!mounted) {
      return;
    }

    if (result != null) {
      invalidateAfterMissionWrite(ref, widget.mission.id);
      Navigator.of(context).pop();
      // Le verdict du service, tel quel — tardive ou non (scénario 3.2).
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }

    // « Transition de mission invalide » : le statut a changé entre l'affichage
    // et l'envoi. Insister serait mentir — on recharge la réalité.
    if (lastFailure?.message.startsWith('Transition de mission invalide') ??
        false) {
      final String message = lastFailure!.message;
      invalidateAfterMissionWrite(ref, widget.mission.id);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    // Le seuil vient du service, lu au démarrage — jamais d'une constante.
    final Duration notice = ref
        .watch(publicSettingsProvider)
        .cancellationNotice;
    final bool lateWarning = isLateCancellation(
      scheduledAt: widget.mission.scheduledAt,
      now: DateTime.now(),
      notice: notice,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Annuler la mission', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            widget.mission.pack.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (lateWarning) ...<Widget>[
            const SizedBox(height: 12),
            // AVANT l'envoi, pas après : le service accepte puis marque.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cette annulation sera enregistrée comme tardive.',
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            maxLength: ContentLimits.reasonMaxLength,
            enabled: !isSubmitting,
            decoration: InputDecoration(
              labelText: 'Motif (obligatoire)',
              border: const OutlineInputBorder(),
              errorText: fieldErrors['reason'],
            ),
            onChanged: (String _) => clearFieldError('reason'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _details,
            maxLength: ContentLimits.cancellationDetailsMaxLength,
            maxLines: 3,
            enabled: !isSubmitting,
            decoration: const InputDecoration(
              labelText: 'Précisions (facultatif)',
              border: OutlineInputBorder(),
            ),
          ),
          if (formError case final String message) ...<Widget>[
            const SizedBox(height: 8),
            Text(message, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: isSubmitting ? null : _submit,
            child: isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Confirmer l’annulation'),
          ),
          TextButton(
            onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Garder la mission'),
          ),
        ],
      ),
    );
  }
}
