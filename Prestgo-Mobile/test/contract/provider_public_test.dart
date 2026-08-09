// T086 — Contrat de la fiche publique (opération 26).
//
// L'exigence tient en une phrase : **tout l'écran en un seul appel** (FR-027). Ce
// fichier la vérifie section par section, parce qu'une section oubliée dans la
// désérialisation ne se verrait qu'à l'écran, sous la forme d'un bloc vide.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/features/search/data/search_repository.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';

import '../support/api_harness.dart';
import '../support/fixtures.dart';

const String providerId = 'p-4c8e1a05-7b3d-4f62-9e08-1a5c7d9e0b3f';

ApiHarness harnessFor(String caseName) {
  final (int status, Map<String, Object?> body) = fixture(
    'booking/provider_public',
    caseName,
  );
  return ApiHarness.always(status, body);
}

Future<ProviderPublicProfile> profileFrom(String caseName) =>
    SearchRepository(harnessFor(caseName).client).publicProfile(providerId);

void main() {
  group('Un seul appel compose tout l’écran', () {
    test('toutes les sections sont présentes', () async {
      final ApiHarness harness = harnessFor('complete');

      final ProviderPublicProfile profile = await SearchRepository(
        harness.client,
      ).publicProfile(providerId);

      expect(profile.publicName, 'Adjoua Plomberie');
      expect(profile.bio, isNotNull);
      expect(profile.experienceYears, 15);
      expect(profile.categories, hasLength(1));
      expect(profile.services, hasLength(1));
      expect(profile.portfolio, hasLength(1));
      expect(profile.availability, hasLength(8));
      expect(profile.upcomingUnavailabilities, hasLength(1));
      expect(profile.zones, hasLength(2));
      expect(profile.ratingDistribution, hasLength(5));
      expect(profile.latestReviews, hasLength(2));

      expect(
        harness.callCount,
        1,
        reason:
            'multiplier les allers-retours ferait apparaître l’écran par morceaux '
            'sur une connexion mobile',
      );
      expect(harness.lastUrl, '$kTestBaseUrl/providers/$providerId/public');
    });

    test('les formules portent leurs options', () async {
      final ProviderPublicProfile profile = await profileFrom('complete');

      expect(profile.packs, hasLength(2));
      final ServicePack diagnostic = profile.packs.first;
      expect(diagnostic.price, 5000);
      expect(diagnostic.durationMinutes, 45);
      expect(diagnostic.options, hasLength(2));
      expect(
        diagnostic.options.last.durationMinutes,
        0,
        reason: 'une option peut coûter plus cher sans prendre plus de temps',
      );
      expect(profile.packs.last.options, isEmpty);
    });

    test('une option est résolue sur sa formule, pas globalement', () async {
      final ProviderPublicProfile profile = await profileFrom('complete');
      final ServicePack diagnostic = profile.packs.first;
      final ServicePack installation = profile.packs.last;

      const String optionId = 'opt-81111111-1111-4111-8111-111111111111';
      expect(diagnostic.optionById(optionId), isNotNull);
      expect(
        installation.optionById(optionId),
        isNull,
        reason:
            'le service refuse une option qui n’appartient pas à la formule choisie',
      );
    });

    test('la répartition des notes est indexée par note', () async {
      final ProviderPublicProfile profile = await profileFrom('complete');

      expect(profile.ratingDistribution[5], 8);
      expect(profile.ratingDistribution[1], 0);
      expect(
        profile.ratingDistribution.values.reduce((int a, int b) => a + b),
        12,
        reason: 'le total doit concorder avec `reviewsCount`',
      );
    });

    test('un avis sans commentaire ni auteur reste affichable', () async {
      final ProviderPublicProfile profile = await profileFrom('complete');

      final ProviderReview anonymous = profile.latestReviews.last;
      expect(anonymous.comment, isNull);
      expect(anonymous.authorFirstName, isNull);
      expect(
        anonymous.authorLabel,
        'Client PRESTGO',
        reason:
            'identifier complètement l’auteur d’un avis public serait une fuite',
      );
    });
  });

  group('Agenda — aucune conversion de fuseau', () {
    test('les heures restent des chaînes `HH:MM`', () async {
      final ProviderPublicProfile profile = await profileFrom('complete');

      final List<WeeklySlot> monday = profile.slotsForWeekday(1);
      expect(monday, hasLength(2));
      expect(monday.first.startTime, '08:00');
      expect(monday.first.endTime, '12:00');
      expect(monday.last.startTime, '14:00');
    });

    test('les créneaux d’un jour sont triés par heure de début', () async {
      final ProviderPublicProfile profile = await profileFrom('complete');

      final List<WeeklySlot> monday = profile.slotsForWeekday(1);
      expect(monday.first.start < monday.last.start, isTrue);
    });

    test('la durée totale doit tenir ENTIÈREMENT dans le créneau', () async {
      final ProviderPublicProfile profile = await profileFrom('complete');
      final WeeklySlot morning = profile.slotsForWeekday(1).first;

      // 08:00–12:00, intervention d'une heure.
      expect(morning.contains(ClockTime.parse('11:00'), 60), isTrue);
      expect(
        morning.contains(ClockTime.parse('11:30'), 60),
        isFalse,
        reason:
            'commencer à 11 h 30 une heure d’intervention ferait déborder le '
            'prestataire (scénario 2.7)',
      );
      expect(morning.contains(ClockTime.parse('07:30'), 60), isFalse);
    });

    test('les absences sont des instants, pas des heures de mur', () async {
      final ProviderPublicProfile profile = await profileFrom('complete');

      final Unavailability absence = profile.upcomingUnavailabilities.single;
      expect(absence.startAt.toUtc().year, 2026);
      expect(
        absence.overlaps(
          DateTime.utc(2026, 8, 6, 9),
          DateTime.utc(2026, 8, 6, 10),
        ),
        isTrue,
      );
      expect(
        absence.overlaps(
          DateTime.utc(2026, 8, 3, 9),
          DateTime.utc(2026, 8, 3, 10),
        ),
        isFalse,
      );
    });

    test(
      '`isAbsentDuring` couvre la durée entière de l’intervention',
      () async {
        final ProviderPublicProfile profile = await profileFrom('complete');

        // Commence avant l'absence, mais déborde dessus.
        expect(
          profile.isAbsentDuring(DateTime.utc(2026, 8, 4, 23, 30), 60),
          isTrue,
        );
        expect(
          profile.isAbsentDuring(DateTime.utc(2026, 8, 4, 9), 60),
          isFalse,
        );
      },
    );
  });

  group('Cas limites', () {
    test('un prestataire sans avis ni offre reste consultable', () async {
      final ProviderPublicProfile profile = await profileFrom('newProvider');

      expect(profile.isNew, isTrue);
      expect(profile.startingPrice, isNull);
      expect(profile.packs, isEmpty);
      expect(
        profile.isBookable,
        isFalse,
        reason: 'sans formule, aucun bouton de réservation ne doit s’afficher',
      );
    });

    test('404 — un dossier non approuvé n’a pas de fiche publique', () async {
      await expectLater(
        profileFrom('notApproved'),
        throwsA(
          isA<ApiException>()
              .having((ApiException e) => e.isNotFound, 'isNotFound', isTrue)
              .having(
                (ApiException e) => e.message,
                'message',
                'Prestataire introuvable',
              ),
        ),
      );
    });
  });

  group('Cache mémoire', () {
    test('une fiche déjà chargée n’est pas rechargée', () async {
      final ApiHarness harness = harnessFor('complete');
      final SearchRepository repository = SearchRepository(harness.client);

      await repository.publicProfile(providerId);
      await repository.publicProfile(providerId);

      expect(harness.callCount, 1);
      expect(repository.loadedProfile(providerId), isNotNull);
    });

    test('`refresh` force la relecture', () async {
      final ApiHarness harness = harnessFor('complete');
      final SearchRepository repository = SearchRepository(harness.client);

      await repository.publicProfile(providerId);
      await repository.publicProfile(providerId, refresh: true);

      expect(
        harness.callCount,
        2,
        reason:
            'le retour depuis une réservation doit montrer un agenda à jour',
      );
    });

    test('le cache est en mémoire seulement — aucune écriture sur disque', () {
      // `SearchRepository` ne reçoit pas de `CacheDao` : sa construction le prouve.
      // Un résultat de recherche servi depuis le disque proposerait des créneaux
      // déjà pris et des prestataires devenus indisponibles.
      final SearchRepository repository = SearchRepository(
        harnessFor('complete').client,
      );
      expect(repository.loadedProfile(providerId), isNull);
    });
  });
}
