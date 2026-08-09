// P6 — Grille d'agenda hebdomadaire (T155, FR-055).
//
// Sept jours, **dimanche en premier** — c'est la convention du service
// (weekday 0 = dimanche), et l'afficher autrement inviterait des décalages d'un
// jour à l'écriture.
//
// Les heures sont des chaînes `HH:MM` de bout en bout : le sélecteur natif rend
// une `TimeOfDay` (sans fuseau), formatée immédiatement en chaîne — jamais de
// `DateTime`, donc jamais de conversion de fuseau (scénario clé du contrat).
//
// Les contrôles locaux (`validateWeeklySlots` : ordre, chevauchement, plafond
// de 50) tournent **avant** l'envoi : les messages serveur correspondants ne
// sont pas contractualisés (scénario 4.5). L'écriture est un PUT : l'état
// complet de la grille part à chaque enregistrement.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_space/domain/weekly_slot.dart';

final FutureProvider<List<WeeklySlot>> _availabilitiesProvider =
    FutureProvider.autoDispose<List<WeeklySlot>>(
      (Ref ref) => ref.watch(providerSelfRepositoryProvider).availabilities(),
    );

class AvailabilitiesStepScreen extends ConsumerWidget {
  const AvailabilitiesStepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<WeeklySlot>> data = ref.watch(
      _availabilitiesProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Disponibilités hebdomadaires')),
      body: switch (data) {
        AsyncValue<List<WeeklySlot>>(:final List<WeeklySlot> value) =>
          _AvailabilitiesBody(initial: value),
        AsyncValue<List<WeeklySlot>>(:final Object error?) => ErrorView(
          message: error is ApiException
              ? error.message
              : 'Impossible de charger l’agenda. Réessayez.',
          onRetry: () => ref.invalidate(_availabilitiesProvider),
        ),
        _ => const LoadingView(label: 'Chargement de l’agenda…'),
      },
    );
  }
}

class _AvailabilitiesBody extends ConsumerStatefulWidget {
  const _AvailabilitiesBody({required this.initial});

  final List<WeeklySlot> initial;

  @override
  ConsumerState<_AvailabilitiesBody> createState() =>
      _AvailabilitiesBodyState();
}

class _AvailabilitiesBodyState extends ConsumerState<_AvailabilitiesBody>
    with FormSubmissionMixin<_AvailabilitiesBody> {
  late List<WeeklySlot> _slots = List<WeeklySlot>.of(widget.initial);

  /// `TimeOfDay` → « HH:MM ». Formaté à la main : `TimeOfDay.format` dépend de
  /// la locale (« 8:00 AM ») alors que le service exige la forme 24 h stricte.
  static String _asWireTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  Future<void> _addSlot(int weekday) async {
    final TimeOfDay? start = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Heure de début',
    );
    if (start == null || !mounted) {
      return;
    }
    final TimeOfDay? end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (start.hour + 4) % 24, minute: start.minute),
      helpText: 'Heure de fin',
    );
    if (end == null || !mounted) {
      return;
    }

    final WeeklySlot candidate = WeeklySlot(
      weekday: weekday,
      startTime: _asWireTime(start),
      endTime: _asWireTime(end),
    );
    // Le refus se prononce AVANT toute écriture — même locale (4.5).
    final String? error = validateWeeklySlots(<WeeklySlot>[
      ..._slots,
      candidate,
    ]);
    if (error != null) {
      showFormError(error);
      return;
    }
    setState(() {
      showFormError(null);
      _slots = <WeeklySlot>[..._slots, candidate];
    });
  }

  void _removeSlot(WeeklySlot slot) => setState(() {
    showFormError(null);
    _slots = _slots.where((WeeklySlot s) => s != slot).toList();
  });

  Future<void> _save() async {
    final String? localError = validateWeeklySlots(_slots);
    if (localError != null) {
      showFormError(localError);
      return;
    }

    final AvailabilitiesUpdate? update = await submit<AvailabilitiesUpdate>(
      () => ref
          .read(providerSelfRepositoryProvider)
          .replaceAvailabilities(_slots),
    );
    if (update == null || !mounted) {
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(update.message)));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(
                'Ajoutez vos créneaux jour par jour. Les heures s’entendent '
                'sur place, telles quelles.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              // Dimanche (0) en premier — l'ordre du service, pas celui du
              // calendrier local.
              for (int weekday = 0; weekday < weekdayLabels.length; weekday++)
                _DayCard(
                  weekday: weekday,
                  slots: _slots
                      .where((WeeklySlot s) => s.weekday == weekday)
                      .toList(growable: false),
                  enabled: !isSubmitting,
                  onAdd: () => _addSlot(weekday),
                  onRemove: _removeSlot,
                ),
            ],
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (formError case final String message) ...<Widget>[
                  Text(
                    message,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  onPressed: isSubmitting ? null : _save,
                  child: isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enregistrer mon agenda'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.weekday,
    required this.slots,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final int weekday;
  final List<WeeklySlot> slots;
  final bool enabled;
  final VoidCallback onAdd;
  final void Function(WeeklySlot) onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    weekdayLabel(weekday),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  onPressed: enabled ? onAdd : null,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Ajouter un créneau le ${weekdayLabel(weekday)}',
                ),
              ],
            ),
            if (slots.isEmpty)
              Text(
                'Aucun créneau',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final WeeklySlot slot in slots)
                    InputChip(
                      label: Text('${slot.startTime} – ${slot.endTime}'),
                      onDeleted: enabled ? () => onRemove(slot) : null,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
