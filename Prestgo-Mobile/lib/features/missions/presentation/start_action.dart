// Fenêtre de démarrage (T171, FR-042, scénario 5.3).
//
// « Démarrer » est indisponible tant que la fenêtre en vigueur n'est pas
// ouverte, et le bouton dit QUAND il le sera — un bouton grisé muet ressemble à
// un défaut. Le seuil est lu auprès du service au démarrage (porte G3), jamais
// figé : si le back-office resserre la fenêtre, le message d'erreur du service
// — interpolé avec la valeur réellement en vigueur — reste l'autorité, et
// l'écran l'affiche tel quel.
//
// Une minuterie réévalue l'ouverture chaque demi-minute : la fenêtre s'ouvre
// pendant que l'écran est affiché — typiquement en attendant sur place — sans
// exiger de geste de rafraîchissement.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

class StartMissionButton extends ConsumerStatefulWidget {
  const StartMissionButton({
    required this.scheduledAt,
    required this.busy,
    required this.onStart,
    super.key,
  });

  /// Horaire prévu de la mission ; `null` laisse le bouton ouvert — le service
  /// reste l'autorité (porte G1).
  final DateTime? scheduledAt;

  final bool busy;
  final VoidCallback onStart;

  @override
  ConsumerState<StartMissionButton> createState() => _StartMissionButtonState();
}

class _StartMissionButtonState extends ConsumerState<StartMissionButton> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Heure d'ouverture de la fenêtre, ou `null` si rien ne la contraint.
  DateTime? _opensAt() {
    final DateTime? scheduledAt = widget.scheduledAt;
    if (scheduledAt == null) {
      return null;
    }
    return scheduledAt.subtract(ref.read(publicSettingsProvider).startWindow);
  }

  bool _isOpen() {
    final DateTime? opensAt = _opensAt();
    return opensAt == null || !DateTime.now().isBefore(opensAt);
  }

  void _armTicker() {
    if (_isOpen()) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker ??= Timer.periodic(const Duration(seconds: 30), (Timer timer) {
      if (_isOpen()) {
        timer.cancel();
        _ticker = null;
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool open = _isOpen();
    _armTicker();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.icon(
          onPressed: open && !widget.busy ? widget.onStart : null,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Démarrer la mission'),
        ),
        if (!open)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _availabilityLabel(_opensAt()!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }

  /// « Disponible à partir de 12:00 » — la date n'apparaît que si la fenêtre
  /// s'ouvre un autre jour.
  static String _availabilityLabel(DateTime opensAt) {
    final DateTime now = DateTime.now();
    final bool sameDay =
        opensAt.year == now.year &&
        opensAt.month == now.month &&
        opensAt.day == now.day;
    return sameDay
        ? 'Disponible à partir de ${DateLabels.time(opensAt)}'
        : 'Disponible à partir du ${DateLabels.dayAndTime(opensAt)}';
  }
}
