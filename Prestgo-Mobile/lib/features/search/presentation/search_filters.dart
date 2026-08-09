// Panneau de filtres (T099, FR-023, FR-024).
//
// Le point central de cet écran n'est pas ce qu'il permet, mais ce qu'il **empêche** :
//
//   • le tri « distance » est désactivé tant qu'aucune position n'est fournie, avec
//     l'explication à côté. Le laisser actif enverrait une requête que le service
//     refuse — l'utilisateur découvrirait le problème après coup, sans comprendre
//     (scénario 2.2) ;
//   • la date et l'heure sont **un seul** contrôle. On ne peut pas choisir l'une
//     sans l'autre, parce que le service les exige ensemble (scénario 2.3).
//
// Les deux refus du service deviennent ainsi structurellement inatteignables.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/location/location_service.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/search/domain/catalog.dart';
import 'package:prestgo_mobile/features/search/domain/provider_search.dart';
import 'package:prestgo_mobile/features/search/presentation/search_controller.dart';

/// Ouvre le panneau en feuille modale.
Future<void> showSearchFilters(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (BuildContext context) => const SearchFiltersSheet(),
    );

class SearchFiltersSheet extends ConsumerStatefulWidget {
  const SearchFiltersSheet({super.key});

  @override
  ConsumerState<SearchFiltersSheet> createState() => _SearchFiltersSheetState();
}

class _SearchFiltersSheetState extends ConsumerState<SearchFiltersSheet> {
  String? _locationNotice;
  bool _requestingLocation = false;

  Future<void> _requestPosition() async {
    setState(() => _requestingLocation = true);
    final LocationResult result = await ref
        .read(searchQueryProvider.notifier)
        .requestPosition();
    if (!mounted) {
      return;
    }
    setState(() {
      _requestingLocation = false;
      // Un refus n'est pas une erreur : c'est un choix, qu'on explique sans
      // insister.
      _locationNotice = result.explanation;
    });
  }

  Future<void> _pickSlot(ProviderSearchQuery query) async {
    final DateTime now = DateTime.now();
    final DateTime? day = await showDatePicker(
      context: context,
      initialDate: query.slot?.date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
      helpText: 'Date d’intervention',
    );
    if (day == null || !mounted) {
      return;
    }

    // Enchaînement immédiat sur l'heure : c'est ce qui rend le couple
    // indissociable. Abandonner ici laisse le créneau **inchangé**, jamais à moitié
    // renseigné.
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Heure de début',
    );
    if (time == null || !mounted) {
      return;
    }

    ref
        .read(searchQueryProvider.notifier)
        .setSlot(
          SearchSlot(
            date: DateTime.utc(day.year, day.month, day.day),
            startTime: ClockTime.parse(
              '${time.hour.toString().padLeft(2, '0')}:'
              '${time.minute.toString().padLeft(2, '0')}',
            ).value,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ProviderSearchQuery query = ref.watch(searchQueryProvider);
    final SearchQueryController controller = ref.read(
      searchQueryProvider.notifier,
    );
    final List<Category> categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final List<Zone> zones = ref.watch(zonesProvider).value ?? const <Zone>[];

    final Category? selectedCategory = categories
        .where((Category c) => c.id == query.categoryId)
        .firstOrNull;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Filtrer', style: theme.textTheme.titleLarge),
              const Spacer(),
              if (query.hasFilters)
                TextButton(
                  onPressed: controller.clearFilters,
                  child: const Text('Tout retirer'),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // --- Catégorie et type ------------------------------------------
          const _SectionLabel('Métier'),
          _ChoiceRow<String>(
            options: <_Choice<String>>[
              for (final Category category in categories)
                _Choice<String>(value: category.id, label: category.name),
            ],
            selected: query.categoryId,
            onSelected: controller.setCategory,
          ),
          if (selectedCategory != null &&
              selectedCategory.serviceTypes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const _SectionLabel('Prestation'),
            _ChoiceRow<String>(
              options: <_Choice<String>>[
                for (final ServiceType type in selectedCategory.serviceTypes)
                  _Choice<String>(value: type.id, label: type.name),
              ],
              selected: query.serviceTypeId,
              onSelected: controller.setServiceType,
            ),
          ],

          const Divider(height: 32),

          // --- Position et rayon ------------------------------------------
          const _SectionLabel('Autour de moi'),
          if (query.position == null)
            OutlinedButton.icon(
              onPressed: _requestingLocation ? null : _requestPosition,
              icon: const Icon(Icons.my_location),
              label: Text(
                _requestingLocation
                    ? 'Recherche de votre position…'
                    : 'Utiliser ma position',
              ),
            )
          else
            Row(
              children: <Widget>[
                Icon(Icons.check_circle, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                const Expanded(child: Text('Position prise en compte')),
                TextButton(
                  onPressed: () => controller.setPosition(null),
                  child: const Text('Retirer'),
                ),
              ],
            ),
          if (_locationNotice case final String notice) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              notice,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (query.position != null) ...<Widget>[
            const SizedBox(height: 8),
            Text('Rayon : ${query.radiusKm.round()} km'),
            Slider(
              value: query.radiusKm,
              min: PaginationLimits.minRadiusKm,
              max: PaginationLimits.maxRadiusKm,
              divisions: 49,
              label: '${query.radiusKm.round()} km',
              onChanged: controller.setRadius,
            ),
          ],

          const Divider(height: 32),

          // --- Zone ---------------------------------------------------------
          const _SectionLabel('Zone'),
          _ChoiceRow<String>(
            options: <_Choice<String>>[
              for (final Zone zone in zones)
                _Choice<String>(value: zone.id, label: zone.name),
            ],
            selected: query.zoneId,
            onSelected: controller.setZone,
          ),

          const Divider(height: 32),

          // --- Créneau : date ET heure, indissociables ----------------------
          const _SectionLabel('Créneau souhaité'),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(
              query.slot == null
                  ? 'Choisir une date et une heure'
                  : '${DateLabels.day(query.slot!.date)} à '
                        '${query.slot!.startTime}',
            ),
            subtitle: const Text('La date et l’heure vont toujours ensemble.'),
            trailing: query.slot == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Retirer le créneau',
                    onPressed: () => controller.setSlot(null),
                  ),
            onTap: () => _pickSlot(query),
          ),

          const Divider(height: 32),

          // --- Note minimale ------------------------------------------------
          const _SectionLabel('Note minimale'),
          _ChoiceRow<double>(
            options: const <_Choice<double>>[
              _Choice<double>(value: 3, label: '3 et +'),
              _Choice<double>(value: 4, label: '4 et +'),
              _Choice<double>(value: 4.5, label: '4,5 et +'),
            ],
            selected: query.minRating,
            onSelected: controller.setMinRating,
          ),

          const Divider(height: 32),

          // --- Tri ----------------------------------------------------------
          const _SectionLabel('Trier par'),
          for (final SearchSort sort in SearchSort.values)
            _SortTile(
              sort: sort,
              selected: query.sort == sort,
              // ⚠️ Le tri par distance exige une position : sans elle, le
              // service répond 400. L'option est donc fermée, avec sa raison.
              enabled:
                  sort != SearchSort.distance || query.isDistanceSortAvailable,
              onSelected: () => controller.setSort(sort),
            ),

          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: const Text('Voir les résultats'),
          ),
        ],
      ),
    );
  }
}

class _SortTile extends StatelessWidget {
  const _SortTile({
    required this.sort,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  final SearchSort sort;
  final bool selected;
  final bool enabled;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    enabled: enabled,
    leading: Icon(
      selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
    ),
    title: Text(sort.label),
    // L'explication tient lieu de refus : elle dit ce qu'il faut faire pour lever
    // l'indisponibilité, plutôt que de laisser l'option grisée sans raison.
    subtitle: enabled
        ? null
        : const Text('Autorisez votre position pour trier par distance.'),
    onTap: enabled ? onSelected : null,
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Choice<T> {
  const _Choice({required this.value, required this.label});

  final T value;
  final String label;
}

/// Rangée de puces à choix unique — resélectionner la puce active la retire.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<_Choice<T>> options;
  final T? selected;
  final void Function(T? value) onSelected;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final _Choice<T> option in options)
          FilterChip(
            label: Text(option.label),
            selected: selected == option.value,
            onSelected: (bool isSelected) =>
                onSelected(isSelected ? option.value : null),
          ),
      ],
    );
  }
}
