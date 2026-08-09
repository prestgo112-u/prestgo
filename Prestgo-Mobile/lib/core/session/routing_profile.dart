// Ce dont l'aiguillage a besoin d'un compte — et rien de plus (data-model §1.4).
//
// Ces types vivent dans le socle et non dans une fonctionnalité : la session, le
// routeur et le profil s'en servent tous les trois. `features/profile` les réutilise
// plutôt que de les redéclarer (T061).
//
// La décision de routage elle-même est dans `lib/app/router_guard.dart` : le socle
// ne connaît aucune route.

/// Statut du compte (data-model §1.2).
enum UserStatus {
  draft,
  pending,
  active,
  rejected,
  suspended,
  deleted;

  static UserStatus parse(String? raw) => switch (raw) {
    'draft' => UserStatus.draft,
    'pending' => UserStatus.pending,
    'active' => UserStatus.active,
    'rejected' => UserStatus.rejected,
    'suspended' => UserStatus.suspended,
    'deleted' => UserStatus.deleted,
    _ => UserStatus.pending,
  };

  /// L'espace client s'ouvre dès que le compte est actif, **indépendamment** de
  /// `hasClientProfile` — que des comptes historiques ont à `false`.
  bool get isActive => this == UserStatus.active;
}

/// Avancement du dossier prestataire (data-model §1.4).
enum ProviderValidationStatus {
  profileIncomplete,
  pendingReview,
  changesRequested,
  rejected,
  suspended,
  approved;

  static ProviderValidationStatus? parse(String? raw) => switch (raw) {
    'profile_incomplete' => ProviderValidationStatus.profileIncomplete,
    'pending_review' => ProviderValidationStatus.pendingReview,
    'changes_requested' => ProviderValidationStatus.changesRequested,
    'rejected' => ProviderValidationStatus.rejected,
    'suspended' => ProviderValidationStatus.suspended,
    'approved' => ProviderValidationStatus.approved,
    _ => null,
  };

  String get wireValue => switch (this) {
    ProviderValidationStatus.profileIncomplete => 'profile_incomplete',
    ProviderValidationStatus.pendingReview => 'pending_review',
    ProviderValidationStatus.changesRequested => 'changes_requested',
    ProviderValidationStatus.rejected => 'rejected',
    ProviderValidationStatus.suspended => 'suspended',
    ProviderValidationStatus.approved => 'approved',
  };

  /// Seul `approved` ouvre l'espace prestataire.
  bool get opensProviderSpace => this == ProviderValidationStatus.approved;
}

/// Les deux seules informations qui pilotent l'aiguillage.
///
/// Le champ `roles` (rôles d'administration, vide pour les comptes ordinaires) en
/// est délibérément absent : il ne doit **jamais** entrer dans la décision.
class RoutingProfile {
  const RoutingProfile({
    required this.userStatus,
    required this.hasProviderProfile,
    this.providerValidationStatus,
  });

  final UserStatus userStatus;
  final bool hasProviderProfile;
  final ProviderValidationStatus? providerValidationStatus;

  bool get isActive => userStatus.isActive;

  @override
  bool operator ==(Object other) =>
      other is RoutingProfile &&
      other.userStatus == userStatus &&
      other.hasProviderProfile == hasProviderProfile &&
      other.providerValidationStatus == providerValidationStatus;

  @override
  int get hashCode =>
      Object.hash(userStatus, hasProviderProfile, providerValidationStatus);

  @override
  String toString() =>
      'RoutingProfile(${userStatus.name}, prestataire: $hasProviderProfile, '
      '${providerValidationStatus?.name})';
}
