// Justificatifs de l'espace prestataire (T216, FR-057 à FR-059).
//
// L'écran de l'étape P7 porte déjà toute la vie du justificatif après
// approbation : états par ligne (en attente, validé, refusé), motif de refus
// en évidence, historique des versions replié, **re-dépôt retiré quand le
// document est validé** (scénario 8.5), et relecture de l'aperçu après chaque
// dépôt — un dépôt en `changes_requested` repasse le dossier en vérification
// tout seul. Le déléguer garantit qu'aucune de ces règles ne divergera.

import 'package:flutter/material.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/documents_step_screen.dart';

class ProviderDocumentsScreen extends StatelessWidget {
  const ProviderDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) => const DocumentsStepScreen();
}
