// Interrupteur de disponibilité (T168, FR-066).
//
// Trois écrans l'affichent — le tableau de bord (en évidence, cahier §4.1), le
// profil de l'espace prestataire, et le suivi P9 pendant la vérification : en
// `pending_review`, c'est la seule action de gestion qui reste ouverte, le
// service laissant `availabilityStatus` traverser le verrou (scénario 4.8).
//
// L'explication sous les trois valeurs n'est pas décorative : « Occupé » laisse
// la fiche **réservable** (seule la pastille change), alors que « Indisponible »
// la retire de la recherche et refuse toute réservation — deux mots proches,
// deux effets opposés (scénario 5.6). Un libellé ambigu ferait choisir « Occupé »
// à quelqu'un qui voulait fermer son agenda, ou l'inverse.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_overview_controller.dart';

/// Interrupteur de disponibilité — actif quel que soit le statut du dossier.
class AvailabilityControl extends ConsumerStatefulWidget {
  const AvailabilityControl({required this.profile, super.key});

  final ProviderProfile profile;

  @override
  ConsumerState<AvailabilityControl> createState() =>
      _AvailabilityControlState();
}

class _AvailabilityControlState extends ConsumerState<AvailabilityControl> {
  bool _saving = false;

  Future<void> _change(AvailabilityStatus status) async {
    if (_saving || status == widget.profile.availabilityStatus) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(providerOverviewProvider.notifier).setAvailability(status);
    } on ApiException catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AvailabilityStatus current = widget.profile.availabilityStatus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SegmentedButton<AvailabilityStatus>(
          segments: <ButtonSegment<AvailabilityStatus>>[
            for (final AvailabilityStatus status in AvailabilityStatus.values)
              ButtonSegment<AvailabilityStatus>(
                value: status,
                label: Text(status.label),
              ),
          ],
          selected: <AvailabilityStatus>{current},
          onSelectionChanged: _saving
              ? null
              : (Set<AvailabilityStatus> selection) => _change(selection.first),
        ),
        const SizedBox(height: 8),
        Text(
          current.explanation,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
