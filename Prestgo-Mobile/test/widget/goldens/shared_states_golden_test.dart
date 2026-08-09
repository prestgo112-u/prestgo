// Références visuelles des composants d'état partagés (T246).
//
// Le triptyque chargement / erreur / vide habille la quasi-totalité des écrans :
// une dérive visuelle ici se propage partout. Ces images de référence figent le
// rendu — tout écart volontaire se ré-approuve avec
// `flutter test --update-goldens test/widget/goldens`.
//
// Étiquette `golden` : les références sont générées sous Windows, le rendu d'un
// autre système diffère au pixel près — l'intégration continue (Linux) les
// exclut (`--exclude-tags=golden`).
@Tags(<String>['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/app/theme/app_theme.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';

/// Surface fixe : la référence ne dépend ni de l'appareil ni de l'hôte de test.
const Size _surface = Size(400, 600);

Widget _host(Widget child, {required ThemeData theme}) => MaterialApp(
  theme: theme,
  debugShowCheckedModeBanner: false,
  home: Scaffold(body: child),
);

Future<void> _capture(
  WidgetTester tester,
  Widget child,
  String goldenName, {
  ThemeData? theme,
}) async {
  await tester.binding.setSurfaceSize(_surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_host(child, theme: theme ?? AppTheme.light()));
  // Un seul `pump` : l'indicateur de chargement est animé, `pumpAndSettle`
  // ne convergerait jamais — l'image fige la première frame, déterministe.
  await tester.pump();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('$goldenName.png'),
  );
}

void main() {
  testWidgets('LoadingView — référence visuelle', (WidgetTester tester) async {
    await _capture(
      tester,
      const LoadingView(label: 'Chargement des missions…'),
      'loading_view',
    );
  });

  testWidgets('ErrorView — reprise et référence support', (
    WidgetTester tester,
  ) async {
    await _capture(
      tester,
      ErrorView(
        message: 'Le service est momentanément indisponible.',
        onRetry: () {},
        correlationId: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
      ),
      'error_view',
    );
  });

  testWidgets('EmptyView — titre, description et actions', (
    WidgetTester tester,
  ) async {
    await _capture(
      tester,
      EmptyView(
        title: 'Aucun prestataire trouvé',
        description: 'Essayez d’élargir la zone de recherche.',
        actions: <EmptyAction>[
          EmptyAction(label: 'Élargir le rayon', onPressed: () {}),
          EmptyAction(label: 'Retirer les filtres', onPressed: () {}),
        ],
      ),
      'empty_view',
    );
  });

  testWidgets('ErrorView — thème sombre', (WidgetTester tester) async {
    await _capture(
      tester,
      ErrorView(
        message: 'Connexion impossible. Vérifiez votre réseau.',
        onRetry: () {},
      ),
      'error_view_dark',
      theme: AppTheme.dark(),
    );
  });
}
