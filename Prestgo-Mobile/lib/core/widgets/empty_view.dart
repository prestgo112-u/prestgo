// État vide partagé — toujours **avec une action**.
//
// Un état vide muet laisse l'utilisateur sans issue. Les écrans de recherche
// proposent « Élargir le rayon » et « Retirer les filtres », le carnet d'adresses
// invite à créer la première adresse, etc.

import 'package:flutter/material.dart';

/// Une action proposée depuis un état vide.
class EmptyAction {
  const EmptyAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    required this.title,
    super.key,
    this.description,
    this.actions = const <EmptyAction>[],
    this.icon = Icons.inbox_outlined,
  });

  final String title;
  final String? description;

  /// Au moins une action est attendue ; la liste vide reste permise pour les rares
  /// écrans où aucune suite n'a de sens.
  final List<EmptyAction> actions;

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? description = this.description;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (description != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                description,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  for (final EmptyAction action in actions)
                    FilledButton.tonal(
                      onPressed: action.onPressed,
                      child: Text(action.label),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
