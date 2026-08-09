// Compte à rebours d'expiration d'une demande en attente (T172, FR-043).
//
// Une mission `pending_provider` non traitée expire automatiquement au bout du
// délai en vigueur (`missionPendingExpiryHours`, lu auprès du service au
// démarrage — porte G3) : « Il vous reste 6 h pour répondre » est ce qui pousse
// à répondre avant que le service ne tranche à la place du prestataire.
//
// Le badge se réévalue chaque demi-minute tant qu'il est affiché ; le délai
// écoulé, il annonce l'expiration imminente — il ne la CONSTATE jamais : c'est
// une tâche planifiée du service qui fait expirer, pas l'application (porte G1).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/core_providers.dart';

class PendingExpiryBadge extends ConsumerStatefulWidget {
  const PendingExpiryBadge({required this.createdAt, super.key});

  /// Date de création de la demande ; `null` laisse le badge muet plutôt que
  /// d'afficher un compte à rebours inventé.
  final DateTime? createdAt;

  @override
  ConsumerState<PendingExpiryBadge> createState() => _PendingExpiryBadgeState();
}

class _PendingExpiryBadgeState extends ConsumerState<PendingExpiryBadge> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (Timer _) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DateTime? createdAt = widget.createdAt;
    if (createdAt == null) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final DateTime expiresAt = createdAt.add(
      ref.watch(publicSettingsProvider).pendingExpiry,
    );
    final Duration remaining = expiresAt.difference(DateTime.now());
    final bool urgent = remaining.inHours < 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.hourglass_bottom,
          size: 14,
          color: urgent ? theme.colorScheme.error : theme.colorScheme.tertiary,
        ),
        const SizedBox(width: 4),
        Text(
          _label(remaining),
          style: theme.textTheme.labelSmall?.copyWith(
            color: urgent
                ? theme.colorScheme.error
                : theme.colorScheme.tertiary,
          ),
        ),
      ],
    );
  }

  static String _label(Duration remaining) {
    if (remaining.isNegative) {
      return 'Expiration imminente';
    }
    if (remaining.inHours >= 1) {
      return 'Il vous reste ${remaining.inHours} h pour répondre';
    }
    return 'Il vous reste ${remaining.inMinutes} min pour répondre';
  }
}
