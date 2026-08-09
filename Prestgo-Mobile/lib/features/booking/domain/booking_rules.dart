// Règles de composition d'une réservation (T089, FR-029 à FR-032).
//
// Fonctions pures, sans réseau ni état : ce sont elles qui permettent au sélecteur de
// ne proposer que des créneaux que le service acceptera, plutôt que de laisser
// l'utilisateur découvrir le refus après coup.
//
// ⚠️ **Le référentiel horaire de l'agenda est UTC.** Le service dérive le jour et
// l'heure d'un créneau des composantes UTC de l'instant réservé
// (`scheduledAt.getUTCDay()`, `getUTCHours()`), puis les compare aux chaînes `HH:MM`
// déclarées par le prestataire. Un agenda « lundi 08:00–18:00 » signifie donc
// 08:00–18:00 **UTC**.
//
// Conséquence directe, et c'est le piège de ce fichier : l'instant réservé se compose
// avec `DateTime.utc(année, mois, jour, heure, minute)` — jamais avec un `DateTime`
// local converti ensuite. Sur un appareil réglé sur un autre fuseau, la seconde
// méthode décalerait l'heure et le service répondrait « Le prestataire n'est pas
// disponible sur ce créneau », sans qu'aucun écran ne puisse expliquer pourquoi.
// (La Côte d'Ivoire étant à UTC+0 toute l'année, l'écart ne se voit pas sur un
// appareil réglé localement — raison de plus pour l'écrire ici.)

import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';

/// Granularité des débuts proposés.
///
/// Le service ne l'impose pas : c'est un choix d'écran. Trente minutes donne assez
/// de choix sans produire une liste illisible sur une journée de dix heures.
const Duration kSlotGranularity = Duration(minutes: 30);

abstract final class BookingRules {
  /// Prix total — formule plus options. C'est le montant que le service figera.
  static int totalPrice({
    required ServicePack pack,
    required Iterable<PackOption> options,
  }) =>
      pack.price +
      options.fold<int>(0, (int sum, PackOption option) => sum + option.price);

  /// Durée totale — formule plus options.
  ///
  /// Une option peut n'ajouter aucune durée : « déplacement hors horaires » coûte
  /// plus cher sans prendre plus de temps.
  static int totalDurationMinutes({
    required ServicePack pack,
    required Iterable<PackOption> options,
  }) =>
      pack.durationMinutes +
      options.fold<int>(
        0,
        (int sum, PackOption option) => sum + option.durationMinutes,
      );

  /// Premier instant réservable, délai minimum compris.
  ///
  /// [minLeadTimeMinutes] vient de `GET /settings/public`, lu au démarrage — jamais
  /// d'une constante écrite dans un écran (porte G3).
  static DateTime earliestStart({
    required DateTime now,
    required int minLeadTimeMinutes,
  }) => now.toUtc().add(Duration(minutes: minLeadTimeMinutes));

  /// Vrai si [scheduledAt] respecte le délai minimum en vigueur.
  static bool respectsLeadTime({
    required DateTime scheduledAt,
    required DateTime now,
    required int minLeadTimeMinutes,
  }) => !scheduledAt.toUtc().isBefore(
    earliestStart(now: now, minLeadTimeMinutes: minLeadTimeMinutes),
  );

  /// Compose l'instant réservé à partir d'un jour et d'une heure d'agenda.
  ///
  /// Voir l'avertissement en tête de fichier : les composantes sont **UTC**.
  static DateTime instantFor({
    required DateTime day,
    required ClockTime time,
  }) => DateTime.utc(day.year, day.month, day.day, time.hour, time.minute);

  /// Jour de la semaine d'un instant, convention du service (0 = dimanche).
  ///
  /// Lu en UTC, comme le fait `scheduledAt.getUTCDay()`.
  static int weekdayOf(DateTime instant) => instant.toUtc().weekday % 7;

  /// Heures de début proposables un jour donné.
  ///
  /// Un début n'est retenu que si les quatre conditions du service sont réunies :
  ///   1. il tombe dans un créneau hebdomadaire du jour ;
  ///   2. la durée **totale** y tient entièrement — c'est le scénario 2.7 ;
  ///   3. aucune absence annoncée ne recouvre l'intervention ;
  ///   4. le délai minimum en vigueur est respecté — scénario 2.6.
  ///
  /// Les chevauchements avec les missions déjà engagées ne sont **pas** vérifiables
  /// ici : l'application ne connaît pas l'agenda réel du prestataire. Le service
  /// tranche, et l'écran ramène à cette étape avec son message (FR-035).
  static List<ClockTime> availableStartTimes({
    required ProviderPublicProfile provider,
    required DateTime day,
    required int durationMinutes,
    required DateTime now,
    required int minLeadTimeMinutes,
    Duration granularity = kSlotGranularity,
  }) {
    if (durationMinutes <= 0) {
      return const <ClockTime>[];
    }

    final DateTime utcDay = day.toUtc();
    final int weekday = utcDay.weekday % 7;
    final DateTime earliest = earliestStart(
      now: now,
      minLeadTimeMinutes: minLeadTimeMinutes,
    );
    final int step = granularity.inMinutes;
    final List<ClockTime> starts = <ClockTime>[];

    for (final WeeklySlot slot in provider.slotsForWeekday(weekday)) {
      // On part du début du créneau et on avance par pas, tant que la durée tient.
      for (
        int minutes = slot.start.minutesOfDay;
        minutes + durationMinutes <= slot.end.minutesOfDay;
        minutes += step
      ) {
        final ClockTime start = ClockTime.parse(
          '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
          '${(minutes % 60).toString().padLeft(2, '0')}',
        );
        final DateTime instant = instantFor(day: utcDay, time: start);

        if (instant.isBefore(earliest)) {
          continue;
        }
        if (provider.isAbsentDuring(instant, durationMinutes)) {
          continue;
        }
        if (!starts.contains(start)) {
          starts.add(start);
        }
      }
    }

    starts.sort();
    return List<ClockTime>.unmodifiable(starts);
  }

  /// Vrai si au moins un début est proposable ce jour-là.
  ///
  /// Sert à griser les jours du calendrier plutôt qu'à ouvrir une liste vide.
  static bool hasAvailability({
    required ProviderPublicProfile provider,
    required DateTime day,
    required int durationMinutes,
    required DateTime now,
    required int minLeadTimeMinutes,
    Duration granularity = kSlotGranularity,
  }) => availableStartTimes(
    provider: provider,
    day: day,
    durationMinutes: durationMinutes,
    now: now,
    minLeadTimeMinutes: minLeadTimeMinutes,
    granularity: granularity,
  ).isNotEmpty;

  /// Durée formatée — « 1 h 15 », « 45 min ».
  static String formatDuration(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    }
    final int hours = minutes ~/ 60;
    final int rest = minutes % 60;
    return rest == 0
        ? '$hours h'
        : '$hours h ${rest.toString().padLeft(2, '0')}';
  }
}
