// P1 — Présentation du parcours « Devenir prestataire » (T150, FR-051).
//
// Purement informatif : aucun appel réseau. Les cinq étapes annoncées sont
// celles de la checklist du service ; les justificatifs exigés seront lus à
// l'étape correspondante (`requiredTypes`), jamais codés en dur — cet écran se
// contente d'annoncer qu'une pièce sera demandée.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';

class OnboardingIntroScreen extends StatelessWidget {
  const OnboardingIntroScreen({super.key});

  static const List<(IconData, String)>
  _stepDescriptions = <(IconData, String)>[
    (Icons.badge_outlined, 'Présentez-vous : nom public et description'),
    (Icons.handyman_outlined, 'Déclarez un service et sa formule tarifaire'),
    (Icons.map_outlined, 'Choisissez vos zones d’intervention'),
    (Icons.schedule_outlined, 'Renseignez vos disponibilités hebdomadaires'),
    (Icons.description_outlined, 'Déposez vos justificatifs'),
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Devenir prestataire')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Proposez vos services sur PRESTGO',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Votre dossier se construit en cinq étapes, dans l’ordre que '
              'vous voulez. Une fois complet, vous le soumettez et notre '
              'équipe le vérifie.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            for (final (int index, (IconData, String) step)
                in _stepDescriptions.indexed) ...<Widget>[
              ListTile(
                leading: CircleAvatar(child: Text('${index + 1}')),
                title: Text(ChecklistStep.values[index].title),
                subtitle: Text(step.$2),
                trailing: Icon(step.$1),
              ),
            ],
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Préparez une pièce justificative lisible (photo ou '
                        'PDF, 10 Mo au maximum). La liste exacte des '
                        'documents demandés s’affiche à l’étape '
                        '« Justificatifs ».',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.push(Routes.providerOnboardingProfile),
              child: const Text('Créer mon profil prestataire'),
            ),
          ],
        ),
      ),
    );
  }
}
