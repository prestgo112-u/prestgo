// Dialogue de motif — refus et annulation côté prestataire (T173, FR-044,
// FR-045).
//
// Un seul dialogue pour les deux actions : le motif (3 caractères au minimum,
// contrôlé AVANT l'envoi — le service le refuserait de toute façon) et, pour
// l'annulation seulement, l'avertissement de tardiveté. L'avertissement se
// donne **avant** l'appel — seuil lu auprès du service (porte G3) — parce que
// le service, lui, n'avertit pas : il accepte et marque `late`.
//
// Le bouton de renoncement s'appelle « Retour », pas « Annuler » : dans un
// dialogue qui annule une mission, deux « Annuler » aux effets opposés seraient
// un piège.

import 'package:flutter/material.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

/// Demande un motif ; rend `null` si l'utilisateur renonce.
///
/// [warning] s'affiche en bandeau d'alerte au-dessus du champ — l'avertissement
/// de tardiveté d'une annulation, typiquement.
Future<String?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? warning,
}) => showDialog<String>(
  context: context,
  builder: (BuildContext context) =>
      _ReasonDialog(title: title, confirmLabel: confirmLabel, warning: warning),
);

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.confirmLabel,
    this.warning,
  });

  final String title;
  final String confirmLabel;
  final String? warning;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final TextEditingController _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final String reason = _reason.text.trim();
    // Le contrôle local reproduit le refus certain du service (FR-044) : un
    // motif trop court ne part jamais sur le réseau (scénario 5.4).
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
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.warning case final String warning) ...<Widget>[
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
                      warning,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _reason,
            autofocus: true,
            maxLength: ContentLimits.reasonMaxLength,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Motif (obligatoire)',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onChanged: (String _) => setState(() => _error = null),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Retour'),
        ),
        FilledButton(onPressed: _confirm, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
