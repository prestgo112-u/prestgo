// Statuts de mission et onglets de la liste (T124, data-model §5.3).
//
// La machine à états vit côté service et n'est **pas** réimplémentée ici (porte
// G1) : ce fichier ne connaît que les statuts eux-mêmes et ce que l'écran en
// dérive — libellés, onglets, et les deux prédicats de confort qui évitent
// d'afficher une action que le service refuserait à coup sûr. En cas de
// désaccord, c'est toujours la réponse du service qui tranche.

/// Statut d'une mission, tel que le service le transporte.
enum MissionStatus {
  draft('draft', 'Brouillon'),
  pendingProvider('pending_provider', 'En attente du prestataire'),
  confirmed('confirmed', 'Confirmée'),
  inProgress('in_progress', 'En cours'),
  completed('completed', 'Terminée'),
  disputed('disputed', 'Litige en cours'),
  cancelled('cancelled', 'Annulée'),
  closed('closed', 'Clôturée'),

  /// Statut inconnu de cette version de l'application : affiché tel quel, aucune
  /// action proposée. Préférable à un plantage si le service évolue avant l'app.
  unknown('', '');

  const MissionStatus(this.apiValue, this.label);

  /// Forme transportée par l'API (`pending_provider`…) et par les filtres.
  final String apiValue;

  /// Libellé affiché.
  final String label;

  static MissionStatus parse(String? raw) {
    for (final MissionStatus status in MissionStatus.values) {
      if (status != MissionStatus.unknown && status.apiValue == raw) {
        return status;
      }
    }
    return MissionStatus.unknown;
  }

  /// Vrai sur un état d'où plus rien ne part (consultation seule).
  bool get isTerminal =>
      this == MissionStatus.cancelled || this == MissionStatus.closed;

  /// Le client peut annuler depuis `pending_provider` et `confirmed` — confort
  /// d'affichage seulement, le service reste l'autorité (§3.7).
  bool get clientMayCancel =>
      this == MissionStatus.pendingProvider || this == MissionStatus.confirmed;

  /// Seuls `pending_provider` et `confirmed` sont reprogrammables.
  bool get isReschedulable => clientMayCancel;
}

/// Les quatre onglets de « Mes missions » — chacun construit en **un appel**
/// grâce au filtre `status` multi-valeurs (écart n°7 clos, scénario 3.1).
enum MissionTab {
  upcoming('À venir', <MissionStatus>[
    MissionStatus.pendingProvider,
    MissionStatus.confirmed,
  ], 'Aucune mission à venir'),
  inProgress('En cours', <MissionStatus>[
    MissionStatus.inProgress,
  ], 'Aucune mission en cours'),
  completed('Terminées', <MissionStatus>[
    MissionStatus.completed,
    MissionStatus.closed,
  ], 'Aucune mission terminée'),
  cancelled('Annulées', <MissionStatus>[
    MissionStatus.cancelled,
  ], 'Aucune mission annulée');

  const MissionTab(this.label, this.statuses, this.emptyMessage);

  final String label;

  /// Statuts demandés au service — joints par des virgules dans le paramètre
  /// `status`, jamais en plusieurs appels.
  final List<MissionStatus> statuses;

  /// Message de l'état vide, propre à l'onglet (FR-037).
  final String emptyMessage;

  /// Valeur du paramètre `status` (`completed,closed`).
  String get statusFilter =>
      statuses.map((MissionStatus s) => s.apiValue).join(',');
}
