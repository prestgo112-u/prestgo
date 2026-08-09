// Étape 2 — date et heure (T112, FR-031, FR-032).
//
// Cet écran ne propose **que** des créneaux que le service acceptera. Quatre
// conditions, appliquées par `BookingRules` :
//   1. le début tombe dans un créneau hebdomadaire du prestataire ;
//   2. la durée **totale** y tient entièrement (scénario 2.7) ;
//   3. aucune absence annoncée ne recouvre l'intervention ;
//   4. le délai minimum **en vigueur** est respecté — lu auprès du service au
//      démarrage, jamais écrit en dur (scénario 2.6, porte G3).
//
// Ce qui n'est pas vérifiable ici : les missions déjà engagées du prestataire.
// L'application ne connaît pas son agenda réel. Le service tranche, et le
// récapitulatif ramène à cette étape avec son message (FR-035).
//
// ⚠️ L'instant envoyé est composé en **UTC** : voir l'avertissement en tête de
// `booking_rules.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_rules.dart';
import 'package:prestgo_mobile/features/booking/presentation/booking_draft_controller.dart';
import 'package:prestgo_mobile/features/booking/presentation/widgets/booking_total_bar.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';

/// Nombre de jours proposés à partir d'aujourd'hui.
const int _horizonDays = 30;

class SchedulePickerScreen extends ConsumerStatefulWidget {
  const SchedulePickerScreen({super.key});

  @override
  ConsumerState<SchedulePickerScreen> createState() =>
      _SchedulePickerScreenState();
}

class _SchedulePickerScreenState extends ConsumerState<SchedulePickerScreen> {
  /// Jour affiché, en UTC — le référentiel de l'agenda.
  late DateTime _day = _todayUtc();

  static DateTime _todayUtc() {
    final DateTime now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final BookingState? booking = ref.watch(bookingDraftProvider);
    if (booking == null || booking.draft.pack == null) {
      return const Scaffold(body: LoadingView());
    }

    final BookingDraftController controller = ref.read(
      bookingDraftProvider.notifier,
    );
    final ThemeData theme = Theme.of(context);
    final DateTime now = DateTime.now().toUtc();
    final int minLead = controller.minLeadTimeMinutes;
    final int duration = booking.draft.totalDurationMinutes;

    final List<ClockTime> starts = BookingRules.availableStartTimes(
      provider: booking.draft.provider,
      day: _day,
      durationMinutes: duration,
      now: now,
      minLeadTimeMinutes: minLead,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Date et heure')),
      body: Column(
        children: <Widget>[
          _DayStrip(
            selected: _day,
            provider: booking.draft.provider,
            durationMinutes: duration,
            now: now,
            minLeadTimeMinutes: minLead,
            onSelected: (DateTime day) => setState(() => _day = day),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Durée de l’intervention : '
                    '${BookingRules.formatDuration(duration)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  'Au plus tôt dans ${BookingRules.formatDuration(minLead)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: starts.isEmpty
                ? _NoSlots(
                    provider: booking.draft.provider,
                    day: _day,
                    durationMinutes: duration,
                  )
                : GridView.count(
                    padding: const EdgeInsets.all(16),
                    crossAxisCount: 4,
                    childAspectRatio: 2.2,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: <Widget>[
                      for (final ClockTime start in starts)
                        _SlotChip(
                          time: start,
                          selected:
                              booking.draft.scheduledAt ==
                              BookingRules.instantFor(day: _day, time: start),
                          onSelected: () => controller.selectSchedule(
                            // Composé en UTC : c'est ce que compare le service.
                            BookingRules.instantFor(day: _day, time: start),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: BookingTotalBar(
        draft: booking.draft,
        label: 'Continuer',
        onContinue: booking.draft.scheduledAt == null
            ? null
            : () => context.push(Routes.bookingSummary),
      ),
    );
  }
}

/// Bande des jours, ceux sans disponibilité étant grisés.
class _DayStrip extends StatelessWidget {
  const _DayStrip({
    required this.selected,
    required this.provider,
    required this.durationMinutes,
    required this.now,
    required this.minLeadTimeMinutes,
    required this.onSelected,
  });

  final DateTime selected;
  final ProviderPublicProfile provider;
  final int durationMinutes;
  final DateTime now;
  final int minLeadTimeMinutes;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime today = DateTime.utc(now.year, now.month, now.day);

    return SizedBox(
      height: 84,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _horizonDays,
        itemBuilder: (BuildContext context, int index) {
          final DateTime day = today.add(Duration(days: index));
          // Griser plutôt que masquer : l'utilisateur voit que le jour existe et
          // qu'il n'y a rien, au lieu de chercher un jour disparu.
          final bool available = BookingRules.hasAvailability(
            provider: provider,
            day: day,
            durationMinutes: durationMinutes,
            now: now,
            minLeadTimeMinutes: minLeadTimeMinutes,
          );
          final bool isSelected = day == selected;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            child: InkWell(
              onTap: available ? () => onSelected(day) : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 60,
                decoration: BoxDecoration(
                  color: isSelected ? theme.colorScheme.primaryContainer : null,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      Weekdays.label(
                        Weekdays.fromDateTime(day),
                      ).substring(0, 3),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: available
                            ? null
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${day.day}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: available
                            ? null
                            : theme.colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.4,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.time,
    required this.selected,
    required this.onSelected,
  });

  final ClockTime time;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(time.value),
    selected: selected,
    onSelected: (_) => onSelected(),
  );
}

/// Explique **pourquoi** la journée est vide — la raison change la suite.
class _NoSlots extends StatelessWidget {
  const _NoSlots({
    required this.provider,
    required this.day,
    required this.durationMinutes,
  });

  final ProviderPublicProfile provider;
  final DateTime day;
  final int durationMinutes;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<WeeklySlot> slots = provider.slotsForWeekday(
      Weekdays.fromDateTime(day),
    );

    final String reason;
    if (slots.isEmpty) {
      reason = 'Le prestataire ne travaille pas ce jour-là.';
    } else if (provider.isAbsentDuring(day, durationMinutes)) {
      reason = 'Le prestataire est absent à cette date.';
    } else {
      reason =
          'Aucun créneau ne permet de tenir '
          '${BookingRules.formatDuration(durationMinutes)} ce jour-là.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.event_busy_outlined,
              size: 40,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Choisissez un autre jour.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
