// État de chargement partagé.
//
// L'application est très majoritairement de la lecture : chargement, erreur et vide
// forment le triptyque qui domine les écrans. Les trois composants vivent ici pour
// que le comportement soit identique partout — un état de chargement doit
// apparaître en moins d'une seconde (SC-005).

import 'package:flutter/material.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  /// Précision facultative — « Chargement des missions… ».
  final String? label;

  @override
  Widget build(BuildContext context) {
    final String text = label ?? 'Chargement…';
    return Semantics(
      liveRegion: true,
      label: text,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox.square(
              dimension: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

/// Chargement d'une page supplémentaire, en pied de liste paginée.
class LoadingMoreTile extends StatelessWidget {
  const LoadingMoreTile({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      ),
    ),
  );
}
