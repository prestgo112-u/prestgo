// Onglets de « Planning et demandes » côté prestataire (T169, FR-038).
//
// Même mécanique que les onglets client : un onglet = **un appel**, statuts
// joints par des virgules dans le paramètre `status`. La différence est le tri —
// `scheduledAt` **croissant**, ce qui arrive d'abord en premier — servi tel quel
// par le service et jamais recalculé.
//
// `MissionStatus` vient du domaine de la fonctionnalité `missions`, commune aux
// deux rôles : c'est le partage que recommande la règle `cross_feature_data`
// (un modèle de domaine, jamais un dépôt).

import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';

/// Les trois onglets de l'écran planning du prestataire.
enum ProviderMissionTab {
  requests('Demandes', <MissionStatus>[
    MissionStatus.pendingProvider,
  ], 'Aucune demande en attente'),
  planning('Planning', <MissionStatus>[
    MissionStatus.confirmed,
    MissionStatus.inProgress,
  ], 'Aucune mission planifiée'),
  history('Historique', <MissionStatus>[
    MissionStatus.completed,
    MissionStatus.closed,
    MissionStatus.cancelled,
  ], 'Aucune mission passée');

  const ProviderMissionTab(this.label, this.statuses, this.emptyMessage);

  final String label;

  /// Statuts demandés au service — joints par des virgules, jamais en
  /// plusieurs appels.
  final List<MissionStatus> statuses;

  /// Message de l'état vide, propre à l'onglet.
  final String emptyMessage;
}
