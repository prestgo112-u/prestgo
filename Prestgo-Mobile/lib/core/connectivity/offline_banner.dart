// Bannière hors ligne PERMANENTE, câblée à l'état réseau (T233, FR-095).
//
// Montée par le `builder` du `MaterialApp` : elle coiffe TOUS les écrans, y
// compris ceux qui n'y pensent pas — c'est ce qui la rend permanente. La
// présentation vit dans `core/widgets/offline_banner.dart` ; ce fichier-ci ne
// fait que le câblage : état réseau d'un côté, horodatage des dernières
// données reçues de l'autre.
//
// L'horodatage est enregistré par la couche réseau à CHAQUE réponse réussie
// (`recordDataTimestamp`) : « Données du 12 mars à 09:14 » dit à l'utilisateur
// jusqu'à quand ce qu'il consulte était vrai.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/widgets/offline_banner.dart';

/// Date de la dernière réponse réussie du service.
class LastDataTimestamp extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void record(DateTime timestamp) => state = timestamp;
}

final NotifierProvider<LastDataTimestamp, DateTime?> lastDataTimestampProvider =
    NotifierProvider<LastDataTimestamp, DateTime?>(LastDataTimestamp.new);

/// Coiffe [child] de la bannière tant que le réseau manque.
///
/// L'état réseau indisponible (greffon absent, plateforme muette) est traité
/// comme EN LIGNE : la connectivité est un filtre d'ergonomie, pas une preuve —
/// les vraies erreurs réseau restent traitées par `ApiException.isNetwork`.
class GlobalOfflineBanner extends ConsumerWidget {
  const GlobalOfflineBanner({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool online = ref.watch(isOnlineProvider).value ?? true;
    if (online) {
      return child;
    }

    final DateTime? lastData = ref.watch(lastDataTimestampProvider);
    return Column(
      children: <Widget>[
        OfflineBanner(
          detail: lastData == null
              ? null
              : 'Données du ${DateLabels.dayAndTime(lastData.toLocal())}',
        ),
        Expanded(child: child),
      ],
    );
  }
}
