// Étape 3 — lieu d'intervention (T113, FR-020).
//
// L'adresse par défaut est **présélectionnée** : dans le cas courant — un client qui
// réserve chez lui — le geste attendu est déjà fait.
//
// Carnet vide : on ne montre pas une liste vide avec un bouton, on renvoie vers la
// création. Une adresse est indispensable pour réserver, et c'est ce que dit l'écran.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/booking/presentation/booking_draft_controller.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';
import 'package:prestgo_mobile/features/profile/presentation/addresses_controller.dart';
import 'package:prestgo_mobile/features/search/domain/catalog.dart';

class AddressStep extends ConsumerStatefulWidget {
  const AddressStep({required this.coveredZones, super.key});

  /// Zones couvertes par le prestataire, rappelées après un refus « hors zone ».
  ///
  /// Elles viennent de la fiche publique, déjà en mémoire : les afficher ne coûte
  /// aucun appel et évite à l'utilisateur de deviner (scénario 2.8).
  final List<Zone> coveredZones;

  @override
  ConsumerState<AddressStep> createState() => _AddressStepState();
}

class _AddressStepState extends ConsumerState<AddressStep> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preselectDefault());
  }

  /// Présélectionne l'adresse par défaut, une seule fois.
  ///
  /// Ne remplace jamais un choix explicite : revenir sur cette étape après avoir
  /// choisi une autre adresse ne doit pas l'écraser.
  void _preselectDefault() {
    if (!mounted) {
      return;
    }
    final BookingState? booking = ref.read(bookingDraftProvider);
    if (booking == null || booking.draft.address != null) {
      return;
    }
    final Address? preferred = ref
        .read(addressesProvider.notifier)
        .defaultAddress;
    if (preferred != null) {
      ref.read(bookingDraftProvider.notifier).selectAddress(preferred);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Address>> addresses = ref.watch(addressesProvider);
    final BookingState? booking = ref.watch(bookingDraftProvider);
    final ThemeData theme = Theme.of(context);

    ref.listen<AsyncValue<List<Address>>>(addressesProvider, (
      AsyncValue<List<Address>>? previous,
      AsyncValue<List<Address>> next,
    ) {
      if (next.hasValue) {
        _preselectDefault();
      }
    });

    return addresses.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (Object error, StackTrace _) => Text(
        error is ApiException ? error.message : ApiFallbackMessages.unknown,
        style: TextStyle(color: theme.colorScheme.error),
      ),
      data: (List<Address> list) {
        if (list.isEmpty) {
          return _EmptyBook(
            onAdd: () async {
              await context.push(Routes.addressNew);
              if (context.mounted) {
                await ref.read(addressesProvider.notifier).reload();
              }
            },
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final Address address in list)
              _AddressChoice(
                address: address,
                selected: booking?.draft.address?.id == address.id,
                onSelected: () => ref
                    .read(bookingDraftProvider.notifier)
                    .selectAddress(address),
              ),
            if (widget.coveredZones.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              _CoveredZones(zones: widget.coveredZones),
            ],
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () async {
                await context.push(Routes.addressNew);
                if (context.mounted) {
                  await ref.read(addressesProvider.notifier).reload();
                }
              },
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Ajouter une adresse'),
            ),
          ],
        );
      },
    );
  }
}

class _AddressChoice extends StatelessWidget {
  const _AddressChoice({
    required this.address,
    required this.selected,
    required this.onSelected,
  });

  final Address address;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
      color: selected ? Theme.of(context).colorScheme.primary : null,
    ),
    title: Row(
      children: <Widget>[
        Flexible(child: Text(address.label)),
        if (address.isDefault) ...<Widget>[
          const SizedBox(width: 8),
          Text('par défaut', style: Theme.of(context).textTheme.labelSmall),
        ],
      ],
    ),
    subtitle: Text(address.fullLine),
    onTap: onSelected,
  );
}

class _EmptyBook extends StatelessWidget {
  const _EmptyBook({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Vous n’avez pas encore d’adresse enregistrée.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Une adresse géolocalisée est nécessaire : elle permet de vérifier '
          'que le prestataire se déplace jusque chez vous.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_location_alt_outlined),
          label: const Text('Ajouter une adresse'),
        ),
      ],
    );
  }
}

/// Zones couvertes par le prestataire, rappelées après un refus « hors zone ».
class _CoveredZones extends StatelessWidget {
  const _CoveredZones({required this.zones});

  final List<Zone> zones;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Ce prestataire intervient dans :',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final Zone zone in zones)
                Chip(
                  label: Text(zone.label),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
