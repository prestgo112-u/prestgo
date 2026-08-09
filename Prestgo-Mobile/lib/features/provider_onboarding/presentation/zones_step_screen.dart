// P5 — Zones d'intervention (T154, FR-054).
//
// L'écran est une liste à cocher qui envoie **l'état complet** : la route est un
// PUT, le tableau envoyé remplace la liste — cocher une case de plus renvoie
// tout. Le pré-cochage vient de `GET /providers/me/zones`, le catalogue de
// `GET /zones`.
//
// Deux garde-fous :
//   • le plafond de 15 est appliqué à la coche — cocher au-delà est refusé avec
//     l'explication, plutôt que d'attendre le 400 du service ;
//   • vider une liste **non vide** exige une confirmation explicite : la liste
//     vide est acceptée par le service et fait disparaître le prestataire de la
//     recherche (scénario 4.4).
//
// Le 400 « Zone inconnue ou inactive » est atomique — rien n'a été écrit : le
// catalogue est rechargé et l'écran réaffiché tel quel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/shared/catalog/catalog.dart';

/// Catalogue et zones déjà couvertes, chargés ensemble.
typedef _ZonesData = ({List<Zone> available, List<Zone> mine});

final FutureProvider<_ZonesData> _zonesDataProvider =
    FutureProvider.autoDispose<_ZonesData>((Ref ref) async {
      final ProviderSelfRepository repository = ref.watch(
        providerSelfRepositoryProvider,
      );
      final List<Zone> available = await repository.availableZones();
      final List<Zone> mine = await repository.myZones();
      return (available: available, mine: mine);
    });

class ZonesStepScreen extends ConsumerWidget {
  const ZonesStepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<_ZonesData> data = ref.watch(_zonesDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Zones d’intervention')),
      body: switch (data) {
        AsyncValue<_ZonesData>(:final _ZonesData value) => _ZonesBody(
          available: value.available,
          initial: value.mine,
        ),
        AsyncValue<_ZonesData>(:final Object error?) => ErrorView(
          message: error is ApiException
              ? error.message
              : 'Impossible de charger les zones. Réessayez.',
          onRetry: () => ref.invalidate(_zonesDataProvider),
        ),
        _ => const LoadingView(label: 'Chargement des zones…'),
      },
    );
  }
}

class _ZonesBody extends ConsumerStatefulWidget {
  const _ZonesBody({required this.available, required this.initial});

  final List<Zone> available;
  final List<Zone> initial;

  @override
  ConsumerState<_ZonesBody> createState() => _ZonesBodyState();
}

class _ZonesBodyState extends ConsumerState<_ZonesBody>
    with FormSubmissionMixin<_ZonesBody> {
  late final Set<String> _selected = <String>{
    for (final Zone zone in widget.initial) zone.id,
  };

  void _toggle(String zoneId, bool checked) {
    if (checked && _selected.length >= ContentLimits.zonesPerProvider) {
      showFormError(
        'Vous ne pouvez pas couvrir plus de '
        '${ContentLimits.zonesPerProvider} zones.',
      );
      return;
    }
    setState(() {
      showFormError(null);
      if (checked) {
        _selected.add(zoneId);
      } else {
        _selected.remove(zoneId);
      }
    });
  }

  Future<void> _save() async {
    // Passer d'une couverture existante à AUCUNE zone mérite qu'on le dise :
    // le prestataire disparaît de la recherche à l'instant même (4.4).
    if (widget.initial.isNotEmpty && _selected.isEmpty) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Ne plus couvrir aucune zone ?'),
          content: const Text(
            'Sans zone d’intervention, votre fiche disparaît de la recherche '
            'et les clients ne peuvent plus vous réserver.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Tout retirer'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }

    final ZonesUpdate? update = await submit<ZonesUpdate>(
      () => ref
          .read(providerSelfRepositoryProvider)
          .replaceZones(_selected.toList(growable: false)),
    );
    if (!mounted) {
      return;
    }

    if (update != null) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(update.message)));
      return;
    }

    // « Zone inconnue ou inactive : … » — contrôle atomique, rien n'est écrit.
    // Le catalogue a changé : recharger et réafficher (le message reste en
    // bannière, posé par le mixin).
    if (lastFailure?.isUserFixable ?? false) {
      ref.invalidate(_zonesDataProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Cochez les zones où vous intervenez.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                '${_selected.length}/${ContentLimits.zonesPerProvider}',
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: <Widget>[
              for (final Zone zone in widget.available)
                CheckboxListTile(
                  value: _selected.contains(zone.id),
                  title: Text(zone.label),
                  onChanged: isSubmitting
                      ? null
                      : (bool? checked) => _toggle(zone.id, checked ?? false),
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
                      : const Text('Enregistrer mes zones'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
