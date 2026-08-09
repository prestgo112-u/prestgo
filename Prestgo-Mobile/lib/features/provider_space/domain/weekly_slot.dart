// Agenda hebdomadaire (data-model §4.4) et ses règles locales (T145).
//
// Les heures sont des **chaînes** `HH:MM`, jamais converties de fuseau : le
// service les interprète en UTC, et convertir dans le fuseau de l'appareil
// décalerait l'agenda d'un utilisateur en déplacement (piège n°4 de
// quickstart.md §6). Aucune `TimeOfDay`, aucune `DateTime` ici.
//
// Trois règles sont reproduites localement parce que leurs messages serveur ne
// sont pas contractualisés (Swagger muet, §2.2 P6) : fin après début, aucun
// chevauchement sur un même jour, plafond de 50 créneaux. Le service reste
// l'autorité — ces contrôles épargnent un aller-retour, ils ne décident rien.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

/// Créneau hebdomadaire — `weekday` 0 à 6, **0 = dimanche**.
class WeeklySlot {
  const WeeklySlot({
    required this.weekday,
    required this.startTime,
    required this.endTime,
  });

  factory WeeklySlot.fromJson(JsonMap json) => WeeklySlot(
    weekday: switch (json['weekday']) {
      final num v => v.toInt(),
      _ => -1,
    },
    startTime: json['startTime'] as String? ?? '',
    endTime: json['endTime'] as String? ?? '',
  );

  final int weekday;

  /// `HH:MM` sur 24 h, envoyée et affichée **telle quelle**.
  final String startTime;
  final String endTime;

  /// Corps attendu par `PUT /providers/me/availabilities` — trois champs, rien
  /// d'autre : `id` et `active` appartiennent au service.
  JsonMap toJson() => <String, Object?>{
    'weekday': weekday,
    'startTime': startTime,
    'endTime': endTime,
  };

  bool get hasValidWeekday =>
      weekday >= AppFormats.firstWeekday && weekday <= AppFormats.lastWeekday;

  bool get hasValidTimes =>
      AppFormats.timeOfDayPattern.hasMatch(startTime) &&
      AppFormats.timeOfDayPattern.hasMatch(endTime);

  /// Minutes depuis minuit — uniquement pour comparer deux chaînes valides.
  int get startMinutes => _minutes(startTime);
  int get endMinutes => _minutes(endTime);

  bool get isOrdered => hasValidTimes && endMinutes > startMinutes;

  /// Deux créneaux du même jour se chevauchent s'ils partagent une minute.
  /// Se toucher (08:00–12:00 puis 12:00–14:00) n'est pas se chevaucher.
  bool overlaps(WeeklySlot other) =>
      weekday == other.weekday &&
      startMinutes < other.endMinutes &&
      other.startMinutes < endMinutes;

  static int _minutes(String time) {
    final List<String> parts = time.split(':');
    if (parts.length != 2) {
      return 0;
    }
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  @override
  bool operator ==(Object other) =>
      other is WeeklySlot &&
      other.weekday == weekday &&
      other.startTime == startTime &&
      other.endTime == endTime;

  @override
  int get hashCode => Object.hash(weekday, startTime, endTime);

  @override
  String toString() => 'WeeklySlot(j$weekday $startTime–$endTime)';
}

/// Jours dans l'ordre d'affichage du service : **dimanche en premier** (FR-055).
const List<String> weekdayLabels = <String>[
  'Dimanche',
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
];

String weekdayLabel(int weekday) =>
    weekday >= 0 && weekday < weekdayLabels.length
    ? weekdayLabels[weekday]
    : 'Jour $weekday';

/// Contrôle local d'un agenda complet — `null` si tout est bon.
///
/// Reproduit les refus **prévisibles** du service, dans l'ordre où ils se
/// corrigent le plus naturellement : format, jour, ordre des heures, plafond,
/// chevauchement. Un seul message à la fois : l'utilisateur corrige, revalide.
String? validateWeeklySlots(List<WeeklySlot> slots) {
  for (final WeeklySlot slot in slots) {
    if (!slot.hasValidWeekday) {
      return 'Le jour va de 0 (dimanche) à 6 (samedi).';
    }
    if (!slot.hasValidTimes) {
      return 'Les heures doivent être au format HH:MM.';
    }
    if (!slot.isOrdered) {
      return 'L’heure de fin doit être après l’heure de début '
          '(${weekdayLabel(slot.weekday)} ${slot.startTime}–${slot.endTime}).';
    }
  }

  if (slots.length > ContentLimits.weeklySlots) {
    return 'Un agenda hebdomadaire ne peut pas dépasser '
        '${ContentLimits.weeklySlots} créneaux.';
  }

  for (int i = 0; i < slots.length; i++) {
    for (int j = i + 1; j < slots.length; j++) {
      if (slots[i].overlaps(slots[j])) {
        return 'Deux créneaux se chevauchent le '
            '${weekdayLabel(slots[i].weekday).toLowerCase()} '
            '(${slots[i].startTime}–${slots[i].endTime} et '
            '${slots[j].startTime}–${slots[j].endTime}).';
      }
    }
  }

  return null;
}
