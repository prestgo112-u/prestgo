// Étape 5 — récapitulatif et confirmation (T115, FR-033 à FR-035).
//
// C'est ici que la **clé d'idempotence est émise**, une fois, à l'affichage de
// l'écran — jamais dans `build`, qui s'exécute à chaque reconstruction. `initState`
// et un `didUpdateWidget` implicite via `ref.listen` suffiraient à en produire dix.
// D'où l'appel unique dans `initState`, puis la relecture par le contrôleur.
//
// La séquence de confirmation est répartie ainsi :
//   • rejeu réseau (1 s puis 3 s, même clé) → socle, `RetryPolicy` ;
//   • boucle sur 409 « déjà en cours »      → `BookingRepository` ;
//   • interprétation du refus               → `BookingErrorMapper`, via le contrôleur.
// Cet écran n'en fait aucune partie lui-même : il affiche le résultat.
//
// Ce que cet écran ne fait **jamais** : présenter un 409 comme une erreur.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/format/money.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_draft.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_rules.dart';
import 'package:prestgo_mobile/features/booking/presentation/address_step.dart';
import 'package:prestgo_mobile/features/booking/presentation/booking_draft_controller.dart';
import 'package:prestgo_mobile/features/booking/presentation/booking_error_mapper.dart';
import 'package:prestgo_mobile/features/booking/presentation/instructions_step.dart';
import 'package:prestgo_mobile/features/search/domain/catalog.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';

class BookingSummaryScreen extends ConsumerStatefulWidget {
  const BookingSummaryScreen({super.key});

  @override
  ConsumerState<BookingSummaryScreen> createState() =>
      _BookingSummaryScreenState();
}

class _BookingSummaryScreenState extends ConsumerState<BookingSummaryScreen> {
  @override
  void initState() {
    super.initState();
    // ⚠️ La clé est émise ici, une seule fois. L'appeler depuis `build` en
    // produirait une neuve à chaque reconstruction et annulerait la protection
    // (piège n°5 de §6 de quickstart.md).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(bookingDraftProvider) != null) {
        ref.read(bookingDraftProvider.notifier).prepareSummary();
      }
    });
  }

  Future<void> _confirm() async {
    await ref.read(bookingDraftProvider.notifier).confirm();
    if (!mounted) {
      return;
    }
    final BookingState? booking = ref.read(bookingDraftProvider);
    if (booking == null) {
      return;
    }

    if (booking.isConfirmed) {
      _showConfirmation(booking);
      return;
    }
    if (booking.isStillProcessing) {
      _showStillProcessing();
    }
  }

  /// Succès — y compris « déjà enregistrée », qui en est un (FR-034).
  void _showConfirmation(BookingState booking) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, size: 40),
        title: Text(
          booking.wasAlreadyRecorded
              ? 'Réservation déjà enregistrée'
              : 'Demande envoyée',
        ),
        content: Text(
          booking.wasAlreadyRecorded
              // Le premier appel était passé : la coupure n'a fait perdre que la
              // réponse. Le dire évite de laisser croire à un doublon.
              ? 'Votre demande avait bien été reçue. Aucune seconde réservation '
                    'n’a été créée.'
              : 'Le prestataire doit maintenant accepter votre demande. Vous '
                    'serez prévenu de sa réponse.',
        ),
        actions: <Widget>[
          FilledButton(
            onPressed: () {
              final String? missionId = booking.mission?.id;
              ref.read(bookingDraftProvider.notifier).clear();
              Navigator.of(context).pop();
              context.go(
                missionId == null
                    ? Routes.missions
                    : Routes.missionDetailFor(missionId),
              );
            },
            child: const Text('Voir ma réservation'),
          ),
        ],
      ),
    );
  }

  /// 409 persistant : ni succès ni erreur — la réservation est probablement passée.
  void _showStillProcessing() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Traitement en cours'),
        content: const Text(
          'Votre demande est en cours d’enregistrement. Consultez vos missions '
          'dans un instant : elle devrait y figurer.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Rester ici'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go(Routes.missions);
            },
            child: const Text('Voir mes missions'),
          ),
        ],
      ),
    );
  }

  /// Ramène à l'étape fautive, brouillon conservé (FR-035).
  void _goToStep(BookingStep step) {
    ref.read(bookingDraftProvider.notifier).dismissCorrection();
    switch (step) {
      case BookingStep.pack:
        context.go(
          Routes.bookingFor(ref.read(bookingDraftProvider)!.draft.provider.id),
        );
      case BookingStep.schedule:
        context.pop();
      case BookingStep.address:
      case BookingStep.instructions:
      case BookingStep.summary:
        // Ces deux étapes vivent sur cet écran : rien à faire, le refus est déjà
        // affiché au-dessus d'elles.
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final BookingState? booking = ref.watch(bookingDraftProvider);
    if (booking == null) {
      return const Scaffold(body: LoadingView());
    }

    final BookingDraft draft = booking.draft;
    final ThemeData theme = Theme.of(context);
    final BookingCorrection? correction = booking.correction;

    return Scaffold(
      appBar: AppBar(title: const Text('Récapitulatif')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          if (correction != null) ...<Widget>[
            _CorrectionBanner(
              correction: correction,
              onCorrect: correction.step == null
                  ? null
                  : () => _goToStep(correction.step!),
            ),
            const SizedBox(height: 16),
          ],

          _RecapCard(draft: draft),

          const SizedBox(height: 24),
          Text('Lieu d’intervention', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          AddressStep(
            // Après un refus « hors zone », on rappelle où le prestataire
            // intervient — l'information est déjà en mémoire.
            coveredZones: correction?.showsCoveredZones ?? false
                ? draft.provider.zones
                : const <Zone>[],
          ),

          const SizedBox(height: 24),
          InstructionsStep(
            initialValue: draft.instructions,
            onChanged: (String? value) =>
                ref.read(bookingDraftProvider.notifier).setInstructions(value),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text('Total', style: theme.textTheme.bodySmall),
                        Text(
                          Money.format(draft.totalPrice),
                          style: theme.textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed:
                        draft.isComplete &&
                            !booking.isConfirming &&
                            (correction?.isRecoverable ?? true)
                        ? _confirm
                        : null,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(180, 52),
                    ),
                    child: booking.isConfirming
                        // L'indicateur reste affiché pendant l'attente sur un 409 :
                        // la première requête est probablement en train d'aboutir.
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Text('Confirmer'),
                  ),
                ],
              ),
              if (!draft.isComplete)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Il manque : ${draft.nextStep.title.toLowerCase()}.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecapCard extends StatelessWidget {
  const _RecapCard({required this.draft});

  final BookingDraft draft;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ServicePack? pack = draft.pack;
    final DateTime? scheduledAt = draft.scheduledAt;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(draft.provider.publicName, style: theme.textTheme.titleMedium),
            const Divider(height: 24),
            if (pack != null) ...<Widget>[
              _Line(label: pack.title, value: Money.format(pack.price)),
              for (final PackOption option in draft.selectedOptions)
                _Line(
                  label: option.title,
                  value: '+ ${Money.format(option.price)}',
                  isSecondary: true,
                ),
              const Divider(height: 24),
              _Line(
                label: 'Durée totale',
                value: BookingRules.formatDuration(draft.totalDurationMinutes),
              ),
            ],
            if (scheduledAt != null)
              _Line(
                label: 'Date et heure',
                // L'agenda est en UTC : on l'affiche tel qu'il a été choisi, sans
                // conversion, pour que l'utilisateur relise ce qu'il a coché.
                value:
                    '${DateLabels.day(scheduledAt.toUtc())} à '
                    '${scheduledAt.toUtc().hour.toString().padLeft(2, '0')}:'
                    '${scheduledAt.toUtc().minute.toString().padLeft(2, '0')}',
              ),
            if (draft.address case final address?)
              _Line(label: 'Adresse', value: address.label),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.isSecondary = false,
  });

  final String label;
  final String value;
  final bool isSecondary;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TextStyle? style = isSecondary
        ? theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          )
        : theme.textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Refus métier : message du service, et retour vers l'étape fautive.
class _CorrectionBanner extends StatelessWidget {
  const _CorrectionBanner({required this.correction, this.onCorrect});

  final BookingCorrection correction;
  final VoidCallback? onCorrect;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.error_outline,
                  size: 20,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 10),
                Expanded(
                  // Message du service, tel quel : lui seul porte les nombres
                  // interpolés (FR-088).
                  child: Text(
                    correction.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            if (correction.hint case final String hint) ...<Widget>[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            if (onCorrect != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onCorrect,
                  child: Text('Corriger : ${correction.step!.title}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
