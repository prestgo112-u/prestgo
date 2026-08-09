// T228 — États d'avis : modération, dépôt, signalement (US9).
//
// Ce que ces tests protègent :
//   • **les états de modération commandent le rendu** (FR-072) : un avis
//     signalé RESTE visible avec sa mention ; un avis retiré est REMPLACÉ par
//     la mention — et il n'existe ni modification ni suppression ;
//   • **le dépôt est gardé localement** : pas de note, rien ne part ; le 409
//     « déjà noté » suit exactement le chemin du succès (FR-071) ;
//   • **le signalement** : motif trop court bloqué localement, doublon rendu
//     comme la mention « déjà signalé » (9.4), action jamais rendue sur ses
//     propres avis.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/reviews/presentation/my_reviews_screen.dart';
import 'package:prestgo_mobile/features/reviews/presentation/report_review_action.dart';
import 'package:prestgo_mobile/features/reviews/presentation/submit_review_screen.dart';

import '../support/fixtures.dart';
import '../support/screen_harness.dart';

const String kMissionId = 'a75221c8-03a0-4dc7-a4c0-c0047ad0713c';
const String kReviewId = '8b7c6d5e-4f3a-4b2c-8d1e-0f9a8b7c6d5e';

/// Laisse les minuteries de snackbar s'éteindre avant la fin du test.
Future<void> drainSnackBars(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 5));

/// Monte [screen] derrière une page de base : les écrans qui se ferment par
/// `pop` ont besoin d'une pile de navigation réelle.
Future<void> pumpPushed(
  WidgetTester tester,
  ScreenHarness harness,
  Widget screen,
) async {
  await harness.pump(
    tester,
    Builder(
      builder: (BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (BuildContext _) => screen),
            ),
            child: const Text('Ouvrir'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Ouvrir'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting(AppFormats.locale));

  group('Mes avis (T225)', () {
    testWidgets('signalé RESTE visible, retiré devient une mention — et '
        'aucune action d’édition n’existe', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(
        (RequestOptions options, int index) =>
            fixture('reviews/my_reviews', 'firstPage'),
      );
      await harness.pump(tester, const MyReviewsScreen());
      await tester.pumpAndSettle();

      // Publié : le contenu, tel que déposé.
      expect(
        find.text('Travail impeccable, ponctuel et soigneux.'),
        findsOneWidget,
      );

      // Signalé : le contenu RESTE affiché, la mention l'accompagne.
      expect(
        find.text('Retard important et chantier laissé sale.'),
        findsOneWidget,
      );
      expect(find.text('Signalé — en cours d’examen'), findsOneWidget);

      // Retiré : la mention REMPLACE le contenu.
      expect(find.text('Avis retiré par la modération.'), findsOneWidget);
      expect(find.text('Contenu retiré par la modération.'), findsNothing);

      // Ni modification ni suppression.
      expect(find.byType(Dismissible), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      await harness.dispose(tester);
    });
  });

  group('Dépôt d’avis (T224)', () {
    testWidgets('sans note, rien ne part ; avec note, la note part dans le '
        'corps', (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final ScreenHarness harness = ScreenHarness((
        RequestOptions options,
        int index,
      ) {
        journal.add('${options.method} ${options.path}');
        return fixture('reviews/submit', 'created');
      });
      await pumpPushed(
        tester,
        harness,
        const SubmitReviewScreen(
          missionId: kMissionId,
          remaining: Duration(days: 12),
        ),
      );

      // Le temps restant s'affiche dans l'écran même (9.1).
      expect(
        find.text('Il vous reste 12 jours pour noter cette mission.'),
        findsOneWidget,
      );

      // Publier sans note : refus local, AUCUN appel.
      await tester.tap(find.text('Publier mon avis'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choisissez une note de 1 à 5 étoiles.'),
        findsOneWidget,
      );
      expect(journal, isEmpty);

      await tester.tap(find.byTooltip('4 étoiles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publier mon avis'));
      await tester.pumpAndSettle();

      expect(journal, <String>['POST /missions/$kMissionId/review']);
      expect(find.text('Merci pour votre avis !'), findsOneWidget);

      await drainSnackBars(tester);
      await harness.dispose(tester);
    });

    testWidgets('409 « déjà noté » : le chemin du succès, pas une erreur', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = ScreenHarness(
        (RequestOptions options, int index) =>
            fixture('reviews/submit', 'duplicate'),
      );
      await pumpPushed(
        tester,
        harness,
        const SubmitReviewScreen(missionId: kMissionId),
      );

      await tester.tap(find.byTooltip('5 étoiles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Publier mon avis'));
      await tester.pumpAndSettle();

      // L'écran s'est fermé sur un remerciement — pas un message d'échec.
      expect(
        find.text('Votre avis avait déjà été pris en compte.'),
        findsOneWidget,
      );
      expect(
        find.text('Vous avez déjà déposé un avis sur cette mission'),
        findsNothing,
      );

      await drainSnackBars(tester);
      await harness.dispose(tester);
    });
  });

  group('Signalement (T226)', () {
    testWidgets('motif court bloqué localement ; transmis, l’action devient '
        'la mention', (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final ScreenHarness harness = ScreenHarness((
        RequestOptions options,
        int index,
      ) {
        journal.add('${options.method} ${options.path}');
        return fixture('reviews/report', 'reported');
      });
      await harness.pump(
        tester,
        const Scaffold(body: ReportReviewAction(reviewId: kReviewId)),
      );

      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();

      // Motif trop court : refus local, rien ne part.
      await tester.enterText(
        find.widgetWithText(TextField, 'Motif (obligatoire)'),
        'ab',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Signaler'));
      await tester.pumpAndSettle();
      expect(
        find.text('Indiquez un motif d’au moins 3 caractères.'),
        findsOneWidget,
      );
      expect(journal, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextField, 'Motif (obligatoire)'),
        'Propos injurieux envers le client.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Signaler'));
      await tester.pumpAndSettle();

      expect(journal, <String>['POST /reviews/$kReviewId/report']);
      expect(find.text('Signalement transmis à la modération'), findsOneWidget);
      // L'action est devenue la mention : plus de second signalement possible.
      expect(find.text('Déjà signalé'), findsOneWidget);
      expect(find.text('Signaler'), findsNothing);

      await drainSnackBars(tester);
      await harness.dispose(tester);
    });

    testWidgets('9.4 — le doublon (409) devient la mention, pas une erreur '
        'brute', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(
        (RequestOptions options, int index) =>
            fixture('reviews/report', 'alreadyReported'),
      );
      await harness.pump(
        tester,
        const Scaffold(body: ReportReviewAction(reviewId: kReviewId)),
      );

      await tester.tap(find.text('Signaler'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Motif (obligatoire)'),
        'Propos injurieux envers le client.',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Signaler'));
      await tester.pumpAndSettle();

      expect(find.text('Vous avez déjà signalé cet avis'), findsOneWidget);
      expect(find.text('Déjà signalé'), findsOneWidget);

      await drainSnackBars(tester);
      await harness.dispose(tester);
    });

    testWidgets('jamais rendue sur ses propres avis', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = ScreenHarness(always(500, null));
      await harness.pump(
        tester,
        const Scaffold(
          body: ReportReviewAction(reviewId: kReviewId, isOwn: true),
        ),
      );

      expect(find.text('Signaler'), findsNothing);
      expect(find.text('Déjà signalé'), findsNothing);

      await harness.dispose(tester);
    });
  });
}
