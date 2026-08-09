// Réexport du catalogue partagé — voir lib/shared/catalog/catalog.dart.
//
// Les modèles ont déménagé dans `lib/shared/` quand l'onboarding prestataire (US4)
// s'est mis à lire le même catalogue : la porte G5 interdit à la surface
// prestataire d'importer `features/search`. Ce réexport garde l'API de la
// fonctionnalité de recherche inchangée.

export 'package:prestgo_mobile/shared/catalog/catalog.dart';
