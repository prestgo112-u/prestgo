// P3 — Déclaration d'un service (T152, FR-053).
//
// Le sélecteur est à deux niveaux — catégorie puis type de service — parce que
// c'est la forme du catalogue (`GET /categories`, tableau nu non paginé). Les
// services déjà déclarés s'affichent en tête : un service **sans formule active**
// y est signalé et rouvre directement l'étape formule — c'est le piège n°2 de la
// checklist (scénario 4.2), et c'est aussi le chemin de reprise naturel.
//
// Deux issues d'erreur guidées plutôt que des bannières brutes :
//   • 404 « type inactif » → le catalogue a changé : il est rechargé ;
//   • 409 « doublon de type » → redirection vers le service existant, dont il ne
//     manque probablement que la formule.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/pack_step_screen.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_offer.dart';
import 'package:prestgo_mobile/shared/catalog/catalog.dart';

/// Catégories et services existants, chargés ensemble à l'ouverture.
typedef _StepData = ({
  List<Category> categories,
  List<ProviderService> services,
});

final FutureProvider<_StepData> _stepDataProvider =
    FutureProvider.autoDispose<_StepData>((Ref ref) async {
      final ProviderSelfRepository repository = ref.watch(
        providerSelfRepositoryProvider,
      );
      final List<Category> categories = await repository.categories();
      final List<ProviderService> services = await repository.services();
      return (categories: categories, services: services);
    });

class ServiceStepScreen extends ConsumerWidget {
  const ServiceStepScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<_StepData> data = ref.watch(_stepDataProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mes prestations')),
      body: switch (data) {
        AsyncValue<_StepData>(:final _StepData value) => _ServiceStepBody(
          categories: value.categories,
          services: value.services,
        ),
        AsyncValue<_StepData>(:final Object error?) => ErrorView(
          message: error is ApiException
              ? error.message
              : 'Impossible de charger le catalogue. Réessayez.',
          onRetry: () => ref.invalidate(_stepDataProvider),
        ),
        _ => const LoadingView(label: 'Chargement du catalogue…'),
      },
    );
  }
}

class _ServiceStepBody extends ConsumerStatefulWidget {
  const _ServiceStepBody({required this.categories, required this.services});

  final List<Category> categories;
  final List<ProviderService> services;

  @override
  ConsumerState<_ServiceStepBody> createState() => _ServiceStepBodyState();
}

class _ServiceStepBodyState extends ConsumerState<_ServiceStepBody>
    with FormSubmissionMixin<_ServiceStepBody> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  Category? _category;
  ServiceType? _serviceType;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _openPackStep(String serviceId, String serviceTitle) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PackStepScreen(
          providerServiceId: serviceId,
          serviceTitle: serviceTitle,
        ),
      ),
    );
    if (mounted) {
      ref.invalidate(_stepDataProvider);
    }
  }

  Future<void> _submit() async {
    final ServiceType? serviceType = _serviceType;
    if (serviceType == null) {
      showFormError('Choisissez une catégorie puis un type de service.');
      return;
    }
    final String title = _title.text.trim();
    if (title.length < ContentLimits.serviceTitleMinLength) {
      showFormError(
        'Le titre doit contenir au moins '
        '${ContentLimits.serviceTitleMinLength} caractères.',
      );
      return;
    }

    final ProviderService? service = await submit<ProviderService>(
      () => ref
          .read(providerSelfRepositoryProvider)
          .createService(
            serviceTypeId: serviceType.id,
            title: title,
            description: _description.text.trim(),
          ),
    );
    if (!mounted) {
      return;
    }

    if (service != null) {
      // P3 enchaîne sur P4 : un service sans formule ne compte pas.
      await _openPackStep(service.id, service.title);
      return;
    }

    final ApiException? failure = lastFailure;
    if (failure == null) {
      return;
    }
    if (failure.isConflict) {
      // Doublon de type : le service existe — y aller plutôt qu'échouer.
      final ProviderService? existing = widget.services
          .where((ProviderService s) => s.serviceTypeId == serviceType.id)
          .firstOrNull;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
      if (existing != null) {
        await _openPackStep(existing.id, existing.title);
      } else {
        ref.invalidate(_stepDataProvider);
      }
      return;
    }
    if (failure.isNotFound) {
      // Type inactif : le catalogue a changé entre l'affichage et l'envoi.
      setState(() {
        _category = null;
        _serviceType = null;
      });
      ref.invalidate(_stepDataProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Category? category = _category;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (widget.services.isNotEmpty) ...<Widget>[
            Text('Services déclarés', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final ProviderService service in widget.services)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(service.title),
                  subtitle: Text(
                    service.hasActivePack
                        ? service.serviceType?.label ?? 'Formule active'
                        : 'Aucune formule active — ce service ne compte pas '
                              'encore pour votre dossier.',
                    style: service.hasActivePack
                        ? null
                        : TextStyle(color: theme.colorScheme.error),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openPackStep(service.id, service.title),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Déclarer un autre service',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
          ],
          DropdownMenu<Category>(
            key: const ValueKey<String>('category-selector'),
            label: const Text('Catégorie'),
            expandedInsets: EdgeInsets.zero,
            initialSelection: category,
            dropdownMenuEntries: <DropdownMenuEntry<Category>>[
              for (final Category entry in widget.categories)
                DropdownMenuEntry<Category>(value: entry, label: entry.name),
            ],
            onSelected: (Category? value) => setState(() {
              _category = value;
              _serviceType = null;
              showFormError(null);
            }),
          ),
          const SizedBox(height: 12),
          DropdownMenu<ServiceType>(
            key: ValueKey<String>('type-selector-${category?.id}'),
            label: const Text('Type de service'),
            expandedInsets: EdgeInsets.zero,
            enabled: category != null,
            initialSelection: _serviceType,
            dropdownMenuEntries: <DropdownMenuEntry<ServiceType>>[
              for (final ServiceType entry
                  in category?.serviceTypes ?? const <ServiceType>[])
                DropdownMenuEntry<ServiceType>(value: entry, label: entry.name),
            ],
            onSelected: (ServiceType? value) => setState(() {
              _serviceType = value;
              showFormError(null);
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            maxLength: ContentLimits.serviceTitleMaxLength,
            enabled: !isSubmitting,
            decoration: InputDecoration(
              labelText: 'Titre du service',
              hintText: 'Ex. : Dépannage plomberie à domicile',
              border: const OutlineInputBorder(),
              errorText: fieldErrors['title'],
            ),
            onChanged: (String _) => clearFieldError('title'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLength: ContentLimits.serviceDescriptionMaxLength,
            maxLines: 3,
            enabled: !isSubmitting,
            decoration: InputDecoration(
              labelText: 'Description (facultative)',
              border: const OutlineInputBorder(),
              errorText: fieldErrors['description'],
            ),
            onChanged: (String _) => clearFieldError('description'),
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
                : const Text('Déclarer ce service'),
          ),
          const SizedBox(height: 8),
          Text(
            'Vous définirez ensuite la formule tarifaire de ce service : sans '
            'elle, le service ne compte pas pour votre dossier.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
