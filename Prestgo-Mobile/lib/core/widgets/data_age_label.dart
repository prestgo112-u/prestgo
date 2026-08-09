// Âge des données affichées — « Mis à jour il y a N min » (T232, FR-096).
//
// Le mode hors ligne ne montre jamais une donnée sans dire de QUAND elle
// date : un agenda d'hier présenté comme frais ferait rater une mission. La
// date vient du `fetchedAt` du cache (data-model §12) — jamais d'une horloge
// d'affichage.

import 'package:flutter/material.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

/// « Mis à jour à l'instant », « il y a N min », « il y a N h », ou la date
/// complète au-delà de 24 h — l'imprécision croît avec l'âge, comme l'usage.
String dataAgeLabel(DateTime fetchedAt, {DateTime? now}) {
  final Duration age = (now ?? DateTime.now()).difference(fetchedAt);
  if (age < const Duration(minutes: 1)) {
    return 'Mis à jour à l’instant';
  }
  if (age < const Duration(hours: 1)) {
    return 'Mis à jour il y a ${age.inMinutes} min';
  }
  if (age < const Duration(hours: 24)) {
    return 'Mis à jour il y a ${age.inHours} h';
  }
  return 'Mis à jour le ${DateLabels.dayAndTime(fetchedAt.toLocal())}';
}

class DataAgeLabel extends StatelessWidget {
  const DataAgeLabel({required this.fetchedAt, super.key, this.now});

  final DateTime fetchedAt;

  /// Horloge injectable — les tests figent le temps.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          Icons.schedule_outlined,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(
          dataAgeLabel(fetchedAt, now: now),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
