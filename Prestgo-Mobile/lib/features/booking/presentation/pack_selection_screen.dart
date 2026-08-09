// Étape 1 — formule et options (T111, FR-029, FR-030).
//
// Le prix total et la durée totale sont recalculés **à chaque coche**, sous les yeux
// de l'utilisateur. Ce n'est pas de l'agrément : le montant affiché ici doit être
// exactement celui que le service figera à la réservation (scénario 2.5). Un écart
// se verrait au récapitulatif, trop tard.
//
// Changer de formule remet les options à zéro : elles appartenaient à l'ancienne, et
// le service refuserait « Option inconnue pour cette formule ».

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/format/money.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_draft.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_rules.dart';
import 'package:prestgo_mobile/features/booking/presentation/booking_draft_controller.dart';
import 'package:prestgo_mobile/features/booking/presentation/widgets/booking_total_bar.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/search/presentation/provider_profile_screen.dart';

class PackSelectionScreen extends ConsumerStatefulWidget {
  const PackSelectionScreen({required this.providerId, super.key});

  final String providerId;

  @override
  ConsumerState<PackSelectionScreen> createState() =>
      _PackSelectionScreenState();
}

class _PackSelectionScreenState extends ConsumerState<PackSelectionScreen> {
  @override
  void initState() {
    super.initState();
    // Le brouillon s'ouvre une fois la fiche chargée : il en a besoin pour
    // l'agenda, les absences et les zones des étapes suivantes.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureDraft());
  }

  void _ensureDraft() {
    final ProviderPublicProfile? provider = ref
        .read(providerProfileProvider(widget.providerId))
        .value;
    if (provider == null || !mounted) {
      return;
    }
    final BookingState? current = ref.read(bookingDraftProvider);
    // Repartir d'un brouillon neuf uniquement si l'on change de prestataire :
    // revenir en arrière depuis le récapitulatif doit conserver la composition.
    if (current == null || current.draft.provider.id != provider.id) {
      ref.read(bookingDraftProvider.notifier).start(provider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ProviderPublicProfile> profile = ref.watch(
      providerProfileProvider(widget.providerId),
    );
    final BookingState? booking = ref.watch(bookingDraftProvider);

    // Le brouillon est ouvert au premier cadre suivant le chargement.
    ref.listen<AsyncValue<ProviderPublicProfile>>(
      providerProfileProvider(widget.providerId),
      (
        AsyncValue<ProviderPublicProfile>? previous,
        AsyncValue<ProviderPublicProfile> next,
      ) {
        if (next.hasValue) {
          _ensureDraft();
        }
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Formule et options')),
      body: profile.when(
        loading: () => const LoadingView(label: 'Chargement de l’offre…'),
        error: (Object error, StackTrace _) => ErrorView(
          message: error is ApiException
              ? error.message
              : ApiFallbackMessages.unknown,
          onRetry: () =>
              ref.invalidate(providerProfileProvider(widget.providerId)),
        ),
        data: (ProviderPublicProfile provider) => booking == null
            ? const LoadingView()
            : _Body(provider: provider, draft: booking.draft),
      ),
      bottomNavigationBar: booking?.draft.pack == null
          ? null
          : BookingTotalBar(
              draft: booking!.draft,
              label: 'Choisir la date',
              onContinue: () => context.push(Routes.bookingSchedule),
            ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.provider, required this.draft});

  final ProviderPublicProfile provider;
  final BookingDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BookingDraftController controller = ref.read(
      bookingDraftProvider.notifier,
    );
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        Text(provider.publicName, style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),

        Text('Choisissez une formule', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final PublicService service in provider.services)
          for (final ServicePack pack in service.packs)
            _PackTile(
              pack: pack,
              serviceTitle: service.title,
              selected: draft.pack?.id == pack.id,
              onSelected: () => controller.selectPack(pack),
            ),

        if (draft.pack case final ServicePack pack) ...<Widget>[
          if (pack.options.isNotEmpty) ...<Widget>[
            const Divider(height: 32),
            Text('Options', style: theme.textTheme.titleSmall),
            Text(
              'Chaque option ajoute son prix, et parfois sa durée.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final PackOption option in pack.options)
              CheckboxListTile(
                value: draft.optionIds.contains(option.id),
                onChanged: (_) => controller.toggleOption(option.id),
                contentPadding: EdgeInsets.zero,
                title: Text(option.title),
                subtitle: Text(
                  option.durationMinutes == 0
                      ? '+ ${Money.format(option.price)}'
                      : '+ ${Money.format(option.price)} · '
                            '+ ${BookingRules.formatDuration(option.durationMinutes)}',
                ),
              ),
          ],
        ],
      ],
    );
  }
}

class _PackTile extends StatelessWidget {
  const _PackTile({
    required this.pack,
    required this.serviceTitle,
    required this.selected,
    required this.onSelected,
  });

  final ServicePack pack;
  final String serviceTitle;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: selected ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: onSelected,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? theme.colorScheme.primary : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(pack.title, style: theme.textTheme.titleSmall),
                    Text(serviceTitle, style: theme.textTheme.bodySmall),
                    if (pack.description case final String description)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          description,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      BookingRules.formatDuration(pack.durationMinutes),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                Money.format(pack.price),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
