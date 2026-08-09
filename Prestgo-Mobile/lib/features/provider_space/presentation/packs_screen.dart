// Formules et options d'un service (T211, FR-067 ; scénarios 8.1 et 8.2).
//
// Deux vérités du contrat que cet écran matérialise :
//
//   • **les missions déjà réservées gardent leur montant** : un changement de
//     prix ne vaut que pour les prochaines réservations (`quotedAmount` est
//     figé à la création de mission). Le formulaire le dit, à l'endroit même
//     où le prix se modifie (8.1) ;
//   • **modifier une option passe par le chemin À PLAT**
//     (`PATCH /providers/me/service-pack-options/{id}`) — la création, elle,
//     reste imbriquée sous la formule. La seule paire asymétrique du contrat.
//
// Ici non plus, rien ne se supprime : formules et options se désactivent.
// Désactiver la dernière formule active de la dernière prestation réservable
// fait disparaître l'offre de la recherche — l'avertissement part avant (8.2).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_self_access.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_offer.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/services_screen.dart';

/// Mention affichée partout où un montant se modifie (8.1).
const String kReservedMissionsKeepAmount =
    'Les missions déjà réservées gardent leur montant : le nouveau prix ne '
    'vaut que pour les prochaines réservations.';

class PackManagementScreen extends ConsumerWidget {
  const PackManagementScreen({required this.serviceId, super.key});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ProviderService>> services = ref.watch(
      providerServicesProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Formules et options')),
      body: switch (services) {
        AsyncValue<List<ProviderService>>(:final List<ProviderService> value) =>
          switch (value
              .where((ProviderService s) => s.id == serviceId)
              .firstOrNull) {
            final ProviderService service => _PacksBody(
              service: service,
              all: value,
            ),
            // Le service a disparu de la liste rechargée : retour à la vue mère.
            null => ErrorView(
              message: 'Cette prestation n’existe plus dans votre offre.',
              onRetry: () => ref.invalidate(providerServicesProvider),
            ),
          },
        AsyncValue<List<ProviderService>>(:final Object error?) =>
          error is ApiException
              ? ErrorView.fromException(
                  error,
                  onRetry: () => ref.invalidate(providerServicesProvider),
                )
              : ErrorView(
                  message: 'Impossible de charger les formules. Réessayez.',
                  onRetry: () => ref.invalidate(providerServicesProvider),
                ),
        _ => const LoadingView(label: 'Chargement des formules…'),
      },
    );
  }
}

class _PacksBody extends ConsumerWidget {
  const _PacksBody({required this.service, required this.all});

  final ProviderService service;
  final List<ProviderService> all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(service.title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final ServicePack pack in service.packs)
          _PackCard(service: service, all: all, pack: pack),
        if (service.packs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Aucune formule sur cette prestation.'),
          ),
      ],
    );
  }
}

class _PackCard extends ConsumerStatefulWidget {
  const _PackCard({
    required this.service,
    required this.all,
    required this.pack,
  });

  final ProviderService service;
  final List<ProviderService> all;
  final ServicePack pack;

  @override
  ConsumerState<_PackCard> createState() => _PackCardState();
}

class _PackCardState extends ConsumerState<_PackCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        invalidateOfferReads(ref);
      }
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

  /// Vrai si désactiver cette formule éteint la dernière offre réservable.
  bool get _lastReachablePack {
    final ServicePack pack = widget.pack;
    final ProviderService service = widget.service;
    final bool otherActivePackHere =
        service.active &&
        service.packs.any((ServicePack p) => p.id != pack.id && p.active);
    final bool otherReachableService = widget.all.any(
      (ProviderService s) => s.id != service.id && s.hasActivePack,
    );
    return !otherActivePackHere && !otherReachableService;
  }

  Future<void> _togglePack() async {
    final ServicePack pack = widget.pack;

    if (pack.active && _lastReachablePack) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Désactiver votre dernière formule active ?'),
          content: const Text(
            'Sans formule active, votre offre disparaît des résultats de '
            'recherche et les clients ne peuvent plus vous réserver. Vous '
            'pourrez la réactiver à tout moment.',
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

    await _run(
      () async => ref
          .read(providerSelfRepositoryProvider)
          .updatePack(pack.id, active: !pack.active),
    );
  }

  Future<void> _editPack() async {
    final ServicePack pack = widget.pack;
    final _PackEdit? edit = await showDialog<_PackEdit>(
      context: context,
      builder: (BuildContext context) => _PackEditDialog(pack: pack),
    );
    if (edit == null || !mounted) {
      return;
    }
    await _run(
      () async => ref
          .read(providerSelfRepositoryProvider)
          .updatePack(
            pack.id,
            title: edit.title,
            price: edit.price,
            durationMinutes: edit.durationMinutes,
          ),
    );
  }

  Future<void> _addOption() async {
    final _OptionEdit? edit = await showDialog<_OptionEdit>(
      context: context,
      builder: (BuildContext context) => const _OptionEditDialog(),
    );
    if (edit == null || !mounted) {
      return;
    }
    // Création : chemin IMBRIQUÉ sous la formule (opération 75).
    await _run(
      () async => ref
          .read(providerSelfRepositoryProvider)
          .createOption(
            widget.pack.id,
            title: edit.title,
            price: edit.price,
            durationMinutes: edit.durationMinutes,
          ),
    );
  }

  Future<void> _editOption(PackOption option) async {
    final _OptionEdit? edit = await showDialog<_OptionEdit>(
      context: context,
      builder: (BuildContext context) => _OptionEditDialog(option: option),
    );
    if (edit == null || !mounted) {
      return;
    }
    // Modification : chemin À PLAT (opération 76) — jamais sous la formule.
    await _run(
      () async => ref
          .read(providerSelfRepositoryProvider)
          .updateOption(
            option.id,
            title: edit.title,
            price: edit.price,
            durationMinutes: edit.durationMinutes,
          ),
    );
  }

  Future<void> _toggleOption(PackOption option) => _run(
    () async => ref
        .read(providerSelfRepositoryProvider)
        .updateOption(option.id, active: !option.active),
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ServicePack pack = widget.pack;

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
                  child: Text(pack.title, style: theme.textTheme.titleSmall),
                ),
                if (!pack.active)
                  Chip(
                    label: const Text('Désactivée'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
              ],
            ),
            Text(
              '${pack.price} XOF · ${pack.durationMinutes} min',
              style: theme.textTheme.bodyMedium,
            ),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: _busy ? null : _editPack,
                  child: const Text('Modifier'),
                ),
                TextButton(
                  onPressed: _busy ? null : _togglePack,
                  child: Text(pack.active ? 'Désactiver' : 'Réactiver'),
                ),
                const Spacer(),
                if (_busy)
                  const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('Options', style: theme.textTheme.labelLarge),
                ),
                TextButton(
                  onPressed: _busy ? null : _addOption,
                  child: const Text('Ajouter une option'),
                ),
              ],
            ),
            if (pack.options.isEmpty)
              Text(
                'Aucune option.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              for (final PackOption option in pack.options)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        option.active
                            ? '${option.title} — ${option.price} XOF'
                            : '${option.title} — ${option.price} XOF '
                                  '(désactivée)',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Modifier l’option',
                      onPressed: _busy ? null : () => _editOption(option),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _toggleOption(option),
                      child: Text(
                        option.active ? 'Désactiver' : 'Réactiver',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}

class _PackEdit {
  const _PackEdit({
    required this.title,
    required this.price,
    required this.durationMinutes,
  });

  final String title;
  final num price;
  final int durationMinutes;
}

/// Formulaire de modification d'une formule — porte la mention du montant
/// figé, à l'endroit même où le prix change (8.1).
class _PackEditDialog extends StatefulWidget {
  const _PackEditDialog({required this.pack});

  final ServicePack pack;

  @override
  State<_PackEditDialog> createState() => _PackEditDialogState();
}

class _PackEditDialogState extends State<_PackEditDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.pack.title,
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.pack.price.toString(),
  );
  late final TextEditingController _duration = TextEditingController(
    text: widget.pack.durationMinutes.toString(),
  );
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _duration.dispose();
    super.dispose();
  }

  void _submit() {
    final String title = _title.text.trim();
    final num? price = num.tryParse(_price.text.trim());
    final int? duration = int.tryParse(_duration.text.trim());
    if (title.isEmpty || price == null || duration == null) {
      setState(
        () => _error = 'Renseignez un titre, un prix et une durée valides.',
      );
      return;
    }
    Navigator.of(
      context,
    ).pop(_PackEdit(title: title, price: price, durationMinutes: duration));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Modifier la formule'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Titre'),
          ),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Prix (XOF)'),
          ),
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Durée (minutes)'),
          ),
          const SizedBox(height: 12),
          Text(
            kReservedMissionsKeepAmount,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_error case final String message)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _OptionEdit {
  const _OptionEdit({
    required this.title,
    required this.price,
    this.durationMinutes,
  });

  final String title;
  final num price;
  final int? durationMinutes;
}

class _OptionEditDialog extends StatefulWidget {
  const _OptionEditDialog({this.option});

  /// `null` = création (chemin imbriqué) ; sinon modification (chemin à plat).
  final PackOption? option;

  @override
  State<_OptionEditDialog> createState() => _OptionEditDialogState();
}

class _OptionEditDialogState extends State<_OptionEditDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.option?.title,
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.option?.price.toString(),
  );
  late final TextEditingController _duration = TextEditingController(
    text: widget.option?.durationMinutes.toString() ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _duration.dispose();
    super.dispose();
  }

  void _submit() {
    final String title = _title.text.trim();
    final num? price = num.tryParse(_price.text.trim());
    if (title.isEmpty || price == null) {
      setState(() => _error = 'Renseignez un titre et un prix valides.');
      return;
    }
    Navigator.of(context).pop(
      _OptionEdit(
        title: title,
        price: price,
        durationMinutes: int.tryParse(_duration.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AlertDialog(
      title: Text(
        widget.option == null ? 'Ajouter une option' : 'Modifier l’option',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Titre'),
          ),
          TextField(
            controller: _price,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Prix (XOF)'),
          ),
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Durée ajoutée (minutes, facultatif)',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            kReservedMissionsKeepAmount,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (_error case final String message)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                message,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Enregistrer')),
      ],
    );
  }
}
