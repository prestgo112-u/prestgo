// T161 — Hub de complétude et écran de suivi, état par état.
//
// Ce que ces tests protègent :
//   • **les libellés officiels des lignes rouges** — « nom public ET
//     présentation », « service AVEC formule active » : ce sont eux qui
//     désamorcent les deux pièges du calcul de la checklist (scénarios 4.1, 4.2) ;
//   • **le bouton « Soumettre » est piloté par `canSubmit`**, jamais par la
//     checklist — le compte démo approuvé a les cases « pleines » et le bouton
//     inerte ;
//   • **un refus de soumission marque EXACTEMENT les lignes désignées** par
//     `errors[].field` (scénario 4.7) ;
//   • **chaque état du suivi P9 a ses actions** — motif en tête, re-soumission
//     seulement si `canSubmit`, contact support quand elle est bloquée.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/checklist_screen.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/status_screen.dart';

import '../support/fixtures.dart';
import '../support/recording_adapter.dart';
import '../support/screen_harness.dart';

/// Service simulé du dossier : l'aperçu servi est un cas de capture, la
/// soumission un autre.
AdapterScenario providerBackend({
  required String overviewCase,
  String submitCase = 'submitted',
  List<String>? journal,
}) => (RequestOptions options, int index) {
  journal?.add('${options.method} ${options.path}');
  if (options.path == '/providers/me/submit') {
    return fixture('provider/submit', submitCase);
  }
  if (options.path == '/providers/me') {
    return fixture('provider/self', overviewCase);
  }
  return (
    404,
    <String, Object?>{'success': false, 'message': 'Route non simulée'},
  );
};

/// Amène [finder] dans le viewport — les écrans P8 et P9 sont des `ListView`
/// paresseuses : un bouton sous la ligne de flottaison n'est pas encore
/// construit, et `find.text` ne le verrait pas.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting(AppFormats.locale));

  group('Hub de complétude (P8)', () {
    testWidgets('les lignes rouges portent les libellés OFFICIELS — les deux '
        'pièges sont désamorcés', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(
        providerBackend(overviewCase: 'overviewIncomplete'),
      );
      await harness.pump(tester, const ChecklistScreen());
      await tester.pumpAndSettle();

      // `services`, `availabilities` et `documents` sont faux dans la capture.
      expect(
        find.text(
          'Déclarez au moins un service avec une formule tarifaire '
          'active',
        ),
        findsOneWidget,
        reason:
            'un service sans formule ne compte pas — le libellé le dit '
            '(scénario 4.2)',
      );
      expect(
        find.text('Renseignez vos disponibilités hebdomadaires'),
        findsOneWidget,
      );
      expect(
        find.text('Fournissez tous les justificatifs obligatoires'),
        findsOneWidget,
      );
      // `profile` et `zones` sont vrais : pas de libellé d'exigence.
      expect(
        find.text('Complétez votre nom public et votre présentation'),
        findsNothing,
      );

      await harness.dispose(tester);
    });

    testWidgets('profil créé sans présentation : la ligne « profil » est '
        'rouge et nomme la présentation (4.1)', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(
        providerBackend(overviewCase: 'createdWithoutBio'),
      );
      await harness.pump(tester, const ChecklistScreen());
      await tester.pumpAndSettle();

      expect(
        find.text('Complétez votre nom public et votre présentation'),
        findsOneWidget,
        reason:
            'bio facultative à la création mais exigée par la checklist : '
            'sans ce libellé, la ligne rouge est incompréhensible (4.1)',
      );

      await harness.dispose(tester);
    });

    testWidgets('« Soumettre » est inerte tant que canSubmit est faux — même '
        'si le dossier semble complet', (WidgetTester tester) async {
      // Le compte démo approuvé : statut approved, canSubmit false.
      final ScreenHarness harness = ScreenHarness(
        providerBackend(overviewCase: 'overviewApproved'),
      );
      await harness.pump(tester, const ChecklistScreen());
      await tester.pumpAndSettle();

      final FilledButton button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Soumettre mon dossier'),
      );
      expect(
        button.onPressed,
        isNull,
        reason: 'le bouton lit canSubmit, jamais la checklist ni le statut',
      );

      await harness.dispose(tester);
    });

    testWidgets('canSubmit vrai : le bouton s’active', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = ScreenHarness(
        providerBackend(overviewCase: 'overviewComplete'),
      );
      await harness.pump(tester, const ChecklistScreen());
      await tester.pumpAndSettle();

      final FilledButton button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Soumettre mon dossier'),
      );
      expect(button.onPressed, isNotNull);

      await harness.dispose(tester);
    });

    testWidgets('un refus de soumission passe en rouge EXACTEMENT les lignes '
        'désignées (4.7)', (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final ScreenHarness harness = ScreenHarness(
        providerBackend(
          overviewCase: 'overviewComplete',
          submitCase: 'incompleteTwoLines',
          journal: journal,
        ),
      );
      await harness.pump(tester, const ChecklistScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Soumettre mon dossier'));
      await tester.pumpAndSettle();

      expect(journal, contains('POST /providers/me/submit'));
      // Les deux lignes désignées portent le libellé du service…
      expect(
        find.text('Complétez votre nom public et votre présentation'),
        findsOneWidget,
      );
      expect(
        find.text('Fournissez tous les justificatifs obligatoires'),
        findsOneWidget,
      );
      // …et les trois autres restent muettes : pas une ligne de plus.
      expect(
        find.text('Choisissez au moins une zone d’intervention'),
        findsNothing,
      );
      expect(
        find.text('Renseignez vos disponibilités hebdomadaires'),
        findsNothing,
      );
      expect(
        find.text(
          'Déclarez au moins un service avec une formule tarifaire '
          'active',
        ),
        findsNothing,
      );

      await harness.dispose(tester);
    });

    testWidgets('re-soumission bloquée : plus de bouton, contact support', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = ScreenHarness(
        providerBackend(overviewCase: 'overviewRejectedBlocked'),
      );
      await harness.pump(tester, const ChecklistScreen());
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(FilledButton, 'Soumettre mon dossier'),
        findsNothing,
      );
      expect(
        find.text(
          'La re-soumission de votre dossier a été bloquée. '
          'Contactez le support.',
        ),
        findsOneWidget,
      );

      await harness.dispose(tester);
    });
  });

  group('Écran de suivi (P9) — un état, des actions', () {
    testWidgets('pending_review : date de soumission, étapes validées, '
        'disponibilité active, rien de plus', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(
        providerBackend(overviewCase: 'overviewPendingReview'),
      );
      await harness.pump(tester, const ProviderStatusScreen());
      await tester.pumpAndSettle();

      expect(find.text('Dossier en cours de vérification'), findsOneWidget);
      expect(find.textContaining('Soumis le'), findsOneWidget);
      // L'interrupteur de disponibilité est là et OUVERT (scénario 4.8)…
      expect(find.text('Disponible'), findsOneWidget);
      expect(find.text('Occupé'), findsOneWidget);
      // …mais aucune re-soumission ni correction n'est proposée.
      expect(find.text('Re-soumettre mon dossier'), findsNothing);
      expect(find.text('Ouvrir mon dossier'), findsNothing);

      await harness.dispose(tester);
    });

    testWidgets('changes_requested (motif sur la présentation) : motif en '
        'tête et « Re-soumettre » actif', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(
        providerBackend(overviewCase: 'overviewChangesRequestedBio'),
      );
      await harness.pump(tester, const ProviderStatusScreen());
      await tester.pumpAndSettle();

      expect(find.text('Corrections demandées'), findsOneWidget);
      expect(
        find.text(
          'Votre présentation est trop vague : précisez vos '
          'prestations et votre expérience.',
        ),
        findsOneWidget,
      );
      await scrollTo(tester, find.text('Ouvrir mon dossier'));
      await scrollTo(tester, find.text('Re-soumettre mon dossier'));
      expect(find.text('Re-soumettre mon dossier'), findsOneWidget);

      await harness.dispose(tester);
    });

    testWidgets('changes_requested (motif sur un document) : PAS de bouton '
        'Re-soumettre — le redépôt suffira (4.9)', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(
        providerBackend(overviewCase: 'overviewChangesRequestedDocument'),
      );
      await harness.pump(tester, const ProviderStatusScreen());
      await tester.pumpAndSettle();

      // « Mes justificatifs » ferme la liste des actions : une fois visible,
      // tout ce qui pouvait suivre est construit — l'absence du bouton de
      // re-soumission est alors une vraie absence, pas un artefact de
      // liste paresseuse.
      await scrollTo(tester, find.text('Mes justificatifs'));
      expect(find.text('Mes justificatifs'), findsOneWidget);
      expect(
        find.text('Re-soumettre mon dossier'),
        findsNothing,
        reason:
            'canSubmit est faux : le redépôt du justificatif renverra le '
            'dossier tout seul',
      );

      await harness.dispose(tester);
    });

    testWidgets('rejected non bloqué : mêmes corrections que '
        'changes_requested', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(
        providerBackend(overviewCase: 'overviewRejected'),
      );
      await harness.pump(tester, const ProviderStatusScreen());
      await tester.pumpAndSettle();

      expect(find.text('Dossier refusé'), findsOneWidget);
      await scrollTo(tester, find.text('Re-soumettre mon dossier'));
      expect(find.text('Re-soumettre mon dossier'), findsOneWidget);

      await harness.dispose(tester);
    });

    testWidgets('rejected AVEC blocage : contact support, aucun bouton', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = ScreenHarness(
        providerBackend(overviewCase: 'overviewRejectedBlocked'),
      );
      await harness.pump(tester, const ProviderStatusScreen());
      await tester.pumpAndSettle();

      expect(find.text('Re-soumettre mon dossier'), findsNothing);
      expect(find.text('Ouvrir mon dossier'), findsNothing);
      expect(find.text('Contacter le support'), findsOneWidget);

      await harness.dispose(tester);
    });

    testWidgets('suspended : information et support, aucune gestion', (
      WidgetTester tester,
    ) async {
      final ScreenHarness harness = ScreenHarness(
        providerBackend(overviewCase: 'overviewSuspended'),
      );
      await harness.pump(tester, const ProviderStatusScreen());
      await tester.pumpAndSettle();

      expect(find.text('Compte suspendu'), findsOneWidget);
      expect(find.text('Contacter le support'), findsOneWidget);
      expect(find.text('Re-soumettre mon dossier'), findsNothing);

      await harness.dispose(tester);
    });
  });
}
