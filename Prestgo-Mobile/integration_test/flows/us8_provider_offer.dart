// T218 — Parcours US8 de bout en bout : scénarios 8.1 à 8.5 de quickstart.md.
//
// La vie de l'offre après approbation : prix modifié avec la mention du
// montant figé (8.1), désactivation de la dernière formule active avec
// l'avertissement de disparition de la recherche (8.2), plafond du portfolio
// (8.3), publication de la photo de profil avec l'avertissement de visibilité
// publique — et l'envoi réel en deux temps, binaire puis rattachement (8.4),
// justificatif validé sans re-dépôt possible (8.5).
//
// Le service simulé porte l'état que les scénarios font muter : le prix et
// l'activation de la formule, la photo de profil. Tout le reste — routeur,
// gardien, dépôts, écrans, chaîne d'intercepteurs — est le code livré.
//
// Comme pour US1 à US7, les scénarios sont exposés par [runUs8Scenarios] et
// déroulés par deux points d'entrée : sur appareil (`integration_test/`) et
// sans appareil (`test/flows/`), ce dernier étant le seul que `flutter test`
// atteint — donc le seul que l'intégration continue exécute.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/app/router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/cache/local_database.dart';
import 'package:prestgo_mobile/core/files/file_upload_service.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/document_picker.dart';

import '../../test/support/fixtures.dart';
import '../../test/support/recording_adapter.dart';
import '../../test/support/screen_harness.dart';
import '../support/app_harness.dart';

const String kProviderId = 'b7e2a4c6-1d3f-4a5b-8c9d-0e1f2a3b4c5e';
const String kServiceId = 's-plomberie-1';
const String kPackId = 'p-express-1';
const String kAvatarFileId = 'f-avatar-1';

/// Service simulé de l'offre — l'état que les scénarios font muter.
class OfferBackend {
  num packPrice = 5000;
  bool packActive = true;
  String? avatarFileId;

  /// Nombre de réalisations servies (20 = plafond atteint, scénario 8.3).
  int portfolioCount = 20;

  final List<String> journal = <String>[];

  int callsTo(String method, String path) =>
      journal.where((String entry) => entry == '$method $path').length;

  AdapterResponse handle(RequestOptions options, int index) {
    final String path = options.path;
    journal.add('${options.method} $path');
    final JsonMap body = switch (options.data) {
      final Map<Object?, Object?> data => data.cast<String, Object?>(),
      _ => const <String, Object?>{},
    };

    switch (path) {
      case '/me':
        final JsonMap me = JsonMap.of(
          fixtureData('auth/me', 'providerApproved'),
        );
        me['providerId'] = kProviderId;
        return envelope(me);

      case '/providers/me':
        if (options.method == 'PATCH') {
          avatarFileId = body['avatarFileId'] as String? ?? avatarFileId;
          return envelope(_overview(), message: 'Profil mis à jour');
        }
        return envelope(_overview());

      case '/providers/me/services':
        return envelope(<Object?>[_service()]);

      case '/providers/me/service-packs/$kPackId':
        if (body['price'] case final num price) {
          packPrice = price;
        }
        if (body['active'] case final bool active) {
          packActive = active;
        }
        return envelope(_pack(), message: 'Formule mise à jour');

      case '/providers/me/portfolio':
        return envelope(<Object?>[
          for (int i = 0; i < portfolioCount; i++)
            <String, Object?>{
              'id': 'real-$i',
              'title': 'Réalisation n°${i + 1}',
              'displayOrder': i,
              'createdAt': '2026-07-01T08:00:00.000Z',
            },
        ]);

      case '/providers/me/documents':
        return envelope(_documents());

      case '/files/upload':
        return envelope(
          <String, Object?>{
            'id': kAvatarFileId,
            'originalName': 'avatar.png',
            'mimeType': 'image/png',
            'size': 2048,
            'visibility': 'public',
          },
          status: 201,
          message: 'Fichier reçu',
        );

      case '/providers/me/missions':
        return (
          200,
          <String, Object?>{
            'success': true,
            'message': 'OK',
            'data': <Object?>[],
            'meta': <String, Object?>{'page': 1, 'limit': 20, 'total': 0},
          },
        );

      case '/me/notifications/unread-count':
        return envelope(<String, Object?>{'unread': 0});

      default:
        return (
          404,
          <String, Object?>{
            'success': false,
            'message': 'Route non simulée : ${options.method} $path',
          },
        );
    }
  }

  JsonMap _overview() => <String, Object?>{
    'id': kProviderId,
    'publicName': 'Kofi Plomberie',
    'bio': 'Plombier à Abidjan depuis 10 ans.',
    'experienceYears': 10,
    'avatarFileId': avatarFileId,
    'validationStatus': 'approved',
    'availabilityStatus': 'available',
    'score': 4.5,
    'reviewsCount': 12,
    'checklist': <String, Object?>{
      'profile': true,
      'services': true,
      'zones': true,
      'availabilities': true,
      'documents': true,
    },
    'requiredDocumentTypes': <String>['id_card'],
    'rejectionReason': null,
    'resubmissionBlocked': false,
    'submittedAt': '2026-07-20T09:00:00.000Z',
    'canSubmit': false,
    'createdAt': '2026-07-19T10:00:00.000Z',
  };

  JsonMap _pack() => <String, Object?>{
    'id': kPackId,
    'providerServiceId': kServiceId,
    'title': 'Intervention express',
    'description': 'Petite réparation, sur place en moins d’une heure.',
    'price': packPrice,
    'durationMinutes': 45,
    'active': packActive,
    'options': <Object?>[],
  };

  JsonMap _service() => <String, Object?>{
    'id': kServiceId,
    'providerId': kProviderId,
    'serviceTypeId': 'type-1',
    'title': 'Dépannage plomberie à domicile',
    'description': 'Fuites, robinetterie, évacuation.',
    'active': true,
    'createdAt': '2026-07-19T10:05:00.000Z',
    'serviceType': <String, Object?>{
      'id': 'type-1',
      'name': 'Réparation de fuite',
      'category': <String, Object?>{'id': 'cat-1', 'name': 'Plomberie'},
    },
    'packs': <Object?>[_pack()],
  };

  /// Un justificatif VALIDÉ en version 2, avec son historique (8.5).
  JsonMap _documents() {
    JsonMap version({
      required String id,
      required int number,
      required String status,
      String? rejectionReason,
    }) => <String, Object?>{
      'id': id,
      'type': 'id_card',
      'status': status,
      'version': number,
      'rejectionReason': rejectionReason,
      'reviewedAt': '2026-07-2${number}T10:00:00.000Z',
      'createdAt': '2026-07-2${number}T08:00:00.000Z',
      'file': <String, Object?>{
        'id': 'doc-v$number',
        'originalName': 'cni-v$number.pdf',
        'mimeType': 'application/pdf',
        'size': 120000,
        'visibility': 'sensitive',
      },
    };
    final JsonMap approved = version(id: 'd-2', number: 2, status: 'approved');
    final JsonMap rejected = version(
      id: 'd-1',
      number: 1,
      status: 'rejected',
      rejectionReason: 'Document illisible, reprenez la photo.',
    );
    return <String, Object?>{
      'requiredTypes': <String>['id_card'],
      'missingTypes': <String>[],
      'current': <Object?>[approved],
      'documents': <Object?>[approved, rejected],
    };
  }
}

/// Sélecteur simulé : rend toujours le même fichier local.
class FixedPicker implements DocumentPicker {
  const FixedPicker(this.candidate);

  final UploadCandidate candidate;

  @override
  Future<UploadCandidate?> pick() async => candidate;
}

/// Déroule les scénarios 8.1 à 8.5.
void runUs8Scenarios() {
  late OfferBackend backend;
  late RecordingAdapter adapter;
  late LocalDatabase database;
  late InMemoryTokenStore tokenStore;
  late ProviderContainer container;

  setUp(() {
    backend = OfferBackend();
    adapter = RecordingAdapter(backend.handle);
    database = LocalDatabase.memory();
    tokenStore = InMemoryTokenStore();
    container = buildAppContainer(
      adapter: adapter,
      database: database,
      tokenStore: tokenStore,
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  void signIn() => tokenStore.tokens = const AuthTokens(
    accessToken: 'access',
    refreshToken: 'refresh',
  );

  Future<void> start(WidgetTester tester, {String? at}) async {
    await tester.pumpWidget(FlowApp(container: container));
    await tester.pumpAndSettle();
    if (at != null) {
      container.read(goRouterProvider).go(at);
      await tester.pumpAndSettle();
    }
  }

  /// Laisse les minuteries de snackbar s'éteindre avant la fin du test.
  Future<void> drainSnackBars(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 5));

  // --- 8.1 — Modifier un prix : la mention du montant figé ---------------------

  testWidgets('8.1 — le prix se modifie avec la mention « les missions '
      'réservées gardent leur montant »', (WidgetTester tester) async {
    signIn();
    await start(tester, at: Routes.providerServices);

    expect(find.text('Dépannage plomberie à domicile'), findsOneWidget);
    await tester.tap(find.text('Formules et options'));
    await tester.pumpAndSettle();

    expect(find.text('5000 XOF · 45 min'), findsOneWidget);
    await tester.tap(find.text('Modifier'));
    await tester.pumpAndSettle();

    // La mention est là, à l'endroit même où le prix change (8.1).
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

    // L'écriture est partie sur SON chemin, et l'écran montre l'état relu.
    expect(backend.callsTo('PATCH', '/providers/me/service-packs/$kPackId'), 1);
    expect(backend.packPrice, 6000);
    expect(find.text('6000 XOF · 45 min'), findsOneWidget);
  });

  // --- 8.2 — Désactiver la dernière formule active ------------------------------

  testWidgets('8.2 — désactiver la dernière formule active avertit de la '
      'disparition de la recherche, puis part une fois confirmé', (
    WidgetTester tester,
  ) async {
    signIn();
    await start(tester, at: Routes.providerServices);

    await tester.tap(find.text('Formules et options'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Désactiver'));
    await tester.pumpAndSettle();

    // L'avertissement, AVANT tout envoi.
    expect(
      find.text('Désactiver votre dernière formule active ?'),
      findsOneWidget,
    );
    expect(
      find.textContaining('disparaît des résultats de recherche'),
      findsOneWidget,
    );
    expect(backend.callsTo('PATCH', '/providers/me/service-packs/$kPackId'), 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Désactiver'));
    await tester.pumpAndSettle();

    expect(backend.callsTo('PATCH', '/providers/me/service-packs/$kPackId'), 1);
    expect(backend.packActive, isFalse);
    // La formule reste VISIBLE, marquée désactivée — rien ne disparaît de la
    // vue de gestion.
    expect(find.text('Désactivée'), findsOneWidget);
    expect(find.text('Réactiver'), findsOneWidget);
  });

  // --- 8.3 — 21e réalisation : action indisponible avec motif -------------------

  testWidgets('8.3 — à 20 réalisations, l’ajout est indisponible avec son '
      'motif', (WidgetTester tester) async {
    signIn();
    await start(tester, at: Routes.providerPortfolio);

    expect(find.text('Réalisation n°1'), findsOneWidget);
    expect(
      find.text(
        'Ajouter une réalisation '
        '(${ContentLimits.portfolioItems}/${ContentLimits.portfolioItems})',
      ),
      findsOneWidget,
    );
    final FilledButton addButton = tester.widget<FilledButton>(
      find.ancestor(
        of: find.textContaining('Ajouter une réalisation'),
        matching: find.bySubtype<FilledButton>(),
      ),
    );
    expect(addButton.onPressed, isNull);
    expect(find.textContaining('20 réalisations au maximum'), findsOneWidget);
    expect(
      backend.callsTo('POST', '/providers/me/portfolio'),
      0,
      reason: 'une action indisponible ne part jamais sur le réseau',
    );
  });

  // --- 8.4 — Publier une photo de profil ----------------------------------------

  testWidgets('8.4 — la photo se publie après l’avertissement de visibilité '
      'publique : le binaire part, PUIS le rattachement', (
    WidgetTester tester,
  ) async {
    // Un vrai fichier local : l'envoi traverse le contrôle de type et de
    // taille du code livré.
    final File avatar = File(
      '${Directory.systemTemp.path}/prestgo_us8_avatar.png',
    );
    avatar.writeAsBytesSync(List<int>.filled(2048, 7));
    addTearDown(() {
      // Sous Windows, le flux multipart peut garder un verrou sur le fichier
      // le temps que le harnais se démonte : un reliquat dans le dossier
      // temporaire vaut mieux qu'un échec de nettoyage.
      try {
        avatar.deleteSync();
      } on FileSystemException {
        // Ignoré : le fichier sera écrasé au prochain passage.
      }
    });

    // Le sélecteur est le SEUL point substitué en plus du harnais commun.
    container.dispose();
    container = buildAppContainer(
      adapter: adapter,
      database: database,
      tokenStore: tokenStore,
      extraOverrides: <Override>[
        documentPickerProvider.overrideWithValue(
          FixedPicker(
            UploadCandidate(
              path: avatar.path,
              mimeType: 'image/png',
              fileName: 'avatar.png',
            ),
          ),
        ),
      ],
    );

    signIn();
    await start(tester, at: Routes.providerProfileSpace);

    expect(find.text('Visible publiquement sur votre fiche.'), findsOneWidget);
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    // L'avertissement PRÉCÈDE le choix du fichier (8.4).
    expect(find.text('Photo visible publiquement'), findsOneWidget);
    expect(backend.callsTo('POST', '/files/upload'), 0);

    await tester.tap(find.text('Choisir une photo'));
    await tester.pump();
    // La lecture du fichier (`MultipartFile.fromFile`) est de l'E/S RÉELLE :
    // elle ne progresse pas sous l'horloge factice du test. Cette fenêtre en
    // temps réel la laisse aboutir, puis l'interface est repompée.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    // Deux temps, dans l'ordre : le binaire, puis le rattachement au profil.
    final int uploadIndex = backend.journal.indexOf('POST /files/upload');
    final int patchIndex = backend.journal.indexOf('PATCH /providers/me');
    expect(uploadIndex, isNot(-1));
    expect(patchIndex, greaterThan(uploadIndex));
    expect(backend.avatarFileId, kAvatarFileId);
    expect(find.text('Photo de profil publiée'), findsOneWidget);

    await drainSnackBars(tester);
  });

  // --- 8.5 — Justificatif validé : re-dépôt indisponible -------------------------

  testWidgets('8.5 — un justificatif validé ne se redépose pas ; le motif du '
      'refus précédent reste lisible dans l’historique', (
    WidgetTester tester,
  ) async {
    signIn();
    await start(tester, at: Routes.providerDocuments);

    // La ligne est validée, en version 2.
    expect(find.text('Pièce d’identité'), findsOneWidget);
    expect(find.text('Validé · version 2'), findsOneWidget);

    // Le re-dépôt est retiré — ni « Déposer », ni « Remplacer ».
    expect(find.text('Déposer'), findsNothing);
    expect(find.text('Remplacer'), findsNothing);
    expect(
      find.text('Document validé — il ne peut plus être remplacé.'),
      findsOneWidget,
    );

    // L'historique des versions reste consultable.
    await tester.tap(find.text('Historique des versions (2)'));
    await tester.pumpAndSettle();
    expect(find.text('cni-v2.pdf'), findsOneWidget);
    expect(find.text('cni-v1.pdf'), findsOneWidget);
  });
}
