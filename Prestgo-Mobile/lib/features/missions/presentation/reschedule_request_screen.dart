// Proposition de report (T131, FR-047, scénarios 3.3 et 3.5).
//
// Une seule demande en attente par mission : l'écran n'est atteignable que si le
// détail n'en porte aucune — et si le service en trouve quand même une (course
// entre deux appareils), le 400 ferme l'écran et recharge la réalité.
//
// La validation locale reproduit les refus **prévisibles** du service — date dans
// le passé proche (délai minimum lu au démarrage, porte G3), date identique — pour
// épargner un aller-retour. Les refus qui dépendent de l'agenda du prestataire
// (« ne travaille pas sur ce créneau », « déjà une mission ») ne peuvent être
// connus qu'après l'appel : le sélecteur reste ouvert et le message s'affiche.
//
// L'écran sert aussi de **contre-proposition** (scénario 3.5) : quand
// l'acceptation échoue sur un créneau devenu indisponible, il s'ouvre avec une
// bannière qui explique pourquoi.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/missions/data/reschedule_repository.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_detail.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_providers.dart';
import 'package:prestgo_mobile/features/missions/presentation/provider_message_rewriter.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';

/// Ouvre l'écran de proposition — [notice] est la bannière de contre-proposition.
Future<void> openRescheduleRequest(
  BuildContext context, {
  required MissionDetail mission,
  String? notice,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (BuildContext context) =>
        RescheduleRequestScreen(mission: mission, notice: notice),
  ),
);

class RescheduleRequestScreen extends ConsumerStatefulWidget {
  const RescheduleRequestScreen({
    required this.mission,
    this.notice,
    super.key,
  });

  final MissionDetail mission;

  /// Contexte affiché en tête — typiquement « le créneau accepté n'est plus
  /// disponible, proposez une autre date ».
  final String? notice;

  @override
  ConsumerState<RescheduleRequestScreen> createState() =>
      _RescheduleRequestScreenState();
}

class _RescheduleRequestScreenState
    extends ConsumerState<RescheduleRequestScreen>
    with FormSubmissionMixin<RescheduleRequestScreen> {
  final TextEditingController _reason = TextEditingController();
  DateTime? _newDate;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime initial = _newDate ?? widget.mission.scheduledAt ?? now;
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) {
      return;
    }
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) {
      return;
    }
    setState(() {
      _newDate = DateTime(day.year, day.month, day.day, time.hour, time.minute);
      showFormError(null);
    });
  }

  /// Refus prévisibles, devancés localement — le service reste l'autorité.
  String? _localCheck(DateTime candidate) {
    final DateTime? current = widget.mission.scheduledAt;
    if (current != null && candidate.isAtSameMomentAs(current)) {
      return 'La nouvelle date est identique à la date actuelle.';
    }
    final Duration lead = ref.read(publicSettingsProvider).minLeadTime;
    if (candidate.isBefore(DateTime.now().add(lead))) {
      return 'La nouvelle date doit être au moins ${lead.inMinutes} minutes '
          'dans le futur.';
    }
    return null;
  }

  Future<void> _submit() async {
    final DateTime? newDate = _newDate;
    if (newDate == null) {
      showFormError('Choisissez une nouvelle date et une heure.');
      return;
    }
    final String? localError = _localCheck(newDate);
    if (localError != null) {
      showFormError(localError);
      return;
    }

    final String reason = _reason.text.trim();
    final RescheduleSubmission? submission = await submit<RescheduleSubmission>(
      () => ref
          .read(rescheduleRepositoryProvider)
          .propose(
            widget.mission.id,
            newDate: newDate,
            reason: reason.isEmpty ? null : reason,
          ),
    );

    if (!mounted) {
      return;
    }

    if (submission != null) {
      invalidateAfterMissionWrite(ref, widget.mission.id);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(submission.message)));
      return;
    }

    // Course perdue : une demande est déjà en attente (autre appareil, autre
    // partie). L'écran n'a plus de raison d'être — la réalité est rechargée.
    if (lastFailure?.message ==
        'Une demande de report est déjà en attente de réponse') {
      final String message = lastFailure!.message;
      invalidateAfterMissionWrite(ref, widget.mission.id);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
    // Les autres 400 (créneau hors agenda, absence, mission déjà prise) restent
    // affichés en bannière : le sélecteur est toujours là pour corriger.
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? current = widget.mission.scheduledAt;
    final DateTime? candidate = _newDate;

    return Scaffold(
      appBar: AppBar(title: const Text('Proposer un report')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (widget.notice case final String notice) ...<Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  notice,
                  style: TextStyle(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Text(widget.mission.pack.title, style: theme.textTheme.titleMedium),
            if (current != null)
              Text(
                'Actuellement prévue le ${DateLabels.dayAndTime(current)}.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: isSubmitting ? null : _pickDate,
              icon: const Icon(Icons.event),
              label: Text(
                candidate == null
                    ? 'Choisir la nouvelle date et l’heure'
                    : DateLabels.dayAndTime(candidate),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              maxLength: ContentLimits.reasonMaxLength,
              maxLines: 2,
              enabled: !isSubmitting,
              decoration: InputDecoration(
                labelText: 'Motif (facultatif)',
                border: const OutlineInputBorder(),
                errorText: fieldErrors['reason'],
              ),
              onChanged: (String _) => clearFieldError('reason'),
            ),
            if (formError case final String message) ...<Widget>[
              const SizedBox(height: 8),
              // « Le prestataire ne travaille pas sur ce créneau » désigne le
              // lecteur quand c'est LUI qui propose : reformulé à la deuxième
              // personne (FR-049), le texte serveur restant l'autorité du fond.
              Text(
                availabilityMessage(
                  message,
                  asProvider:
                      ref.watch(meControllerProvider).value?.providerId ==
                      widget.mission.provider.id,
                ),
                style: TextStyle(color: theme.colorScheme.error),
              ),
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
                  : const Text('Envoyer la demande'),
            ),
            const SizedBox(height: 8),
            Text(
              'L’autre partie devra accepter cette proposition pour que la '
              'mission soit déplacée.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
