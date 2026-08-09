// Ligne de mission côté prestataire — tableau de bord et planning (T167, T169).
//
// Les champs utiles sont ceux du client de la mission : `clientName`, le lieu,
// la formule, l'horaire, le montant. `providerName`, c'est soi-même — jamais
// affiché ici. Une demande en attente porte son compte à rebours d'expiration
// (FR-043). L'ordre d'affichage est celui de la liste reçue : le tri croissant
// du service, jamais recalculé (FR-038).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/format/money.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_list_item.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/widgets/pending_expiry_badge.dart';

class ProviderMissionTile extends StatelessWidget {
  const ProviderMissionTile({required this.mission, super.key});

  final MissionListItem mission;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? scheduledAt = mission.scheduledAt;

    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        child: Text(
          mission.clientName.isEmpty
              ? '?'
              : mission.clientName.characters.first.toUpperCase(),
        ),
      ),
      title: Text(
        mission.packTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            mission.clientName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (scheduledAt != null)
            Text(
              '${DateLabels.dayAndTime(scheduledAt)} · ${mission.locality}',
              style: theme.textTheme.bodySmall,
            ),
          _StatusLine(mission: mission),
          if (mission.status == MissionStatus.pendingProvider)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: PendingExpiryBadge(createdAt: mission.createdAt),
            ),
        ],
      ),
      // « — » quand le montant n'existe pas, jamais « 0 XOF » (data-model §5.1).
      trailing: Text(
        Money.formatOrAbsent(mission.quotedAmount),
        style: theme.textTheme.labelLarge,
      ),
      isThreeLine: true,
      onTap: () => context.push(Routes.missionDetailFor(mission.id)),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.mission});

  final MissionListItem mission;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color color = switch (mission.status) {
      MissionStatus.pendingProvider => scheme.tertiary,
      MissionStatus.confirmed || MissionStatus.inProgress => scheme.primary,
      MissionStatus.completed || MissionStatus.closed => scheme.secondary,
      MissionStatus.cancelled || MissionStatus.disputed => scheme.error,
      MissionStatus.draft || MissionStatus.unknown => scheme.outline,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        mission.statusLabel,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
