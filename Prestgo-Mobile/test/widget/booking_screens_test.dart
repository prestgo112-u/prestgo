// T118 — États de recherche et récapitulatif de réservation.
//
// Ce que ces tests protègent :
//   • **la recherche** — les trois valeurs absentes se masquent au lieu de s'afficher
//     à zéro, et un résultat vide propose les seules suites qui s'appliquent ;
//   • **le récapitulatif** — le total suit les options en direct, un refus métier
//     ramène à l'étape fautive sans perdre le brouillon, et la clé d'idempotence
//     survit à une reconstruction.
//
// Ce dernier point est le plus important de la phase : une clé régénérée à chaque
// `build` annulerait toute la protection contre les doubles réservations, et rien à
// l'écran ne le montrerait.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/idempotency.dart';
import 'package:prestgo_mobile/core/format/money.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_draft.dart';
import 'package:prestgo_mobile/features/booking/presentation/booking_draft_controller.dart';
import 'package:prestgo_mobile/features/booking/presentation/booking_error_mapper.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/search/domain/provider_search.dart';
import 'package:prestgo_mobile/features/search/presentation/search_states.dart';
import 'package:prestgo_mobile/features/search/presentation/widgets/provider_card.dart';

import '../support/fixtures.dart';

const SearchPosition abidjan = SearchPosition(latitude: 5.35, longitude: -3.98);

ProviderSearchResult resultAt(int index) => ProviderSearchResult.fromJson(
  (fixtureBody('booking/search', 'firstPage')['data']! as List<Object?>)[index]
      as Map<String, Object?>,
);

ProviderPublicProfile get providerProfile => ProviderPublicProfile.fromJson(
  fixtureData('booking/provider_public', 'complete'),
);

Address get address =>
    Address.fromJson(fixtureData('booking/addresses', 'created'));

Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  ProviderScope(
    child: MaterialApp(home: Scaffold(body: child)),
  ),
);

void main() {
  group('Carte de résultat — ce qui se masque', () {
    testWidgets('un prestataire noté affiche sa note', (
      WidgetTester tester,
    ) async {
      await pump(tester, ProviderCard(provider: resultAt(0), onTap: () {}));

      expect(find.text('4.8'), findsOneWidget);
      expect(find.text('(12 avis)'), findsOneWidget);
      expect(find.text('Nouveau'), findsNothing);
    });

    testWidgets('sans avis, « Nouveau » remplace la note', (
      WidgetTester tester,
    ) async {
      await pump(tester, ProviderCard(provider: resultAt(1), onTap: () {}));

      expect(find.text('Nouveau'), findsOneWidget);
      expect(
        find.text('0.0'),
        findsNothing,
        reason:
            'une note de 0 ferait passer un prestataire neuf pour un mauvais',
      );
    });

    testWidgets('la distance est affichée quand elle existe', (
      WidgetTester tester,
    ) async {
      await pump(tester, ProviderCard(provider: resultAt(0), onTap: () {}));
      expect(find.text('1.2 km'), findsOneWidget);
    });

    testWidgets('distance et prix absents sont masqués, pas mis à zéro', (
      WidgetTester tester,
    ) async {
      await pump(tester, ProviderCard(provider: resultAt(2), onTap: () {}));

      expect(find.textContaining('km'), findsNothing);
      expect(find.textContaining('À partir de'), findsNothing);
      // La carte reste utile : le nom et la note sont là.
      expect(find.text('Ama Électricité'), findsOneWidget);
    });

    testWidgets('le prix d’appel est formaté en francs CFA', (
      WidgetTester tester,
    ) async {
      await pump(tester, ProviderCard(provider: resultAt(0), onTap: () {}));
      expect(find.text('À partir de ${Money.format(5000)}'), findsOneWidget);
    });
  });

  group('Résultat vide — les suites proposées', () {
    testWidgets('avec position et filtres, les deux suites sont offertes', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        SearchEmptyView(
          query: const ProviderSearchQuery(
            position: abidjan,
            categoryId: 'cat-1',
          ),
          onWidenRadius: () {},
          onClearFilters: () {},
        ),
      );

      expect(find.text('Élargir à 20 km'), findsOneWidget);
      expect(find.text('Retirer les filtres'), findsOneWidget);
    });

    testWidgets('sans position, « élargir » n’a aucun sens', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        SearchEmptyView(
          query: const ProviderSearchQuery(categoryId: 'cat-1'),
          onWidenRadius: () {},
          onClearFilters: () {},
        ),
      );

      expect(find.textContaining('Élargir'), findsNothing);
      expect(find.text('Retirer les filtres'), findsOneWidget);
    });

    testWidgets('sans filtre, « retirer les filtres » non plus', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        SearchEmptyView(
          query: const ProviderSearchQuery(position: abidjan),
          onWidenRadius: () {},
          onClearFilters: () {},
        ),
      );

      expect(find.text('Retirer les filtres'), findsNothing);
      expect(find.text('Élargir à 20 km'), findsOneWidget);
    });

    testWidgets('au rayon maximal, le texte le dit', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        SearchEmptyView(
          query: const ProviderSearchQuery(position: abidjan, radiusKm: 50),
          onWidenRadius: () {},
          onClearFilters: () {},
        ),
      );

      expect(find.textContaining('50 km, le maximum couvert'), findsOneWidget);
      expect(find.textContaining('Élargir'), findsNothing);
    });

    testWidgets('un créneau demandé explique le vide autrement', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        SearchEmptyView(
          query: ProviderSearchQuery(
            position: abidjan,
            slot: SearchSlot(
              date: DateTime.utc(2026, 8, 3),
              startTime: '09:00',
            ),
          ),
          onWidenRadius: () {},
          onClearFilters: () {},
        ),
      );

      expect(
        find.textContaining('Personne n’est disponible sur ce créneau'),
        findsOneWidget,
      );
    });

    testWidgets('les deux suites sont réellement branchées', (
      WidgetTester tester,
    ) async {
      var widened = 0;
      var cleared = 0;
      await pump(
        tester,
        SearchEmptyView(
          query: const ProviderSearchQuery(
            position: abidjan,
            categoryId: 'cat-1',
          ),
          onWidenRadius: () => widened++,
          onClearFilters: () => cleared++,
        ),
      );

      await tester.tap(find.text('Élargir à 20 km'));
      await tester.tap(find.text('Retirer les filtres'));
      expect(widened, 1);
      expect(cleared, 1);
    });
  });

  group('Pied de liste paginée', () {
    testWidgets('un chargement en cours montre l’indicateur', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        SearchListFooter(isLoadingMore: true, hasError: false, onRetry: () {}),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('un échec propose la reprise sans effacer la liste', (
      WidgetTester tester,
    ) async {
      var retried = 0;
      await pump(
        tester,
        SearchListFooter(
          isLoadingMore: false,
          hasError: true,
          onRetry: () => retried++,
        ),
      );

      await tester.tap(find.text('Charger la suite'));
      expect(retried, 1);
    });

    testWidgets('en fin de liste, rien n’est affiché', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        SearchListFooter(isLoadingMore: false, hasError: false, onRetry: () {}),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Charger la suite'), findsNothing);
    });
  });

  group('Brouillon — total recalculé en direct (FR-030)', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      container.read(bookingDraftProvider.notifier).start(providerProfile);
    });

    tearDown(() => container.dispose());

    test('cocher une option change prix et durée', () {
      final BookingDraftController controller = container.read(
        bookingDraftProvider.notifier,
      );
      final ProviderPublicProfile provider = providerProfile;
      final ServicePack pack = provider.packs.first;

      controller.selectPack(pack);
      expect(container.read(bookingDraftProvider)!.draft.totalPrice, 5000);
      expect(
        container.read(bookingDraftProvider)!.draft.totalDurationMinutes,
        45,
      );

      controller.toggleOption(pack.options.first.id);
      expect(container.read(bookingDraftProvider)!.draft.totalPrice, 6500);
      expect(
        container.read(bookingDraftProvider)!.draft.totalDurationMinutes,
        60,
      );

      controller.toggleOption(pack.options.first.id);
      expect(container.read(bookingDraftProvider)!.draft.totalPrice, 5000);
    });
  });

  group('Clé d’idempotence — cycle de vie (FR-033)', () {
    late ProviderContainer container;
    late BookingDraftController controller;

    setUp(() {
      container = ProviderContainer();
      controller = container.read(bookingDraftProvider.notifier);
      final ProviderPublicProfile provider = providerProfile;
      controller
        ..start(provider)
        ..selectPack(provider.packs.first)
        ..selectSchedule(DateTime.utc(2026, 8, 3, 9))
        ..selectAddress(address);
    });

    tearDown(() => container.dispose());

    test('deux affichages du récapitulatif rendent la MÊME clé', () {
      final IdempotencyKey first = controller.prepareSummary();
      final IdempotencyKey second = controller.prepareSummary();

      expect(
        second.value,
        first.value,
        reason:
            'une clé neuve à chaque reconstruction annulerait la protection '
            'contre les doubles réservations',
      );
    });

    test('modifier une option émet une clé NEUVE (scénario 2.10)', () {
      final IdempotencyKey before = controller.prepareSummary();

      controller.toggleOption(providerProfile.packs.first.options.first.id);
      // Changer les options efface la date : on la repose pour ne comparer que
      // l'effet de l'option.
      controller.selectSchedule(DateTime.utc(2026, 8, 3, 9));
      final IdempotencyKey after = controller.prepareSummary();

      expect(after.value, isNot(before.value));
    });

    test('changer d’adresse émet aussi une clé neuve', () {
      final IdempotencyKey before = controller.prepareSummary();

      controller.selectAddress(
        Address.fromJson(
          (fixtureBody('booking/addresses', 'list')['data']! as List<Object?>)
                  .first
              as Map<String, Object?>,
        ),
      );
      final IdempotencyKey after = controller.prepareSummary();

      expect(after.value, isNot(before.value));
    });

    test('repartir d’un brouillon neuf abandonne la clé', () {
      controller.prepareSummary();
      expect(controller.currentKey, isNotNull);

      controller.start(providerProfile);
      expect(controller.currentKey, isNull);
    });
  });

  group('Refus métier → étape corrigeable (FR-035)', () {
    ApiException refusal(String caseName) {
      final (int status, Map<String, Object?> body) = fixture(
        'booking/booking',
        caseName,
      );
      return ApiException.fromResponse(statusCode: status, body: body);
    }

    test('adresse hors zone ramène à l’adresse, zones à l’appui', () {
      final BookingCorrection correction = BookingErrorMapper.map(
        refusal('addressOutOfZone'),
      );

      expect(correction.step, BookingStep.address);
      expect(correction.showsCoveredZones, isTrue);
      expect(
        correction.message,
        "Cette adresse n'est pas dans la zone d'intervention du prestataire",
        reason: 'le message du service est affiché tel quel (FR-088)',
      );
    });

    test('créneau pris ramène au créneau', () {
      expect(
        BookingErrorMapper.map(refusal('slotTaken')).step,
        BookingStep.schedule,
      );
      expect(
        BookingErrorMapper.map(refusal('slotNotAvailable')).step,
        BookingStep.schedule,
      );
      expect(
        BookingErrorMapper.map(refusal('providerAbsent')).step,
        BookingStep.schedule,
      );
    });

    test('délai trop court ramène au créneau, message chiffré compris', () {
      final BookingCorrection correction = BookingErrorMapper.map(
        refusal('leadTimeTooShort'),
      );

      expect(correction.step, BookingStep.schedule);
      expect(correction.message, contains('60 minutes'));
    });

    test('option inconnue ramène à la formule', () {
      expect(
        BookingErrorMapper.map(refusal('unknownOption')).step,
        BookingStep.pack,
      );
      expect(
        BookingErrorMapper.map(refusal('packNotFound')).step,
        BookingStep.pack,
      );
    });

    test('adresse non géolocalisée ramène à l’adresse', () {
      expect(
        BookingErrorMapper.map(refusal('addressNotGeolocated')).step,
        BookingStep.address,
      );
    });

    test('un débit dépassé n’est pas corrigeable — il faut attendre', () {
      final BookingCorrection correction = BookingErrorMapper.map(
        refusal('rateLimited'),
      );

      expect(correction.isRecoverable, isFalse);
      expect(correction.step, isNull);
    });

    test('un refus non reconnu reste affichable', () {
      final BookingCorrection correction = BookingErrorMapper.map(
        ApiException.fromResponse(
          statusCode: 400,
          body: const <String, Object?>{
            'success': false,
            'message': 'Une règle métier inédite',
          },
        ),
      );

      expect(correction.message, 'Une règle métier inédite');
      expect(correction.step, isNull);
      expect(
        correction.isRecoverable,
        isTrue,
        reason: 'le récapitulatif laisse revenir sur n’importe quelle étape',
      );
    });

    test('la correspondance survit à une apostrophe typographique', () {
      final BookingCorrection correction = BookingErrorMapper.map(
        ApiException.fromResponse(
          statusCode: 400,
          body: const <String, Object?>{
            'success': false,
            'message':
                'Cette adresse n’est pas dans la zone d’intervention du '
                'prestataire',
          },
        ),
      );

      expect(correction.step, BookingStep.address);
    });
  });
}
