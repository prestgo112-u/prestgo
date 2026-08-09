// Carnet d'adresses (T106, T108, T109 — FR-019, FR-020).
//
// Trois comportements que l'écran doit tenir :
//
//   • **l'adresse par défaut est en tête** — c'est l'ordre du service, jamais
//     recalculé ici ;
//   • **l'ajout se ferme au plafond**, avec son motif affiché. Laisser le bouton
//     actif pour recevoir « Vous ne pouvez pas enregistrer plus de 10 adresses »
//     serait une promesse non tenue (FR-020) ;
//   • **la suppression a deux issues**, toutes deux des succès. Le message diffère,
//     l'écran ne présente jamais l'archivage comme un échec.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/widgets/empty_view.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';
import 'package:prestgo_mobile/features/profile/presentation/addresses_controller.dart';

class AddressesScreen extends ConsumerWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Address>> addresses = ref.watch(addressesProvider);
    final bool isAtCapacity = ref
        .watch(addressesProvider.notifier)
        .isAtCapacity;

    return Scaffold(
      appBar: AppBar(title: const Text('Mes adresses')),
      floatingActionButton: addresses.hasValue && !isAtCapacity
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.addressNew),
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Ajouter'),
            )
          : null,
      body: addresses.when(
        loading: () => const LoadingView(label: 'Chargement de vos adresses…'),
        error: (Object error, StackTrace _) => ErrorView(
          message: error is ApiException
              ? error.message
              : ApiFallbackMessages.unknown,
          onRetry: () => ref.read(addressesProvider.notifier).reload(),
        ),
        data: (List<Address> list) => list.isEmpty
            ? EmptyView(
                icon: Icons.place_outlined,
                title: 'Aucune adresse enregistrée',
                description:
                    'Une adresse géolocalisée est nécessaire pour réserver : '
                    'elle permet de vérifier que le prestataire se déplace '
                    'jusque chez vous.',
                actions: <EmptyAction>[
                  EmptyAction(
                    label: 'Ajouter une adresse',
                    onPressed: () => context.push(Routes.addressNew),
                  ),
                ],
              )
            : RefreshIndicator(
                onRefresh: () => ref.read(addressesProvider.notifier).reload(),
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: <Widget>[
                    if (isAtCapacity) const _CapacityNotice(),
                    for (final Address address in list)
                      _AddressTile(address: address),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Motif affiché quand l'ajout est fermé.
class _CapacityNotice extends StatelessWidget {
  const _CapacityNotice();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 20,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Vous avez atteint le maximum de '
              '${ContentLimits.addressesPerAccount} adresses. Supprimez-en une '
              'pour en ajouter une nouvelle.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddressTile extends ConsumerWidget {
  const _AddressTile({required this.address});

  final Address address;

  Future<void> _setDefault(BuildContext context, WidgetRef ref) async {
    try {
      // La réponse est la liste à jour : l'état s'alimente sans second appel.
      await ref.read(addressesProvider.notifier).setDefault(address.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('« ${address.label} » est votre adresse par défaut.'),
          ),
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: Text('Supprimer « ${address.label} » ?'),
            content: const Text(
              'Si cette adresse a servi à une mission, elle sera conservée dans '
              'votre historique mais retirée de votre carnet.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      return;
    }

    try {
      final AddressRemoval result = await ref
          .read(addressesProvider.notifier)
          .remove(address.id);
      if (context.mounted) {
        // Les deux issues sont des succès : seul le message change.
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return ListTile(
      leading: Icon(
        address.isDefault ? Icons.home : Icons.place_outlined,
        color: address.isDefault ? theme.colorScheme.primary : null,
      ),
      title: Row(
        children: <Widget>[
          Flexible(child: Text(address.label)),
          if (address.isDefault) ...<Widget>[
            const SizedBox(width: 8),
            Chip(
              label: const Text('Par défaut'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              labelStyle: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
      subtitle: Text(address.fullLine),
      trailing: PopupMenuButton<String>(
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(value: 'edit', child: Text('Modifier')),
          if (!address.isDefault)
            const PopupMenuItem<String>(
              value: 'default',
              child: Text('Définir par défaut'),
            ),
          const PopupMenuItem<String>(
            value: 'remove',
            child: Text('Supprimer'),
          ),
        ],
        onSelected: (String action) => switch (action) {
          'edit' => context.push(Routes.addressDetailFor(address.id)),
          'default' => _setDefault(context, ref),
          'remove' => _remove(context, ref),
          _ => null,
        },
      ),
    );
  }
}
