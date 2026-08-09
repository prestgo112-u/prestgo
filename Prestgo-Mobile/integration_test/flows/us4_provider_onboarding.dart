// T162 — Parcours US4 de bout en bout : scénarios 4.1 à 4.9 de quickstart.md.
//
// L'onboarding prestataire : hub de complétude, étapes dans un ordre libre,
// soumission pilotée par le service, suivi et correction. Le service simulé
// porte un **état mutable** qui reproduit le calcul de checklist du backend
// (provider-checklist.ts) — c'est lui qui décide, jamais l'écran (porte G1).
//
// Comme pour US1 à US3, les scénarios sont exposés par [runUs4Scenarios] et
// déroulés par deux points d'entrée : sur appareil (`integration_test/`) et
// sans appareil (`test/flows/`), ce dernier étant le seul que `flutter test`
// atteint — donc le seul que l'intégration continue exécute.

import 'dart:io';
import 'dart:typed_data';

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
import 'package:prestgo_mobile/features/provider_onboarding/presentation/document_picker.dart';
import 'package:prestgo_mobile/shared/catalog/catalog.dart';

import '../../test/support/fixtures.dart';
import '../../test/support/recording_adapter.dart';
import '../../test/support/screen_harness.dart';
import '../support/app_harness.dart';

const String kCocodyId = 'fddb1349-5f23-4307-9560-710c6220c049';
const String kMarcoryId = 'b4d92c63-8fa5-4e27-9c31-475a6b8d9f21';

/// Sélecteur de fichier substitué : rend toujours le même candidat.
class FakeDocumentPicker implements DocumentPicker {
  FakeDocumentPicker(this.candidate);

  UploadCandidate? candidate;

  @override
  Future<UploadCandidate?> pick() async => candidate;
}

/// Service simulé du dossier prestataire — état mutable, checklist recalculée
/// comme le fait le backend.
class ProviderBackend {
  ProviderBackend()
    : zoneCatalog =
          (fixtureBody('provider/zones', 'catalog')['data']! as List<Object?>)
              .whereType<Map<Object?, Object?>>()
              .map((Map<Object?, Object?> e) => e.cast<String, Object?>())
              .toList();

  final List<JsonMap> zoneCatalog;

  // --- État du dossier ----------------------------------------------------------

  bool hasProviderProfile = false;
  String? publicName;
  String? bio;
  int? experienceYears;
  String validationStatus = 'profile_incomplete';
  String availabilityStatus = 'available';
  bool resubmissionBlocked = false;
  String? rejectionReason;
  String? submittedAt;

  /// `{id, serviceTypeId, title, active, packs: [{id, title, price,
  /// durationMinutes, active, options: []}]}`.
  final List<JsonMap> services = <JsonMap>[];

  List<String> zoneIds = <String>[];
  List<JsonMap> slots = <JsonMap>[];

  /// Toutes les versions, la plus récente d'abord.
  final List<JsonMap> documentVersions = <JsonMap>[];

  /// Champs que la soumission refuse MALGRÉ `canSubmit` — la course du
  /// scénario 4.7 : l'état a changé côté service entre l'affichage et le clic.
  List<String>? submitRejects;

  final List<String> journal = <String>[];

  int callsTo(String method, String path) =>
      journal.where((String entry) => entry == '$method $path').length;

  // --- Checklist — le calcul du service, pas celui de l'écran --------------------

  bool get _profileDone =>
      (publicName?.isNotEmpty ?? false) && (bio?.isNotEmpty ?? false);

  bool get _servicesDone => services.any(
    (JsonMap s) =>
        s['active'] == true &&
        (s['packs']! as List<Object?>).whereType<Map<Object?, Object?>>().any(
          (Map<Object?, Object?> p) => p['active'] == true,
        ),
  );

  JsonMap? get _currentDocument => documentVersions.firstOrNull;

  bool get _documentsDone {
    final JsonMap? current = _currentDocument;
    return current != null && current['status'] != 'rejected';
  }

  JsonMap get _checklist => <String, Object?>{
    'profile': _profileDone,
    'services': _servicesDone,
    'zones': zoneIds.isNotEmpty,
    'availabilities': slots.isNotEmpty,
    'documents': _documentsDone,
  };

  bool get canSubmit =>
      _checklist.values.every((Object? done) => done == true) &&
      const <String>{
        'profile_incomplete',
        'changes_requested',
        'rejected',
      }.contains(validationStatus) &&
      !resubmissionBlocked;

  JsonMap overview() => <String, Object?>{
    'id': 'prov-e7a41f9c-0000-4000-8000-000000000001',
    'publicName': publicName ?? '',
    'bio': bio,
    'experienceYears': experienceYears,
    'validationStatus': validationStatus,
    'availabilityStatus': availabilityStatus,
    'score': 0,
    'reviewsCount': 0,
    'checklist': _checklist,
    'requiredDocumentTypes': <String>['id_card'],
    'rejectionReason': rejectionReason,
    'resubmissionBlocked': resubmissionBlocked,
    'submittedAt': submittedAt,
    'canSubmit': canSubmit,
    'createdAt': '2026-07-31T10:24:08.412Z',
  };

  JsonMap me() {
    final JsonMap base = JsonMap.of(fixtureData('auth/me', 'client'));
    base['hasProviderProfile'] = hasProviderProfile;
    base['providerId'] = hasProviderProfile ? 'prov-1' : null;
    base['providerValidationStatus'] = hasProviderProfile
        ? validationStatus
        : null;
    return base;
  }

  // --- Amorçages de scénario ------------------------------------------------------

  /// Un profil créé, avec présentation : la première case est verte.
  void seedProfile() {
    hasProviderProfile = true;
    publicName = 'Koffi Électricité Générale';
    bio = 'Électricien depuis 8 ans à Abidjan.';
    experienceYears = 8;
  }

  /// Les cinq cases vertes — prêt à soumettre.
  void seedFullDossier() {
    seedProfile();
    services.add(<String, Object?>{
      'id': 'svc-1',
      'serviceTypeId': 'st-21111111-1111-4111-8111-111111111111',
      'title': 'Dépannage plomberie à domicile',
      'active': true,
      'createdAt': '2026-07-31T10:30:12.001Z',
      'packs': <Object?>[
        <String, Object?>{
          'id': 'pack-1',
          'title': 'Intervention express',
          'price': 5000,
          'durationMinutes': 45,
          'active': true,
          'options': <Object?>[],
        },
      ],
    });
    zoneIds = <String>[kCocodyId];
    slots = <JsonMap>[
      <String, Object?>{'weekday': 1, 'startTime': '08:00', 'endTime': '12:00'},
    ];
    documentVersions.insert(0, <String, Object?>{
      'id': 'doc-1',
      'type': 'id_card',
      'status': 'pending',
      'version': 1,
      'rejectionReason': null,
      'reviewedAt': null,
      'createdAt': '2026-07-31T11:05:33.208Z',
      'file': <String, Object?>{
        'id': 'file-1',
        'originalName': 'cni-recto.jpg',
        'mimeType': 'image/jpeg',
        'size': 812304,
        'visibility': 'sensitive',
      },
    });
  }

  // --- Le service simulé ----------------------------------------------------------

  AdapterResponse handle(RequestOptions options, int index) {
    final String path = options.path;
    journal.add('${options.method} $path');
    final JsonMap body = switch (options.data) {
      final Map<Object?, Object?> data => data.cast<String, Object?>(),
      _ => const <String, Object?>{},
    };

    switch (path) {
      case '/me':
        return envelope(me());

      case '/categories':
        return fixture('booking/catalog', 'categories');

      case '/zones':
        return fixture('provider/zones', 'catalog');

      case '/providers/me':
        return _handleSelf(options, body);

      case '/providers/me/submit':
        return _handleSubmit();

      case '/providers/me/services':
        if (options.method == 'POST') {
          final JsonMap created = <String, Object?>{
            'id': 'svc-${services.length + 1}',
            'providerId': 'prov-1',
            'serviceTypeId': body['serviceTypeId'],
            'title': body['title'],
            'description': body['description'],
            'active': true,
            'createdAt': '2026-07-31T10:30:12.001Z',
          };
          services.add(<String, Object?>{...created, 'packs': <Object?>[]});
          return envelope(created, status: 201, message: 'Service déclaré');
        }
        return envelope(services);

      case '/providers/me/service-packs':
        final JsonMap? service = services
            .where((JsonMap s) => s['id'] == body['providerServiceId'])
            .firstOrNull;
        if (service == null) {
          return fixture('provider/services', 'packServiceNotFound');
        }
        final JsonMap pack = <String, Object?>{
          'id': 'pack-${services.length}',
          'providerServiceId': service['id'],
          'title': body['title'],
          'price': body['price'],
          'durationMinutes': body['durationMinutes'],
          'active': true,
          'options': <Object?>[],
        };
        (service['packs']! as List<Object?>).add(pack);
        return envelope(pack, status: 201, message: 'Formule créée');

      case '/providers/me/zones':
        if (options.method == 'PUT') {
          zoneIds = switch (body['zoneIds']) {
            final List<Object?> ids => ids.whereType<String>().toList(),
            _ => <String>[],
          };
          return envelope(
            _coveredZones(),
            message: 'Zones d\'intervention mises à jour',
          );
        }
        return envelope(_coveredZones());

      case '/providers/me/availabilities':
        if (options.method == 'PUT') {
          slots = switch (body['slots']) {
            final List<Object?> raw =>
              raw
                  .whereType<Map<Object?, Object?>>()
                  .map((Map<Object?, Object?> e) => e.cast<String, Object?>())
                  .toList(),
            _ => <JsonMap>[],
          };
          return envelope(slots, message: 'Disponibilités mises à jour');
        }
        return envelope(slots);

      case FileUploadService.uploadPath:
        return envelope(<String, Object?>{
          'id': 'file-up-${index + 1}',
          'originalName': 'cni-recto-net.jpg',
          'mimeType': 'image/jpeg',
          'size': 934112,
          'visibility': 'sensitive',
        }, message: 'Fichier enregistré');

      case '/providers/me/documents':
        if (options.method == 'POST') {
          return _handleDocumentDeposit(body);
        }
        return envelope(<String, Object?>{
          'requiredTypes': <String>['id_card'],
          'missingTypes': _documentsDone ? <String>[] : <String>['id_card'],
          'documents': documentVersions,
          'current': <Object?>[?_currentDocument],
        });

      default:
        // Options de formule — chemin imbriqué.
        if (path.startsWith('/providers/me/service-packs/') &&
            path.endsWith('/options')) {
          return envelope(
            <String, Object?>{
              'id': 'opt-1',
              'title': body['title'],
              'price': body['price'],
              'durationMinutes': body['durationMinutes'] ?? 0,
              'active': true,
            },
            status: 201,
            message: 'Option créée',
          );
        }
        return (
          404,
          <String, Object?>{
            'success': false,
            'message': 'Route non simulée : ${options.method} $path',
          },
        );
    }
  }

  AdapterResponse _handleSelf(RequestOptions options, JsonMap body) {
    switch (options.method) {
      case 'POST':
        if (hasProviderProfile) {
          // Reprise d'un parcours interrompu : l'application doit traiter ce
          // 409 comme un succès (scénario 4.3).
          return fixture('provider/self', 'alreadyExists');
        }
        hasProviderProfile = true;
        publicName = body['publicName'] as String?;
        bio = body['bio'] as String?;
        experienceYears = (body['experienceYears'] as num?)?.toInt();
        return envelope(
          overview(),
          status: 201,
          message:
              'Profil prestataire créé. Complétez votre dossier pour le '
              'soumettre.',
        );

      case 'PATCH':
        final bool touchesIdentity =
            body.containsKey('publicName') ||
            body.containsKey('bio') ||
            body.containsKey('experienceYears') ||
            body.containsKey('avatarFileId');
        if (touchesIdentity && validationStatus == 'pending_review') {
          // Le verrou du service (scénario 4.8).
          return fixture('provider/self', 'lockedInReview');
        }
        publicName = body['publicName'] as String? ?? publicName;
        bio = body['bio'] as String? ?? bio;
        if (body.containsKey('experienceYears')) {
          experienceYears = (body['experienceYears'] as num?)?.toInt();
        }
        availabilityStatus =
            body['availabilityStatus'] as String? ?? availabilityStatus;
        return envelope(overview(), message: 'Profil mis à jour');

      default:
        if (!hasProviderProfile) {
          return fixture('provider/self', 'noProfile');
        }
        return envelope(overview());
    }
  }

  AdapterResponse _handleSubmit() {
    if (resubmissionBlocked) {
      return fixture('provider/submit', 'resubmissionBlocked');
    }
    final List<String>? rejects = submitRejects;
    if (rejects != null || !canSubmit) {
      const Map<String, String> labels = <String, String>{
        'profile': 'Complétez votre nom public et votre présentation',
        'services':
            'Déclarez au moins un service avec une formule tarifaire active',
        'zones': 'Choisissez au moins une zone d\'intervention',
        'availabilities': 'Renseignez vos disponibilités hebdomadaires',
        'documents': 'Fournissez tous les justificatifs obligatoires',
      };
      final List<String> fields =
          rejects ??
          _checklist.entries
              .where((MapEntry<String, Object?> e) => e.value == false)
              .map((MapEntry<String, Object?> e) => e.key)
              .toList();
      return (
        400,
        <String, Object?>{
          'success': false,
          'message': 'Votre dossier n\'est pas complet',
          'errors': <Object?>[
            for (final String field in fields)
              <String, Object?>{
                'field': field,
                'code': 'checklist_incomplete',
                'message': labels[field],
              },
          ],
          'meta': <String, Object?>{
            'correlationId': 'us4-submit-0000-0000-000000000000',
          },
        },
      );
    }
    validationStatus = 'pending_review';
    submittedAt = '2026-08-01T09:00:00.000Z';
    rejectionReason = null;
    return envelope(overview(), message: 'Dossier soumis à la vérification');
  }

  AdapterResponse _handleDocumentDeposit(JsonMap body) {
    if (_currentDocument?['status'] == 'approved') {
      return fixture('provider/documents', 'alreadyApproved');
    }
    final JsonMap document = <String, Object?>{
      'id': 'doc-${documentVersions.length + 1}',
      'type': body['type'],
      'status': 'pending',
      'version': documentVersions.length + 1,
      'rejectionReason': null,
      'reviewedAt': null,
      'createdAt': '2026-08-01T09:30:00.000Z',
      'file': <String, Object?>{
        'id': body['fileId'],
        'originalName': 'cni-recto-net.jpg',
        'mimeType': 'image/jpeg',
        'size': 934112,
        'visibility': 'sensitive',
      },
    };
    documentVersions.insert(0, document);
    // L'effet de bord central de P7 : en `changes_requested`, le dépôt seul
    // renvoie le dossier en vérification (scénario 4.9).
    if (validationStatus == 'changes_requested') {
      validationStatus = 'pending_review';
      submittedAt = '2026-08-01T09:30:00.000Z';
      rejectionReason = null;
    }
    return envelope(document, status: 201, message: 'Justificatif transmis');
  }

  List<JsonMap> _coveredZones() => zoneCatalog
      .where((JsonMap zone) => zoneIds.contains(zone['id']))
      .toList(growable: false);
}

/// Déroule les scénarios 4.1 à 4.9.
void runUs4Scenarios() {
  late ProviderBackend backend;
  late RecordingAdapter adapter;
  late LocalDatabase database;
  late InMemoryTokenStore tokenStore;
  late FakeDocumentPicker picker;
  late ProviderContainer container;

  setUp(() {
    backend = ProviderBackend();
    adapter = RecordingAdapter(backend.handle);
    database = LocalDatabase.memory();
    tokenStore = InMemoryTokenStore();
    picker = FakeDocumentPicker(null);
    container = buildAppContainer(
      adapter: adapter,
      database: database,
      tokenStore: tokenStore,
      extraOverrides: <Override>[
        documentPickerProvider.overrideWithValue(picker),
      ],
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

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Laisse le vrai temps s'écouler — indispensable dès qu'un vrai fichier est
  /// lu (l'envoi multipart), l'horloge simulée ne faisant jamais aboutir les
  /// entrées-sorties réelles.
  Future<void> settleWithRealIo(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> drainSnackBars(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 5));

  /// Revient à l'écran précédent par le bouton de l'AppBar.
  ///
  /// ⚠️ Pas `tester.pageBack()` : il cherche un bouton Cupertino ou l'infobulle
  /// anglaise « Back », alors que l'application est localisée — le bouton
  /// Material s'appelle « Retour ».
  Future<void> goBack(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton).first);
    await tester.pumpAndSettle();
  }

  // --- 4.1 — Profil sans présentation : la ligne dit POURQUOI -------------------

  testWidgets('4.1 — créer un profil sans présentation laisse la ligne '
      '« profil » rouge, libellé « nom public ET présentation »', (
    WidgetTester tester,
  ) async {
    signIn();
    await start(tester, at: Routes.providerOnboardingProfile);

    await tester.enterText(
      find.widgetWithText(TextField, 'Nom public'),
      'Koffi Électricité Générale',
    );
    await tester.tap(find.text('Créer mon profil'));
    await tester.pumpAndSettle();

    // Le hub est atteint, et la première ligne explique le piège : la
    // présentation est facultative à la création mais exigée pour soumettre.
    expect(locationOf(container), Routes.providerChecklist);
    expect(
      find.text('Complétez votre nom public et votre présentation'),
      findsOneWidget,
    );
    expect(backend.hasProviderProfile, isTrue);
  });

  // --- 4.2 — Un service sans formule ne compte pas ------------------------------

  testWidgets('4.2 — déclarer un service SANS formule laisse « prestations » '
      'rouge', (WidgetTester tester) async {
    backend.seedProfile();
    signIn();
    await start(tester, at: Routes.providerChecklist);

    await tester.tap(find.text('Prestations'));
    await tester.pumpAndSettle();

    // Sélecteur à deux niveaux : catégorie puis type.
    await tester.tap(find.byType(DropdownMenu<Category>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plomberie').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownMenu<ServiceType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réparation de fuite').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Titre du service'),
      'Dépannage plomberie à domicile',
    );
    await scrollTo(tester, find.text('Déclarer ce service'));
    await tester.tap(find.text('Déclarer ce service'));
    await tester.pumpAndSettle();

    // P4 s'ouvre — mais le prestataire renonce à créer la formule.
    expect(find.text('Créer la formule'), findsOneWidget);
    await goBack(tester);

    // De retour sur P3, le service est là, signalé sans formule.
    expect(
      find.textContaining('Aucune formule active'),
      findsOneWidget,
      reason: 'le service décoratif doit être signalé, pas caché',
    );
    await goBack(tester);

    // Le hub relit la checklist : « prestations » est TOUJOURS rouge (4.2).
    expect(
      find.text(
        'Déclarez au moins un service avec une formule tarifaire active',
      ),
      findsOneWidget,
    );
    expect(backend.services, hasLength(1));
  });

  // --- 4.3 — Reprise : le 409 est un succès -------------------------------------

  testWidgets('4.3 — relancer la création sur un compte déjà pourvu arrive '
      'sur le hub, sans erreur affichée', (WidgetTester tester) async {
    backend.seedProfile();
    signIn();
    await start(tester, at: Routes.providerOnboardingProfile);

    await tester.enterText(
      find.widgetWithText(TextField, 'Nom public'),
      'Koffi Électricité Générale',
    );
    await tester.tap(find.text('Créer mon profil'));
    await tester.pumpAndSettle();

    // Le POST a répondu 409, le dépôt a enchaîné sur GET : succès de bout en
    // bout, pas la moindre erreur à l'écran (4.3).
    expect(backend.callsTo('POST', '/providers/me'), 1);
    expect(backend.callsTo('GET', '/providers/me'), greaterThanOrEqualTo(1));
    expect(locationOf(container), Routes.providerChecklist);
    expect(find.text('Ce compte a déjà un profil prestataire'), findsNothing);
    expect(find.text('Soumettre mon dossier'), findsOneWidget);
  });

  // --- 4.4 — Vider les zones exige une confirmation -----------------------------

  testWidgets('4.4 — vider la liste des zones demande une confirmation '
      'explicite, et rien ne part avant elle', (WidgetTester tester) async {
    backend
      ..seedProfile()
      ..zoneIds = <String>[kCocodyId, kMarcoryId];
    signIn();
    await start(tester, at: Routes.providerChecklist);

    await tester.tap(find.text('Zones d’intervention'));
    await tester.pumpAndSettle();

    // Décocher les deux zones couvertes.
    await tester.tap(find.text('Cocody, Abidjan'));
    await tester.tap(find.text('Marcory, Abidjan'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enregistrer mes zones'));
    await tester.pumpAndSettle();

    // La confirmation est là, et RIEN n'est encore parti.
    expect(find.text('Ne plus couvrir aucune zone ?'), findsOneWidget);
    expect(backend.callsTo('PUT', '/providers/me/zones'), 0);

    // Renoncer ne change rien…
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(backend.callsTo('PUT', '/providers/me/zones'), 0);
    expect(backend.zoneIds, hasLength(2));

    // …confirmer envoie l'état complet : une liste vide.
    await tester.tap(find.text('Enregistrer mes zones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tout retirer'));
    await tester.pumpAndSettle();

    expect(backend.callsTo('PUT', '/providers/me/zones'), 1);
    expect(backend.zoneIds, isEmpty);

    await drainSnackBars(tester);
  });

  // --- 4.5 — Chevauchement signalé AVANT l'envoi --------------------------------

  testWidgets('4.5 — deux créneaux qui se chevauchent sont refusés '
      'localement : aucun appel réseau', (WidgetTester tester) async {
    backend.seedProfile();
    signIn();
    await start(tester, at: Routes.providerChecklist);

    await tester.tap(find.text('Disponibilités'));
    await tester.pumpAndSettle();

    // Premier créneau du lundi : 08:00 – 12:00 (les valeurs proposées).
    await tester.tap(find.byTooltip('Ajouter un créneau le Lundi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('08:00 – 12:00'), findsOneWidget);

    // Second créneau identique : chevauchement, refusé AVANT tout envoi.
    await tester.tap(find.byTooltip('Ajouter un créneau le Lundi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.textContaining('se chevauchent'), findsOneWidget);
    expect(find.text('08:00 – 12:00'), findsOneWidget);
    expect(
      backend.callsTo('PUT', '/providers/me/availabilities'),
      0,
      reason: 'le refus est local — le service n\'est jamais sollicité (4.5)',
    );
  });

  // --- 4.6 — 12 Mo : refus local, zéro réseau -----------------------------------

  testWidgets('4.6 — un justificatif au-delà de 10 Mo est refusé avant tout '
      'appel réseau', (WidgetTester tester) async {
    backend.seedProfile();
    // Un vrai fichier trop lourd : le contrôle lit sa taille sur le disque.
    final File oversized = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'prestgo_us4_oversized.jpg',
    )..writeAsBytesSync(Uint8List(11 * 1024 * 1024));
    addTearDown(oversized.deleteSync);
    picker.candidate = UploadCandidate(
      path: oversized.path,
      mimeType: 'image/jpeg',
    );

    signIn();
    await start(tester, at: Routes.providerChecklist);

    await tester.tap(find.text('Justificatifs'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Déposer'));
    await tester.pumpAndSettle();

    expect(
      find.text('Fichier trop volumineux (maximum 10 Mo).'),
      findsOneWidget,
    );
    expect(
      backend.callsTo('POST', FileUploadService.uploadPath),
      0,
      reason: 'un dépassement ne part JAMAIS sur le réseau (4.6, R7)',
    );
    expect(backend.callsTo('POST', '/providers/me/documents'), 0);
  });

  // --- 4.7 — Les lignes rouges sont celles du service ---------------------------

  testWidgets('4.7 — un refus de soumission marque EXACTEMENT les lignes '
      'désignées par le service', (WidgetTester tester) async {
    backend
      ..seedFullDossier()
      // La course : `canSubmit` était vrai à l'affichage, mais le service
      // constate deux manques au moment du dépôt.
      ..submitRejects = <String>['profile', 'documents'];
    signIn();
    await start(tester, at: Routes.providerChecklist);

    await scrollTo(tester, find.text('Soumettre mon dossier'));
    await tester.tap(find.text('Soumettre mon dossier'));
    await tester.pumpAndSettle();

    // Les deux lignes désignées, avec le libellé officiel du service…
    expect(
      find.text('Complétez votre nom public et votre présentation'),
      findsOneWidget,
    );
    expect(
      find.text('Fournissez tous les justificatifs obligatoires'),
      findsOneWidget,
    );
    // …et pas une de plus (4.7).
    expect(
      find.text('Choisissez au moins une zone d’intervention'),
      findsNothing,
    );
    expect(
      find.text('Renseignez vos disponibilités hebdomadaires'),
      findsNothing,
    );
    expect(backend.validationStatus, 'profile_incomplete');
  });

  // --- 4.8 — Verrou de vérification, disponibilité ouverte ----------------------

  testWidgets('4.8 — en vérification, l\'identité est en lecture seule mais '
      'l\'interrupteur de disponibilité fonctionne', (
    WidgetTester tester,
  ) async {
    backend
      ..seedFullDossier()
      ..validationStatus = 'pending_review'
      ..submittedAt = '2026-07-31T14:02:51.007Z';
    signIn();
    await start(tester);

    // Le gardien a routé sur le suivi.
    expect(locationOf(container), Routes.providerStatus);
    expect(find.text('Dossier en cours de vérification'), findsOneWidget);

    await scrollTo(tester, find.text('Voir mon profil'));
    await tester.tap(find.text('Voir mon profil'));
    await tester.pumpAndSettle();

    // Champs d'identité grisés — le verrou est celui du service, l'écran le
    // matérialise (4.8).
    final TextField publicName = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Nom public'),
    );
    expect(publicName.enabled, isFalse);
    expect(find.text('Enregistrer'), findsNothing);

    // L'interrupteur, lui, répond : « Occupé » part, seul, en PATCH.
    await scrollTo(tester, find.text('Occupé'));
    await tester.tap(find.text('Occupé'));
    await tester.pumpAndSettle();

    expect(backend.availabilityStatus, 'busy');
    final RequestOptions patch = adapter.calls.lastWhere(
      (RequestOptions call) =>
          call.method == 'PATCH' && call.path == '/providers/me',
    );
    expect(
      patch.data,
      <String, Object?>{'availabilityStatus': 'busy'},
      reason:
          'le moindre champ d\'identité dans ce corps déclencherait le '
          'verrou',
    );
    expect(
      find.text(
        'Votre fiche reste visible et réservable : seule la pastille change.',
      ),
      findsOneWidget,
    );
  });

  // --- 4.9 — Redépôt en corrections demandées -----------------------------------

  testWidgets('4.9 — déposer un justificatif en « corrections demandées » '
      'renvoie le dossier en vérification et retire « Re-soumettre »', (
    WidgetTester tester,
  ) async {
    backend
      ..seedFullDossier()
      ..validationStatus = 'changes_requested'
      ..submittedAt = '2026-07-31T14:02:51.007Z'
      ..rejectionReason =
          'Votre pièce d\'identité est illisible : redéposez une photo nette.';
    // Un vrai petit fichier valide : l'envoi multipart lit le disque.
    final File valid = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'prestgo_us4_valid.jpg',
    )..writeAsBytesSync(Uint8List.fromList(List<int>.filled(2048, 7)));
    // Suppression au mieux : sous Windows, le flux multipart peut garder le
    // fichier ouvert un instant après le test.
    addTearDown(() {
      try {
        valid.deleteSync();
      } on FileSystemException {
        // Le dossier temporaire du système s'en chargera.
      }
    });
    picker.candidate = UploadCandidate(
      path: valid.path,
      mimeType: 'image/jpeg',
    );

    signIn();
    await start(tester);

    // Le suivi montre le motif ET le bouton de re-soumission (checklist
    // complète, motif sur la présentation du document).
    expect(locationOf(container), Routes.providerStatus);
    expect(find.text('Corrections demandées'), findsOneWidget);
    await scrollTo(tester, find.text('Re-soumettre mon dossier'));

    // Redéposer le justificatif…
    await scrollTo(tester, find.text('Mes justificatifs'));
    await tester.tap(find.text('Mes justificatifs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remplacer'));
    await settleWithRealIo(tester);

    // …le dossier est reparti TOUT SEUL, et l'écran l'annonce (4.9).
    expect(backend.validationStatus, 'pending_review');
    expect(find.textContaining('reparti en vérification'), findsOneWidget);
    await drainSnackBars(tester);

    // De retour sur le suivi : plus de « Re-soumettre » à proposer.
    await goBack(tester);
    expect(find.text('Dossier en cours de vérification'), findsOneWidget);
    expect(find.text('Re-soumettre mon dossier'), findsNothing);
  });
}
