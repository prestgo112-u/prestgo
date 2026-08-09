// Écran d'attente du squelette de routeur.
//
// La Phase 2 pose la table des routes et le gardien ; les écrans arrivent avec leur
// récit utilisateur. Chaque emplacement affiche donc la tâche qui le remplira, ce
// qui rend visible ce qui reste à faire au lieu d'une page blanche.

import 'package:flutter/material.dart';

class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.title,
    required this.task,
    this.actions = const <Widget>[],
    super.key,
  });

  final String title;

  /// Identifiant de la tâche qui implémentera cet écran — « T098 ».
  final String task;

  /// Actions de barre de titre.
  ///
  /// Un écran d'attente peut se trouver être un écran d'**atterrissage** : c'est le
  /// cas de l'accueil client. Il doit alors offrir la déconnexion, faute de quoi son
  /// occupant n'a aucune issue — ni ici, ni ailleurs, puisque rien n'y mène.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.construction_outlined,
                size: 44,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Écran prévu par la tâche $task.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
