// T051 — Composants d'état partagés.
//
// L'application est très majoritairement de la lecture : chargement, erreur et vide
// forment le triptyque qui domine les écrans. Leur comportement est vérifié ici une
// fois pour toutes, plutôt qu'écran par écran.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/core/widgets/offline_banner.dart';

Future<void> pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  group('Chargement', () {
    testWidgets('affiche un indicateur et un libellé par défaut', (
      WidgetTester tester,
    ) async {
      await pump(tester, const LoadingView());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Chargement…'), findsOneWidget);
    });

    testWidgets('accepte un libellé précis, annoncé aux lecteurs d’écran', (
      WidgetTester tester,
    ) async {
      await pump(tester, const LoadingView(label: 'Chargement des missions…'));

      expect(find.text('Chargement des missions…'), findsOneWidget);
      // Zone vive : le lecteur d'écran annonce le chargement sans que
      // l'utilisateur ait à explorer l'écran.
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .any((Semantics s) => s.properties.liveRegion ?? false),
        isTrue,
      );
    });

    testWidgets('le pied de liste paginée est discret', (
      WidgetTester tester,
    ) async {
      await pump(tester, const LoadingMoreTile());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Erreur', () {
    testWidgets('affiche le message et propose la reprise', (
      WidgetTester tester,
    ) async {
      var retried = 0;
      await pump(
        tester,
        ErrorView(
          message: 'Le service est momentanément indisponible.',
          onRetry: () => retried++,
        ),
      );

      expect(
        find.text('Le service est momentanément indisponible.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Réessayer'));
      expect(retried, 1);
    });

    testWidgets('sans reprise possible, aucun bouton n’est affiché', (
      WidgetTester tester,
    ) async {
      await pump(tester, const ErrorView(message: 'Erreur'));
      expect(find.text('Réessayer'), findsNothing);
    });

    testWidgets('reprend le message assaini de l’exception', (
      WidgetTester tester,
    ) async {
      final ApiException error = ApiException.fromResponse(
        statusCode: 401,
        body: const <String, Object?>{
          'success': false,
          'message': 'Invalid credentials',
        },
      );

      await pump(tester, ErrorView.fromException(error, onRetry: () {}));

      expect(find.text(ApiFallbackMessages.invalidCredentials), findsOneWidget);
      expect(find.text('Invalid credentials'), findsNothing);
    });

    testWidgets('un débit dépassé ne propose jamais « Réessayer »', (
      WidgetTester tester,
    ) async {
      final ApiException error = ApiException.fromResponse(statusCode: 429);

      await pump(tester, ErrorView.fromException(error, onRetry: () {}));

      expect(find.text(ApiFallbackMessages.rateLimited), findsOneWidget);
      expect(
        find.text('Réessayer'),
        findsNothing,
        reason: 'un rejeu sur 429 ne ferait qu’aggraver le débit (porte G4)',
      );
    });

    testWidgets('une coupure réseau change l’icône', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        ErrorView.fromException(const ApiException.network(), onRetry: () {}),
      );
      expect(find.byIcon(Icons.wifi_off_outlined), findsOneWidget);
    });

    testWidgets(
      'la référence de corrélation est proposée en copie, jamais mise en avant',
      (WidgetTester tester) async {
        final ApiException error = ApiException.fromResponse(
          statusCode: 500,
          body: const <String, Object?>{
            'success': false,
            'meta': <String, Object?>{'correlationId': 'req-42'},
          },
        );

        await pump(tester, ErrorView.fromException(error));

        expect(
          find.text('Copier la référence pour le support'),
          findsOneWidget,
        );
        // L'identifiant lui-même n'est pas affiché.
        expect(find.text('req-42'), findsNothing);
      },
    );

    testWidgets('le bandeau compact laisse le reste de l’écran visible', (
      WidgetTester tester,
    ) async {
      var retried = 0;
      await pump(
        tester,
        Column(
          children: <Widget>[
            const Text('Bloc voisin'),
            ErrorTile(
              message: 'Ce bloc n’a pas pu être chargé.',
              onRetry: () => retried++,
            ),
          ],
        ),
      );

      expect(find.text('Bloc voisin'), findsOneWidget);
      await tester.tap(find.text('Réessayer'));
      expect(retried, 1);
    });
  });

  group('Vide', () {
    testWidgets('un état vide propose toujours une suite', (
      WidgetTester tester,
    ) async {
      var widened = 0;
      var cleared = 0;

      await pump(
        tester,
        EmptyView(
          title: 'Aucun prestataire trouvé',
          description: 'Essayez d’élargir votre recherche.',
          actions: <EmptyAction>[
            EmptyAction(label: 'Élargir le rayon', onPressed: () => widened++),
            EmptyAction(
              label: 'Retirer les filtres',
              onPressed: () => cleared++,
            ),
          ],
        ),
      );

      expect(find.text('Aucun prestataire trouvé'), findsOneWidget);
      expect(find.text('Essayez d’élargir votre recherche.'), findsOneWidget);

      await tester.tap(find.text('Élargir le rayon'));
      await tester.tap(find.text('Retirer les filtres'));
      expect(widened, 1);
      expect(cleared, 1);
    });

    testWidgets('sans action, le titre suffit', (WidgetTester tester) async {
      await pump(tester, const EmptyView(title: 'Rien à afficher'));

      expect(find.text('Rien à afficher'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('Bannière hors ligne', () {
    testWidgets('annonce la consultation seule', (WidgetTester tester) async {
      await pump(tester, const OfflineBanner());
      expect(find.text('Hors ligne — consultation seule'), findsOneWidget);
    });

    testWidgets('affiche la date des données quand elle est connue', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        const OfflineBanner(detail: 'Données du 12 août à 09:14'),
      );

      expect(find.text('Hors ligne — consultation seule'), findsOneWidget);
      expect(find.text('Données du 12 août à 09:14'), findsOneWidget);
    });
  });
}
