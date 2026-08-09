// T217 — Écrans de l'espace prestataire : la vie de l'offre (US8).
//
// Ce que ces tests protègent :
//   • **le vocabulaire du contrat** (T210) : rien ne se « Supprime » — services
//     et formules se « Désactivent », et tout reste visible dans la vue de
//     gestion, y compris ce qui est désactivé ;
//   • **l'avertissement de disparition de la recherche** (8.2) : désactiver la
//     dernière prestation réservable exige une confirmation explicite — et un
//     refus n'envoie RIEN sur le réseau ;
//   • **la paire asymétrique des options** (T211) : création par le chemin
//     imbriqué, modification par le chemin À PLAT — avec la mention « les
//     missions réservées gardent leur montant » à l'endroit du prix (8.1) ;
//   • **le plafond du portfolio** (8.3) : à 20, l'ajout est indisponible AVEC
//     son motif — pas un bouton muet ;
//   • **l'avertissement de visibilité publique de la photo** (8.4) : il
//     précède le choix du fichier, et l'annuler n'ouvre pas le sélecteur.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/files/file_upload_service.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/document_picker.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/packs_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/portfolio_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/provider_profile_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/services_screen.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/unavailabilities_screen.dart';

import '../support/fixtures.dart';
import '../support/recording_adapter.dart';
import '../support/screen_harness.dart';

const String kPackId = '7f0b2a4c-9d1e-4f3a-8b5c-6d7e8f9a0b1c';
const String kOptionId = '2c3d4e5f-6a7b-4c8d-9e0f-1a2b3c4d5e6f';
const String kServiceId = '4698c3da-7697-41b5-8c6d-946fdcec95f0';

/// Service simulé de l'offre : liste de gestion, écritures rejouées depuis les
/// captures de l'onboarding (mêmes routes, mêmes réponses).
AdapterScenario offerBackend({List<String>? journal}) =>
    (RequestOptions options, int index) {
      journal?.add('${options.method} ${options.path}');
      final String path = options.path;
      if (path == '/providers/me/services' && options.method == 'GET') {
        return fixture('provider_offer/services', 'management');
      }
      if (path.startsWith('/providers/me/service-pack-options/')) {
        return fixture('provider/services', 'optionUpdated');
      }
      if (path.startsWith('/providers/me/service-packs/')) {
        return fixture('provider/services', 'packUpdated');
      }
      if (path.startsWith('/providers/me/services/')) {
        return fixture('provider/services', 'serviceUpdated');
      }
      if (path == '/providers/me') {
        return fixture('provider/self', 'overviewApproved');
      }
      return (
        404,
        <String, Object?>{'success': false, 'message': 'Route non simulée'},
      );
    };

/// Vingt réalisations sans fichier affichable : le plafond seul importe ici.
JsonMap portfolioAtCapBody() => <String, Object?>{
  'success': true,
  'message': 'OK',
  'data': <Object?>[
    for (int i = 0; i < ContentLimits.portfolioItems; i++)
      <String, Object?>{
        'id': 'item-$i',
        'title': 'Réalisation n°${i + 1}',
        'displayOrder': i,
        'createdAt': '2026-07-01T08:00:00.000Z',
      },
  ],
};

/// Sélecteur espion : enregistre s'il a été ouvert, ne rend jamais rien.
class RecordingPicker implements DocumentPicker {
  int calls = 0;

  @override
  Future<UploadCandidate?> pick() async {
    calls += 1;
    return null;
  }
}

void main() {
  setUpAll(() => initializeDateFormatting(AppFormats.locale));

  group('Mes prestations (T210)', () {
    testWidgets('vue de gestion : tout est visible, rien ne se supprime — '
        'on « Désactive »', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(offerBackend());
      await harness.pump(tester, const ProviderServicesScreen());
      await tester.pumpAndSettle();

      // Les deux services sont là, y compris le désactivé.
      expect(find.text('Dépannage plomberie à domicile'), findsOneWidget);
      expect(find.text('Petite maçonnerie'), findsOneWidget);
      expect(find.text('Réparation de fuite — Plomberie'), findsOneWidget);
      expect(find.text('Désactivée'), findsOneWidget);

      // Le vocabulaire : « Désactiver » et « Réactiver », jamais « Supprimer ».
      expect(find.text('Désactiver'), findsOneWidget);
      expect(find.text('Réactiver'), findsOneWidget);
      expect(find.textContaining('Supprimer'), findsNothing);

      await harness.dispose(tester);
    });

    testWidgets('8.2 — désactiver la dernière prestation réservable avertit '
        'de la disparition de la recherche ; annuler n’envoie rien', (
      WidgetTester tester,
    ) async {
      final List<String> journal = <String>[];
      final ScreenHarness harness = ScreenHarness(
        offerBackend(journal: journal),
      );
      await harness.pump(tester, const ProviderServicesScreen());
      await tester.pumpAndSettle();

      // Le service actif est le SEUL réservable (l'autre est désactivé) : la
      // confirmation s'impose.
      await tester.tap(find.text('Désactiver'));
      await tester.pumpAndSettle();

      expect(
        find.text('Désactiver votre dernière prestation ?'),
        findsOneWidget,
      );
      expect(
        find.textContaining('disparaît des résultats de recherche'),
        findsOneWidget,
      );

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      // Rien n'est parti : la seule entrée du journal est la lecture.
      expect(journal.where((String call) => call.startsWith('PATCH')), isEmpty);

      await harness.dispose(tester);
    });
  });

  group('Formules et options (T211)', () {
    testWidgets('8.1 — le formulaire de prix porte la mention du montant '
        'figé, et la formule s’écrit sur son chemin', (
      WidgetTester tester,
    ) async {
      final List<String> journal = <String>[];
      final ScreenHarness harness = ScreenHarness(
        offerBackend(journal: journal),
      );
      await harness.pump(
        tester,
        const PackManagementScreen(serviceId: kServiceId),
      );
      await tester.pumpAndSettle();

      // La formule désactivée est visible elle aussi.
      expect(find.text('Intervention express'), findsOneWidget);
      expect(find.text('Forfait journée'), findsOneWidget);

      await tester.tap(find.text('Modifier').first);
      await tester.pumpAndSettle();

      // La mention est DANS le formulaire, à l'endroit où le prix change.
      expect(
        find.textContaining('missions déjà réservées gardent leur montant'),
        findsOneWidget,
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Prix (XOF)'),
        '6000',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(journal, contains('PATCH /providers/me/service-packs/$kPackId'));

      await harness.dispose(tester);
    });

    testWidgets('l’option se modifie par le chemin À PLAT — jamais sous la '
        'formule', (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final ScreenHarness harness = ScreenHarness(
        offerBackend(journal: journal),
      );
      await harness.pump(
        tester,
        const PackManagementScreen(serviceId: kServiceId),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Modifier l’option'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(
        journal,
        contains('PATCH /providers/me/service-pack-options/$kOptionId'),
      );
      expect(
        journal.where(
          (String call) =>
              call.startsWith('PATCH /providers/me/service-packs/') &&
              call.contains('/options'),
        ),
        isEmpty,
      );

      await harness.dispose(tester);
    });
  });

  group('Portfolio (T215)', () {
    testWidgets('8.3 — à 20 réalisations, l’ajout est indisponible AVEC son '
        'motif', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness((
        RequestOptions options,
        int index,
      ) {
        if (options.path == '/providers/me/portfolio') {
          return (200, portfolioAtCapBody());
        }
        return (
          404,
          <String, Object?>{'success': false, 'message': 'Route non simulée'},
        );
      });
      await harness.pump(tester, const ProviderPortfolioScreen());
      await tester.pumpAndSettle();

      expect(find.text('Ajouter une réalisation (20/20)'), findsOneWidget);
      // `FilledButton.icon` construit un sous-type privé : la recherche passe
      // par un prédicat, pas par le runtimeType exact.
      final FilledButton addButton = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Ajouter une réalisation (20/20)'),
          matching: find.byWidgetPredicate(
            (Widget widget) => widget is FilledButton,
          ),
        ),
      );
      expect(addButton.onPressed, isNull);
      expect(find.textContaining('20 réalisations au maximum'), findsOneWidget);

      await harness.dispose(tester);
    });
  });

  group('Absences exceptionnelles (T214)', () {
    testWidgets('liste relue par la route publique, suppression confirmée '
        'puis envoyée', (WidgetTester tester) async {
      final List<String> journal = <String>[];
      final ScreenHarness harness = ScreenHarness((
        RequestOptions options,
        int index,
      ) {
        journal.add('${options.method} ${options.path}');
        if (options.path == '/providers/me') {
          return fixture('provider/self', 'overviewApproved');
        }
        if (options.path.endsWith('/unavailabilities') &&
            options.method == 'GET') {
          return fixture('provider_offer/unavailabilities', 'list');
        }
        if (options.method == 'DELETE') {
          return fixture('provider_offer/unavailabilities', 'deleted');
        }
        return (
          404,
          <String, Object?>{'success': false, 'message': 'Route non simulée'},
        );
      });
      await harness.pump(tester, const ProviderUnavailabilitiesScreen());
      await tester.pumpAndSettle();

      // La relecture passe par la route publique, avec MON identifiant.
      expect(
        journal,
        contains(
          'GET /providers/bb1397e8-ff8f-4142-a9f9-b0a0d07dfa5c'
          '/unavailabilities',
        ),
      );
      expect(find.text('Congés annuels'), findsOneWidget);

      await tester.tap(find.byTooltip('Supprimer l’absence').first);
      await tester.pumpAndSettle();
      expect(find.text('Supprimer cette absence ?'), findsOneWidget);

      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();

      expect(
        journal,
        contains(
          'DELETE /providers/me/unavailabilities/'
          'd4e5f6a7-b8c9-4d0e-8f1a-3b4c5d6e7f8a',
        ),
      );

      await harness.dispose(tester);
    });
  });

  group('Photo de profil (T209)', () {
    testWidgets('8.4 — l’avertissement de visibilité publique précède le '
        'sélecteur ; annuler ne l’ouvre pas', (WidgetTester tester) async {
      final ScreenHarness harness = ScreenHarness(offerBackend());
      final RecordingPicker picker = RecordingPicker();

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            ...harness.overrides,
            documentPickerProvider.overrideWithValue(picker),
          ],
          child: const MaterialApp(home: ProviderSpaceProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Visible publiquement sur votre fiche.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Publier'));
      await tester.pumpAndSettle();

      expect(find.text('Photo visible publiquement'), findsOneWidget);
      expect(
        find.textContaining('visible par tous les visiteurs'),
        findsOneWidget,
      );
      // L'avertissement est arrivé AVANT le choix du fichier.
      expect(picker.calls, 0);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      // Renoncer n'ouvre jamais le sélecteur.
      expect(picker.calls, 0);

      await harness.dispose(tester);
    });
  });
}
