// « Mes prestations » — la vie de l'offre après approbation (T210, FR-067).
//
// Le vocabulaire est celui du contrat : il n'existe **aucune suppression** —
// un service se « Désactive », jamais ne s'efface (`active: false`), et tout
// reste visible dans cette vue de gestion, y compris ce qui est désactivé.
//
// Désactiver la **dernière** prestation encore réservable fait disparaître
// l'offre des résultats de recherche à l'instant même : l'écran le dit avant
// d'envoyer, plutôt que de laisser le prestataire le découvrir par le silence
// de son téléphone (scénario 8.2).
//
// Toute écriture invalide l'aperçu du dossier (FR-050) : la checklist en
// dépend.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_overview_controller.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_self_access.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_offer.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/packs_screen.dart';

/// L'offre complète, partagée avec l'écran des formules : une seule vérité,
/// invalidée après chaque écriture.
final FutureProvider<List<ProviderService>> providerServicesProvider =
    FutureProvider.autoDispose<List<ProviderService>>(
      (Ref ref) => ref.watch(providerSelfRepositoryProvider).services(),
    );

/// Invalidation commune aux écritures de l'offre : la liste ET l'aperçu du
/// dossier (la checklist dépend des services — FR-050).
void invalidateOfferReads(WidgetRef ref) {
  ref
    ..invalidate(providerServicesProvider)
    ..invalidate(providerOverviewProvider);
}

/// Vrai si, [services] étant l'état courant, désactiver [target] retire la
/// dernière prestation encore réservable — donc l'offre entière de la
/// recherche.
bool deactivationClearsSearch(
  List<ProviderService> services,
  ProviderService target,
) => !services.any((ProviderService s) => s.id != target.id && s.hasActivePack);

class ProviderServicesScreen extends ConsumerWidget {
  const ProviderServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ProviderService>> services = ref.watch(
      providerServicesProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Mes prestations')),
      body: switch (services) {
        AsyncValue<List<ProviderService>>(:final List<ProviderService> value) =>
          value.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aucune prestation déclarée. Votre offre s’est '
                      'construite à l’onboarding ; contactez le support pour '
                      'ajouter un nouveau type de service.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(providerServicesProvider),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      for (final ProviderService service in value)
                        _ServiceCard(service: service, all: value),
                    ],
                  ),
                ),
        AsyncValue<List<ProviderService>>(:final Object error?) =>
          error is ApiException
              ? ErrorView.fromException(
                  error,
                  onRetry: () => ref.invalidate(providerServicesProvider),
                )
              : ErrorView(
                  message: 'Impossible de charger vos prestations. Réessayez.',
                  onRetry: () => ref.invalidate(providerServicesProvider),
                ),
        _ => const LoadingView(label: 'Chargement de vos prestations…'),
      },
    );
  }
}

class _ServiceCard extends ConsumerStatefulWidget {
  const _ServiceCard({required this.service, required this.all});

  final ProviderService service;
  final List<ProviderService> all;

  @override
  ConsumerState<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends ConsumerState<_ServiceCard> {
  bool _busy = false;

  Future<void> _toggleActive() async {
    final ProviderService service = widget.service;
    final bool deactivating = service.active;

    if (deactivating && deactivationClearsSearch(widget.all, service)) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Désactiver votre dernière prestation ?'),
          content: const Text(
            'C’est votre dernière prestation réservable : une fois '
            'désactivée, votre offre disparaît des résultats de recherche '
            'et les clients ne peuvent plus vous réserver. Vous pourrez la '
            'réactiver à tout moment.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Désactiver'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(providerSelfRepositoryProvider)
          .updateService(service.id, active: !service.active);
      if (!mounted) {
        return;
      }
      invalidateOfferReads(ref);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deactivating ? 'Prestation désactivée' : 'Prestation réactivée',
          ),
        ),
      );
    } on ApiException catch (failure) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ProviderService service = widget.service;
    final int activePacks = service.packs
        .where((ServicePack pack) => pack.active)
        .length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(service.title, style: theme.textTheme.titleSmall),
                      if (service.serviceType case final OfferServiceType t)
                        Text(
                          t.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (!service.active)
                  Chip(
                    label: const Text('Désactivée'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              service.packs.isEmpty
                  ? 'Aucune formule'
                  : '$activePacks formule(s) active(s) sur '
                        '${service.packs.length}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (BuildContext context) =>
                                PackManagementScreen(serviceId: service.id),
                          ),
                        ),
                  child: const Text('Formules et options'),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : _toggleActive,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(service.active ? 'Désactiver' : 'Réactiver'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
