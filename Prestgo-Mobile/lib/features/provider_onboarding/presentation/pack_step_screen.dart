// P4 et P4b — Formule tarifaire et ses options (T153, FR-053).
//
// C'est la création de la formule — pas celle du service — qui fait passer la
// case « prestations » de la checklist au vert : l'écran le dit en toutes
// lettres. Les options sont facultatives (P4b) et s'ajoutent une fois la formule
// créée, sur le chemin **imbriqué** du pack.
//
// Le prix est un nombre nu : la devise (XOF) est une décision d'application,
// affichée par le formateur unique — jamais envoyée au service.
//
// Un 404 « service introuvable » signifie que le `providerServiceId` ne
// correspond plus : la liste des services doit être relue — l'écran se ferme et
// l'appelant recharge.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/format/money.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_offer.dart';

class PackStepScreen extends ConsumerStatefulWidget {
  const PackStepScreen({
    required this.providerServiceId,
    required this.serviceTitle,
    super.key,
  });

  /// Le `data.id` retenu à la création du service (P3).
  final String providerServiceId;

  final String serviceTitle;

  @override
  ConsumerState<PackStepScreen> createState() => _PackStepScreenState();
}

class _PackStepScreenState extends ConsumerState<PackStepScreen>
    with FormSubmissionMixin<PackStepScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _duration = TextEditingController();

  /// Formule créée — l'écran bascule alors sur les options (P4b).
  ServicePack? _pack;
  List<PackOption> _options = const <PackOption>[];

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _duration.dispose();
    super.dispose();
  }

  String? _localCheck() {
    if (_title.text.trim().length < ContentLimits.packTitleMinLength) {
      return 'Le titre doit contenir au moins '
          '${ContentLimits.packTitleMinLength} caractères.';
    }
    final num? price = num.tryParse(_price.text.trim());
    if (price == null || price < 0) {
      return 'Le prix est un nombre positif ou nul.';
    }
    final int? duration = int.tryParse(_duration.text.trim());
    if (duration == null ||
        duration < ContentLimits.packDurationMinMinutes ||
        duration > ContentLimits.packDurationMaxMinutes) {
      return 'La durée va de ${ContentLimits.packDurationMinMinutes} à '
          '${ContentLimits.packDurationMaxMinutes} minutes.';
    }
    return null;
  }

  Future<void> _createPack() async {
    final String? localError = _localCheck();
    if (localError != null) {
      showFormError(localError);
      return;
    }

    final ServicePack? pack = await submit<ServicePack>(
      () => ref
          .read(providerSelfRepositoryProvider)
          .createPack(
            providerServiceId: widget.providerServiceId,
            title: _title.text.trim(),
            description: _description.text.trim(),
            price: num.parse(_price.text.trim()),
            durationMinutes: int.parse(_duration.text.trim()),
          ),
    );
    if (!mounted) {
      return;
    }

    if (pack != null) {
      setState(() => _pack = pack);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Formule créée')));
      return;
    }

    if (lastFailure?.isNotFound ?? false) {
      // Le service porteur a disparu : l'appelant relira la liste.
      final String message = lastFailure!.message;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _addOption() async {
    final ServicePack? pack = _pack;
    if (pack == null) {
      return;
    }
    final PackOption? option = await showModalBottomSheet<PackOption>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => _OptionSheet(packId: pack.id),
    );
    if (option != null && mounted) {
      setState(() => _options = <PackOption>[..._options, option]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ServicePack? pack = _pack;

    return Scaffold(
      appBar: AppBar(title: Text(widget.serviceTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: pack == null
            ? _buildPackForm(theme)
            : _buildOptions(theme, pack),
      ),
    );
  }

  Widget _buildPackForm(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text('Votre formule tarifaire', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        'C’est elle qui rend ce service réservable — sans formule active, il '
        'ne compte pas pour votre dossier.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _title,
        maxLength: ContentLimits.packTitleMaxLength,
        enabled: !isSubmitting,
        decoration: InputDecoration(
          labelText: 'Titre de la formule',
          hintText: 'Ex. : Intervention express',
          border: const OutlineInputBorder(),
          errorText: fieldErrors['title'],
        ),
        onChanged: (String _) => clearFieldError('title'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _description,
        maxLength: ContentLimits.packDescriptionMaxLength,
        maxLines: 3,
        enabled: !isSubmitting,
        decoration: InputDecoration(
          labelText: 'Description (facultative)',
          border: const OutlineInputBorder(),
          errorText: fieldErrors['description'],
        ),
        onChanged: (String _) => clearFieldError('description'),
      ),
      const SizedBox(height: 12),
      Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _price,
              keyboardType: TextInputType.number,
              enabled: !isSubmitting,
              decoration: InputDecoration(
                labelText: 'Prix (${AppFormats.currencyCode})',
                border: const OutlineInputBorder(),
                errorText: fieldErrors['price'],
              ),
              onChanged: (String _) => clearFieldError('price'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _duration,
              keyboardType: TextInputType.number,
              enabled: !isSubmitting,
              decoration: InputDecoration(
                labelText: 'Durée (minutes)',
                border: const OutlineInputBorder(),
                errorText: fieldErrors['durationMinutes'],
              ),
              onChanged: (String _) => clearFieldError('durationMinutes'),
            ),
          ),
        ],
      ),
      if (formError case final String message) ...<Widget>[
        const SizedBox(height: 8),
        Text(message, style: TextStyle(color: theme.colorScheme.error)),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: isSubmitting ? null : _createPack,
        child: isSubmitting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Créer la formule'),
      ),
    ],
  );

  Widget _buildOptions(ThemeData theme, ServicePack pack) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Card(
        child: ListTile(
          leading: const Icon(Icons.check_circle, color: Colors.green),
          title: Text(pack.title),
          subtitle: Text(
            '${Money.format(pack.price)} · ${pack.durationMinutes} min',
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text('Options (facultatives)', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(
        'Une option ajoute un supplément de prix — et parfois de durée — que '
        'le client choisit à la réservation.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 8),
      for (final PackOption option in _options)
        ListTile(
          leading: const Icon(Icons.add_circle_outline),
          title: Text(option.title),
          subtitle: Text(
            option.durationMinutes > 0
                ? '${Money.format(option.price)} · '
                      '+${option.durationMinutes} min'
                : Money.format(option.price),
          ),
        ),
      OutlinedButton.icon(
        onPressed: _addOption,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter une option'),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Terminer'),
      ),
    ],
  );
}

/// Saisie d'une option — P4b.
class _OptionSheet extends ConsumerStatefulWidget {
  const _OptionSheet({required this.packId});

  final String packId;

  @override
  ConsumerState<_OptionSheet> createState() => _OptionSheetState();
}

class _OptionSheetState extends ConsumerState<_OptionSheet>
    with FormSubmissionMixin<_OptionSheet> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _duration = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().length < ContentLimits.packTitleMinLength) {
      showFormError(
        'Le titre doit contenir au moins '
        '${ContentLimits.packTitleMinLength} caractères.',
      );
      return;
    }
    final num? price = num.tryParse(_price.text.trim());
    if (price == null || price < 0) {
      showFormError('Le prix est un nombre positif ou nul.');
      return;
    }
    final String durationText = _duration.text.trim();
    final int? duration = durationText.isEmpty
        ? null
        : int.tryParse(durationText);
    if (durationText.isNotEmpty &&
        (duration == null ||
            duration < ContentLimits.optionDurationMinMinutes ||
            duration > ContentLimits.optionDurationMaxMinutes)) {
      showFormError(
        'La durée va de ${ContentLimits.optionDurationMinMinutes} à '
        '${ContentLimits.optionDurationMaxMinutes} minutes.',
      );
      return;
    }

    final PackOption? option = await submit<PackOption>(
      () => ref
          .read(providerSelfRepositoryProvider)
          .createOption(
            widget.packId,
            title: _title.text.trim(),
            price: price,
            durationMinutes: duration,
          ),
    );
    if (option != null && mounted) {
      Navigator.of(context).pop(option);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Nouvelle option', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            maxLength: ContentLimits.packTitleMaxLength,
            enabled: !isSubmitting,
            decoration: InputDecoration(
              labelText: 'Titre de l’option',
              border: const OutlineInputBorder(),
              errorText: fieldErrors['title'],
            ),
            onChanged: (String _) => clearFieldError('title'),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _price,
                  keyboardType: TextInputType.number,
                  enabled: !isSubmitting,
                  decoration: InputDecoration(
                    labelText: 'Prix (${AppFormats.currencyCode})',
                    border: const OutlineInputBorder(),
                    errorText: fieldErrors['price'],
                  ),
                  onChanged: (String _) => clearFieldError('price'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _duration,
                  keyboardType: TextInputType.number,
                  enabled: !isSubmitting,
                  decoration: InputDecoration(
                    labelText: 'Durée (min, facultatif)',
                    border: const OutlineInputBorder(),
                    errorText: fieldErrors['durationMinutes'],
                  ),
                  onChanged: (String _) => clearFieldError('durationMinutes'),
                ),
              ),
            ],
          ),
          if (formError case final String message) ...<Widget>[
            const SizedBox(height: 8),
            Text(message, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: isSubmitting ? null : _submit,
            child: isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Ajouter l’option'),
          ),
        ],
      ),
    );
  }
}
