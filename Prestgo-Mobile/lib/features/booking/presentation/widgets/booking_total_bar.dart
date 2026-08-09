// Barre de total, ancrée en bas des étapes de réservation.
//
// Elle affiche le prix **et** la durée, recalculés en continu (FR-030). Les deux
// comptent : le prix décide de l'achat, la durée décide des créneaux qui resteront
// proposables à l'étape suivante.

import 'package:flutter/material.dart';
import 'package:prestgo_mobile/core/format/money.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_draft.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_rules.dart';

class BookingTotalBar extends StatelessWidget {
  const BookingTotalBar({
    required this.draft,
    required this.label,
    required this.onContinue,
    super.key,
  });

  final BookingDraft draft;
  final String label;

  /// `null` désactive le bouton — étape encore incomplète.
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    Money.format(draft.totalPrice),
                    style: theme.textTheme.titleLarge,
                  ),
                  Text(
                    BookingRules.formatDuration(draft.totalDurationMinutes),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: onContinue,
              style: FilledButton.styleFrom(minimumSize: const Size(170, 52)),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
