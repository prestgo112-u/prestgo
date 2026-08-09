// Étape 4 — instructions (T114, FR-029).
//
// Facultatives, 500 caractères au plus. Le compteur est affiché en permanence, et la
// saisie **bloquée** au plafond : le service refuserait au-delà, et découvrir la
// limite au moment de confirmer serait la découvrir trop tard.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

class InstructionsStep extends StatefulWidget {
  const InstructionsStep({
    required this.initialValue,
    required this.onChanged,
    super.key,
  });

  final String? initialValue;
  final ValueChanged<String?> onChanged;

  @override
  State<InstructionsStep> createState() => _InstructionsStepState();
}

class _InstructionsStepState extends State<InstructionsStep> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    maxLines: 3,
    maxLength: ContentLimits.bookingInstructionsMaxLength,
    // Le plafond est appliqué à la frappe, pas au moment d'envoyer.
    inputFormatters: <TextInputFormatter>[
      LengthLimitingTextInputFormatter(
        ContentLimits.bookingInstructionsMaxLength,
      ),
    ],
    decoration: const InputDecoration(
      labelText: 'Instructions (facultatif)',
      hintText: 'Portail bleu, sonner deux fois, étage…',
      border: OutlineInputBorder(),
      alignLabelWithHint: true,
    ),
    onChanged: (String value) =>
        widget.onChanged(value.trim().isEmpty ? null : value),
  );
}
