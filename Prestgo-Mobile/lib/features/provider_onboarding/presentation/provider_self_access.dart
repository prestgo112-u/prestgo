// Point d'accès de l'espace prestataire au dépôt du dossier (porte G5).
//
// La couche `data/` d'une fonctionnalité lui appartient : `provider_space`
// n'importe pas le dépôt de `provider_onboarding`, il passe par CE fichier de
// présentation — le même principe que `provider_overview_controller`, qui
// relaie déjà les écritures d'identité.
//
// Ré-exporter plutôt que relayer méthode par méthode : l'offre, le portfolio
// et les absences sont une dizaine d'opérations sans état partagé — les
// recopier dans un contrôleur n'ajouterait que de la distance. L'aperçu du
// dossier, lui, garde son relais dédié parce qu'il porte UN état partagé.

export 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart'
    show
        AvailabilitiesUpdate,
        ProviderSelfRepository,
        ZonesUpdate,
        providerSelfRepositoryProvider;
