// Zones d'intervention de l'espace prestataire (T212, FR-054).
//
// Après approbation, la gestion des zones est EXACTEMENT celle de l'étape P5
// de l'onboarding : pré-cochage par `GET /providers/me/zones`, écriture par
// remplacement intégral (`PUT`), plafond de 15 appliqué à la coche,
// confirmation avant de tout vider. Deux écrans divergeraient un jour sur une
// de ces règles — celui-ci délègue donc à l'étape, qui reste la seule vérité.

import 'package:flutter/material.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/zones_step_screen.dart';

class ProviderZonesScreen extends StatelessWidget {
  const ProviderZonesScreen({super.key});

  @override
  Widget build(BuildContext context) => const ZonesStepScreen();
}
