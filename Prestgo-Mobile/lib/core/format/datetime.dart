// Dates et heures (R11).
//
// Deux régimes, à ne jamais confondre :
//
//   • **Dates d'intervention** — échangées en **UTC** (ISO 8601), affichées en heure
//     locale de l'appareil, qui coïncide avec UTC en Côte d'Ivoire. Envoyer une
//     heure locale fait refuser un créneau pourtant valide.
//
//   • **Heures d'agenda `HH:MM`** — manipulées comme des **chaînes**, jamais
//     converties de fuseau. Un prestataire en déplacement verrait sinon son agenda
//     décalé, et le contrôle de disponibilité du service compare le jour et l'heure
//     UTC de l'intervention à ces créneaux.

import 'package:intl/intl.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

/// Conversions des dates d'intervention.
abstract final class MissionDates {
  /// Forme envoyée au service : ISO 8601 en UTC.
  static String toApi(DateTime value) => value.toUtc().toIso8601String();

  /// Lit une date du service et la ramène en heure locale pour l'affichage.
  static DateTime fromApi(String raw) => DateTime.parse(raw).toLocal();

  /// Lit une date éventuellement absente.
  static DateTime? fromApiOrNull(String? raw) =>
      raw == null || raw.isEmpty ? null : fromApi(raw);

  /// Date au format `AAAA-MM-JJ`, tel que l'attend le filtre de recherche.
  static String toApiDate(DateTime value) =>
      DateFormat('yyyy-MM-dd').format(value);
}

/// Heure d'agenda `HH:MM` — **une chaîne**, pas un instant.
///
/// Ce type existe pour rendre impossible l'erreur la plus coûteuse du projet :
/// convertir un créneau hebdomadaire dans le fuseau de l'appareil.
class ClockTime implements Comparable<ClockTime> {
  const ClockTime._(this.hour, this.minute);

  /// Analyse `HH:MM` (24 h). Lève si le format est invalide.
  factory ClockTime.parse(String raw) {
    final ClockTime? parsed = ClockTime.tryParse(raw);
    if (parsed == null) {
      throw FormatException('Heure attendue au format HH:MM', raw);
    }
    return parsed;
  }

  /// Analyse `HH:MM`, ou `null` si la chaîne n'est pas une heure valide.
  static ClockTime? tryParse(String raw) {
    if (!AppFormats.timeOfDayPattern.hasMatch(raw)) {
      return null;
    }
    return ClockTime._(
      int.parse(raw.substring(0, 2)),
      int.parse(raw.substring(3, 5)),
    );
  }

  final int hour;
  final int minute;

  int get minutesOfDay => hour * 60 + minute;

  /// Forme transmise au service et affichée à l'écran — identiques.
  String get value =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(ClockTime other) => minutesOfDay.compareTo(other.minutesOfDay);

  bool operator <(ClockTime other) => minutesOfDay < other.minutesOfDay;
  bool operator <=(ClockTime other) => minutesOfDay <= other.minutesOfDay;
  bool operator >(ClockTime other) => minutesOfDay > other.minutesOfDay;
  bool operator >=(ClockTime other) => minutesOfDay >= other.minutesOfDay;

  @override
  bool operator ==(Object other) =>
      other is ClockTime && other.minutesOfDay == minutesOfDay;

  @override
  int get hashCode => minutesOfDay;

  @override
  String toString() => value;
}

/// Jours de la semaine selon la convention du service : **0 = dimanche**.
abstract final class Weekdays {
  static const List<String> labels = <String>[
    'Dimanche',
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
  ];

  static bool isValid(int weekday) =>
      weekday >= AppFormats.firstWeekday && weekday <= AppFormats.lastWeekday;

  static String label(int weekday) {
    if (!isValid(weekday)) {
      throw RangeError.range(
        weekday,
        AppFormats.firstWeekday,
        AppFormats.lastWeekday,
        'weekday',
      );
    }
    return labels[weekday];
  }

  /// Traduit le jour d'un `DateTime` (1 = lundi … 7 = dimanche) vers la convention
  /// du service (0 = dimanche … 6 = samedi).
  static int fromDateTime(DateTime value) => value.weekday % 7;
}

/// Affichage des dates et de l'âge des données.
abstract final class DateLabels {
  static final DateFormat _dayMonth = DateFormat('d MMMM', AppFormats.locale);
  static final DateFormat _dayMonthYear = DateFormat(
    'd MMMM y',
    AppFormats.locale,
  );
  static final DateFormat _hourMinute = DateFormat('HH:mm', AppFormats.locale);

  static String day(DateTime value) => _dayMonth.format(value);

  static String dayWithYear(DateTime value) => _dayMonthYear.format(value);

  static String time(DateTime value) => _hourMinute.format(value);

  static String dayAndTime(DateTime value) =>
      '${_dayMonth.format(value)} à ${_hourMinute.format(value)}';

  /// Âge d'une donnée en cache — « Mis à jour à l'instant / il y a 5 min / … ».
  ///
  /// Alimente la mention affichée à côté d'un contenu servi hors ligne (FR-096).
  static String age(Duration value) {
    if (value.inMinutes < 1) {
      return 'à l’instant';
    }
    if (value.inMinutes < 60) {
      return 'il y a ${value.inMinutes} min';
    }
    if (value.inHours < 24) {
      final int hours = value.inHours;
      return 'il y a $hours h';
    }
    final int days = value.inDays;
    return days == 1 ? 'hier' : 'il y a $days jours';
  }
}
