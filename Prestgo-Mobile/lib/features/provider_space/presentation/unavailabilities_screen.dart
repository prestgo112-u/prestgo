// Absences exceptionnelles (T214, FR-056).
//
// La relecture passe par la route publique `GET /providers/{id}/…`
// (opération 29) — il n'existe pas de `GET /providers/me/unavailabilities` :
// l'identifiant vient de l'aperçu du dossier, déjà chargé partout dans
// l'espace prestataire.
//
// Les deux contrôles locaux reproduisent les 400 du service AVANT l'envoi :
// fin après début (`isOrdered`) et non-chevauchement avec une absence
// existante (`overlaps`). Le service reste l'autorité — son message s'affiche
// tel quel si un cas passe entre les mailles.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_overview_controller.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_self_access.dart';
import 'package:prestgo_mobile/features/provider_space/domain/unavailability.dart';

/// Mes absences, relues par la route publique avec MON identifiant.
final FutureProvider<List<Unavailability>> myUnavailabilitiesProvider =
    FutureProvider.autoDispose<List<Unavailability>>((Ref ref) async {
      final ProviderProfile profile = await ref.watch(
        providerOverviewProvider.future,
      );
      return ref
          .watch(providerSelfRepositoryProvider)
          .unavailabilities(profile.id);
    });

class ProviderUnavailabilitiesScreen extends ConsumerWidget {
  const ProviderUnavailabilitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Unavailability>> absences = ref.watch(
      myUnavailabilitiesProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Absences exceptionnelles')),
      body: switch (absences) {
        AsyncValue<List<Unavailability>>(:final List<Unavailability> value) =>
          _UnavailabilitiesBody(absences: value),
        AsyncValue<List<Unavailability>>(:final Object error?) =>
          error is ApiException
              ? ErrorView.fromException(
                  error,
                  onRetry: () => ref.invalidate(myUnavailabilitiesProvider),
                )
              : ErrorView(
                  message: 'Impossible de charger vos absences. Réessayez.',
                  onRetry: () => ref.invalidate(myUnavailabilitiesProvider),
                ),
        _ => const LoadingView(label: 'Chargement de vos absences…'),
      },
    );
  }
}

class _UnavailabilitiesBody extends ConsumerStatefulWidget {
  const _UnavailabilitiesBody({required this.absences});

  final List<Unavailability> absences;

  @override
  ConsumerState<_UnavailabilitiesBody> createState() =>
      _UnavailabilitiesBodyState();
}

class _UnavailabilitiesBodyState extends ConsumerState<_UnavailabilitiesBody>
    with FormSubmissionMixin<_UnavailabilitiesBody> {
  Future<void> _add() async {
    final _NewAbsence? draft = await showDialog<_NewAbsence>(
      context: context,
      builder: (BuildContext context) => const _NewAbsenceDialog(),
    );
    if (draft == null || !mounted) {
      return;
    }

    // Contrôles locaux : les mêmes règles que les 400 du service (T208).
    final Unavailability candidate = Unavailability(
      id: '',
      startAt: draft.startAt,
      endAt: draft.endAt,
      reason: draft.reason,
    );
    if (!candidate.isOrdered) {
      showFormError('La date de fin doit être postérieure à la date de début.');
      return;
    }
    if (widget.absences.any(candidate.overlaps)) {
      showFormError('Cette absence chevauche une absence déjà enregistrée.');
      return;
    }

    final Unavailability? created = await submit<Unavailability>(
      () => ref
          .read(providerSelfRepositoryProvider)
          .createUnavailability(
            startAt: draft.startAt,
            endAt: draft.endAt,
            reason: draft.reason,
          ),
    );
    if (created == null || !mounted) {
      return;
    }
    ref.invalidate(myUnavailabilitiesProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Absence enregistrée')));
  }

  Future<void> _delete(Unavailability absence) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Supprimer cette absence ?'),
        content: Text(
          'Du ${DateLabels.dayAndTime(absence.startAt.toLocal())} au '
          '${DateLabels.dayAndTime(absence.endAt.toLocal())}. Vous '
          'redeviendrez réservable sur cette période.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final Object? done = await submit<Object?>(() async {
      await ref
          .read(providerSelfRepositoryProvider)
          .deleteUnavailability(absence.id);
      return true;
    });
    if (done == null || !mounted) {
      return;
    }
    ref.invalidate(myUnavailabilitiesProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Absence supprimée')));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Expanded(
          child: widget.absences.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aucune absence à venir. Déclarez vos congés et '
                      'indisponibilités : les clients ne pourront pas '
                      'réserver sur ces périodes.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    for (final Unavailability absence in widget.absences)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.event_busy_outlined),
                          title: Text(
                            'Du ${DateLabels.dayAndTime(absence.startAt.toLocal())}\n'
                            'au ${DateLabels.dayAndTime(absence.endAt.toLocal())}',
                          ),
                          subtitle: absence.reason == null
                              ? null
                              : Text(absence.reason!),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Supprimer l’absence',
                            onPressed: isSubmitting
                                ? null
                                : () => _delete(absence),
                          ),
                        ),
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
                FilledButton.icon(
                  onPressed: isSubmitting ? null : _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Déclarer une absence'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NewAbsence {
  const _NewAbsence({required this.startAt, required this.endAt, this.reason});

  final DateTime startAt;
  final DateTime endAt;
  final String? reason;
}

class _NewAbsenceDialog extends StatefulWidget {
  const _NewAbsenceDialog();

  @override
  State<_NewAbsenceDialog> createState() => _NewAbsenceDialogState();
}

class _NewAbsenceDialogState extends State<_NewAbsenceDialog> {
  DateTime? _start;
  DateTime? _end;
  final TextEditingController _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool start}) async {
    final DateTime now = DateTime.now();
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: (start ? _start : _end) ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: start ? 'Début de l’absence' : 'Fin de l’absence',
    );
    if (date == null || !mounted) {
      return;
    }
    setState(() {
      _error = null;
      if (start) {
        _start = date;
      } else {
        // La fin est EXCLUSIVE côté service : « au 17 » signifie « jusqu'au
        // 17 à minuit ». Le jour choisi est inclus dans l'absence.
        _end = date.add(const Duration(days: 1));
      }
    });
  }

  void _submit() {
    final DateTime? start = _start;
    final DateTime? end = _end;
    if (start == null || end == null) {
      setState(() => _error = 'Choisissez les deux dates.');
      return;
    }
    final String reason = _reason.text.trim();
    Navigator.of(context).pop(
      _NewAbsence(
        startAt: start,
        endAt: end,
        reason: reason.isEmpty ? null : reason,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Déclarer une absence'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OutlinedButton(
            onPressed: () => _pick(start: true),
            child: Text(
              _start == null
                  ? 'Premier jour d’absence'
                  : 'Du ${DateLabels.dayAndTime(_start!.toLocal())}',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _pick(start: false),
            child: Text(
              _end == null
                  ? 'Dernier jour d’absence'
                  : 'Au ${DateLabels.dayAndTime(_end!.toLocal())}',
            ),
          ),
          TextField(
            controller: _reason,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Motif (facultatif)'),
          ),
          if (_error case final String message)
            Text(message, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Déclarer')),
      ],
    );
  }
}
