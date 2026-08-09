// Frise chronologique d'une mission (T129, FR-039).
//
// La frise fusionne deux flux de `GET /missions/{id}/history` : les changements
// de statut et les reports passés, intercalés par date. L'ordre affiché est
// chronologique — on lit une histoire du début à la fin.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_history.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_providers.dart';

class MissionHistoryScreen extends ConsumerWidget {
  const MissionHistoryScreen({required this.missionId, super.key});

  final String missionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MissionHistory> history = ref.watch(
      missionHistoryProvider(missionId),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Historique de la mission')),
      body: history.when(
        loading: () => const LoadingView(label: 'Chargement de l’historique…'),
        error: (Object error, StackTrace _) => ErrorView(
          message: error is ApiException
              ? error.message
              : ApiFallbackMessages.unknown,
          onRetry: () => ref.invalidate(missionHistoryProvider(missionId)),
        ),
        data: (MissionHistory history) => history.isEmpty
            ? const EmptyView(
                icon: Icons.history,
                title: 'Aucun évènement',
                description: 'L’historique de cette mission est vide.',
              )
            : MissionHistoryView(history: history),
      ),
    );
  }
}

/// La frise elle-même — réutilisable hors de l'écran (aperçu dans le détail).
class MissionHistoryView extends StatelessWidget {
  const MissionHistoryView({required this.history, super.key});

  final MissionHistory history;

  @override
  Widget build(BuildContext context) {
    final List<_TimelineEvent> events = _merge(history);

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: events.length,
      itemBuilder: (BuildContext context, int index) => _TimelineTile(
        event: events[index],
        isFirst: index == 0,
        isLast: index == events.length - 1,
      ),
    );
  }

  /// Fusionne statuts et reports en un seul fil, du plus ancien au plus récent.
  static List<_TimelineEvent> _merge(MissionHistory history) {
    final List<_TimelineEvent> events = <_TimelineEvent>[
      for (final MissionHistoryEntry entry in history.statusHistory)
        _TimelineEvent(
          date: entry.createdAt,
          title: entry.label,
          subtitle: entry.reason,
          icon: _statusIcon(entry.newStatus),
        ),
      for (final RescheduleTrace trace in history.reschedules)
        _TimelineEvent(
          date: trace.createdAt,
          title: 'Report demandé',
          subtitle: <String>[
            if (trace.newScheduledAt case final DateTime newDate)
              'Nouvelle date proposée : ${DateLabels.dayAndTime(newDate)}',
            if (trace.reason case final String reason) reason,
          ].join('\n'),
          icon: Icons.update,
        ),
    ];

    // Tri stable par date ; les évènements sans date restent en fin de liste,
    // dans l'ordre où le service les a rendus.
    events.sort((_TimelineEvent a, _TimelineEvent b) {
      final DateTime? left = a.date;
      final DateTime? right = b.date;
      if (left == null || right == null) {
        return (left == null ? 1 : 0) - (right == null ? 1 : 0);
      }
      return left.compareTo(right);
    });
    return events;
  }

  static IconData _statusIcon(MissionStatus status) => switch (status) {
    MissionStatus.pendingProvider => Icons.hourglass_top,
    MissionStatus.confirmed => Icons.check_circle_outline,
    MissionStatus.inProgress => Icons.play_circle_outline,
    MissionStatus.completed => Icons.task_alt,
    MissionStatus.disputed => Icons.gavel,
    MissionStatus.cancelled => Icons.cancel_outlined,
    MissionStatus.closed => Icons.lock_outline,
    MissionStatus.draft || MissionStatus.unknown => Icons.circle_outlined,
  };
}

class _TimelineEvent {
  const _TimelineEvent({
    required this.date,
    required this.title,
    required this.icon,
    this.subtitle,
  });

  final DateTime? date;
  final String title;
  final String? subtitle;
  final IconData icon;
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.event,
    required this.isFirst,
    required this.isLast,
  });

  final _TimelineEvent event;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? subtitle = event.subtitle;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Le rail : un trait continu, interrompu aux extrémités.
          SizedBox(
            width: 56,
            child: Column(
              children: <Widget>[
                Expanded(child: _RailSegment(visible: !isFirst)),
                Icon(event.icon, color: theme.colorScheme.primary),
                Expanded(child: _RailSegment(visible: !isLast)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(event.title, style: theme.textTheme.titleSmall),
                  if (event.date case final DateTime date)
                    Text(
                      DateLabels.dayAndTime(date),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (subtitle != null && subtitle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle, style: theme.textTheme.bodyMedium),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

class _RailSegment extends StatelessWidget {
  const _RailSegment({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 2,
      color: visible
          ? Theme.of(context).colorScheme.outlineVariant
          : Colors.transparent,
    ),
  );
}
