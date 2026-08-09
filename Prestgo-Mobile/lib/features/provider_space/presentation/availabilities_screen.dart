// Agenda hebdomadaire de l'espace prestataire (T213, FR-055).
//
// Même délégation que pour les zones (T212) : la grille de l'étape P6 porte
// déjà tout le contrat — lecture dédiée (`GET /providers/me/availabilities`,
// miroir exact du PUT), heures `HH:MM` sans conversion de fuseau, contrôles
// locaux avant l'envoi, écriture par remplacement intégral. Une seule grille,
// une seule vérité.

import 'package:flutter/material.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/availabilities_step_screen.dart';

class ProviderAvailabilitiesScreen extends StatelessWidget {
  const ProviderAvailabilitiesScreen({super.key});

  @override
  Widget build(BuildContext context) => const AvailabilitiesStepScreen();
}
