// Ouverture et suivi de litige (T134, FR-100).
//
// Volontairement minimaliste en V1 (data-model §11) : un formulaire d'ouverture —
// motif obligatoire — puis un suivi qui affiche l'état et les échanges tels que le
// service les rend. La mission passe en `disputed` côté service : le détail est
// invalidé pour refléter le nouveau statut.
//
// L'écran de suivi ne peut être atteint qu'avec l'identifiant rendu à l'ouverture
// (le détail de mission ne porte pas de référence de litige) : après l'ouverture,
// le suivi s'affiche dans la foulée ; plus tard, la mission `disputed` affiche un
// bandeau d'information sans relecture dédiée.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/disputes/data/dispute_repository.dart';
import 'package:prestgo_mobile/features/disputes/domain/dispute.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_providers.dart';

/// Ouverture d'un litige sur une mission.
class DisputeScreen extends ConsumerStatefulWidget {
  const DisputeScreen({required this.missionId, super.key});

  final String missionId;

  @override
  ConsumerState<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends ConsumerState<DisputeScreen>
    with FormSubmissionMixin<DisputeScreen> {
  final TextEditingController _reason = TextEditingController();

  /// Litige rendu par l'ouverture — l'écran bascule alors en suivi.
  Dispute? _opened;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String reason = _reason.text.trim();
    if (reason.length < ContentLimits.reasonMinLength) {
      showFormError(
        'Décrivez le problème en au moins ${ContentLimits.reasonMinLength} '
        'caractères.',
      );
      return;
    }

    final Dispute? dispute = await submit<Dispute>(
      () => ref
          .read(disputeRepositoryProvider)
          .open(missionId: widget.missionId, reason: reason),
    );

    if (dispute != null && mounted) {
      // La mission vient de passer en `disputed` : ses lectures sont fausses.
      invalidateAfterMissionWrite(ref, widget.missionId);
      setState(() => _opened = dispute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Dispute? opened = _opened;

    return Scaffold(
      appBar: AppBar(
        title: Text(opened == null ? 'Ouvrir un litige' : 'Suivi du litige'),
      ),
      body: opened == null ? _buildForm(context) : DisputeView(dispute: opened),
    );
  }

  Widget _buildForm(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Décrivez le problème rencontré sur cette mission. Notre équipe '
            'examinera votre demande et reviendra vers vous.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _reason,
            maxLength: ContentLimits.reasonMaxLength,
            maxLines: 5,
            enabled: !isSubmitting,
            decoration: InputDecoration(
              labelText: 'Motif du litige (obligatoire)',
              border: const OutlineInputBorder(),
              errorText: fieldErrors['reason'],
            ),
            onChanged: (String _) => clearFieldError('reason'),
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
                : const Text('Ouvrir le litige'),
          ),
        ],
      ),
    );
  }
}

/// Suivi — état et échanges, en lecture seule.
class DisputeView extends StatelessWidget {
  const DisputeView({required this.dispute, super.key});

  final Dispute dispute;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: ListTile(
            leading: Icon(Icons.gavel, color: theme.colorScheme.tertiary),
            title: const Text('Litige enregistré'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (dispute.status.isNotEmpty) Text('État : ${dispute.status}'),
                if (dispute.createdAt case final DateTime createdAt)
                  Text('Ouvert le ${DateLabels.dayAndTime(createdAt)}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Motif', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(dispute.reason),
        if (dispute.messages.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Text('Échanges', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          for (final DisputeMessage message in dispute.messages)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(message.message),
                      if (message.createdAt case final DateTime createdAt)
                        Text(
                          DateLabels.dayAndTime(createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 16),
        Text(
          'Vous serez averti de chaque évolution de ce litige. La mission '
          'reste consultable pendant son traitement.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
