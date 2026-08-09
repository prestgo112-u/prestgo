// Détail de mission (T128, FR-039, FR-040, FR-044, FR-045).
//
// Trois règles de rendu, toutes issues du contrat :
//   • `quotedAmount` nul s'affiche « — », jamais « 0 XOF » — les missions
//     antérieures au montant figé existent en base ;
//   • une annulation tardive est **signalée explicitement** (`late`) ;
//   • **aucune coordonnée personnelle** de l'autre partie : la mise en relation
//     passe par la messagerie, dont l'entrée est le fil de la mission.
//
// Les actions affichées se déduisent du statut (data-model §5.3) mais la machine
// à états reste au service (porte G1) : au pire, une action affichée à tort est
// refusée avec son message, jamais l'inverse silencieux. L'écran sert les DEUX
// rôles : le lecteur est reconnu par `me.id` (client) ou `me.providerId`
// (prestataire), et les actions prestataire vivent dans `MissionActionsBar`
// (T170) — jamais « Refuser » et « Annuler » ensemble.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/connectivity/offline_gate.dart';
import 'package:prestgo_mobile/core/connectivity/reconnect_refresher.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/files/file_avatar.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/format/money.dart';
import 'package:prestgo_mobile/core/widgets/data_age_label.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/missions/domain/cancellation.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_detail.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_history.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';
import 'package:prestgo_mobile/features/missions/presentation/cancel_mission_sheet.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_actions_bar.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_providers.dart';
import 'package:prestgo_mobile/features/missions/presentation/reschedule_request_screen.dart';
import 'package:prestgo_mobile/features/missions/presentation/reschedule_response_view.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';
import 'package:prestgo_mobile/features/reviews/domain/review_eligibility.dart';
import 'package:prestgo_mobile/features/reviews/presentation/submit_review_screen.dart';

class MissionDetailScreen extends ConsumerWidget {
  const MissionDetailScreen({required this.missionId, super.key});

  final String missionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<MissionDetail> detail = ref.watch(
      missionDetailProvider(missionId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Détail de la mission'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Historique de la mission',
            onPressed: () => context.push(Routes.missionHistoryFor(missionId)),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const LoadingView(label: 'Chargement de la mission…'),
        error: (Object error, StackTrace _) => ErrorView(
          message: error is ApiException
              ? error.message
              : ApiFallbackMessages.unknown,
          onRetry: () => ref.invalidate(missionDetailProvider(missionId)),
        ),
        data: (MissionDetail mission) => _MissionDetailBody(mission: mission),
      ),
    );
  }
}

class _MissionDetailBody extends ConsumerWidget {
  const _MissionDetailBody({required this.mission});

  final MissionDetail mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Me? me = ref.watch(meControllerProvider).value;
    final bool asClient = mission.isClient(me?.id ?? '');
    // Le lecteur est-il LE prestataire de cette mission ? Comparé sur
    // `providerId`, jamais sur `roles` (FR-013).
    final bool asProvider =
        me?.providerId != null && me?.providerId == mission.provider.id;

    // Au retour du réseau, l'écran courant se relit tout seul (10.3).
    return RefreshOnReconnect(
      onReconnect: () => invalidateAfterMissionWrite(ref, mission.id),
      child: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(missionDetailProvider(mission.id)),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _StatusHeader(mission: mission),
            const SizedBox(height: 4),
            _OfflineDataAge(missionId: mission.id),
            if (mission.cancellation
                case final Cancellation cancellation) ...<Widget>[
              const SizedBox(height: 12),
              _CancellationBanner(cancellation: cancellation),
            ],
            if (mission.pendingReschedule != null) ...<Widget>[
              const SizedBox(height: 12),
              RescheduleResponseView(
                mission: mission,
                reschedule: mission.pendingReschedule!,
              ),
            ],
            const SizedBox(height: 12),
            _ServiceCard(mission: mission),
            if (mission.address != null) ...<Widget>[
              const SizedBox(height: 12),
              _AddressCard(address: mission.address!),
            ],
            if (mission.instructions case final String instructions
                when instructions.isNotEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _InstructionsCard(instructions: instructions),
            ],
            const SizedBox(height: 12),
            _ProviderCard(mission: mission),
            const SizedBox(height: 16),
            _ActionsArea(
              mission: mission,
              asClient: asClient,
              asProvider: asProvider,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hors ligne, le détail servi par le cache s'affiche AVEC son âge (10.1).
class _OfflineDataAge extends ConsumerWidget {
  const _OfflineDataAge({required this.missionId});

  final String missionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool online = ref.watch(isOnlineProvider).value ?? true;
    if (online) {
      return const SizedBox.shrink();
    }
    final DateTime? fetchedAt = ref
        .watch(missionDetailFetchedAtProvider(missionId))
        .value;
    return fetchedAt == null
        ? const SizedBox.shrink()
        : DataAgeLabel(fetchedAt: fetchedAt);
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.mission});

  final MissionDetail mission;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateTime? scheduledAt = mission.scheduledAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Chip(label: Text(mission.statusLabel)),
        const SizedBox(height: 4),
        if (scheduledAt != null)
          Text(
            'Prévue le ${DateLabels.dayAndTime(scheduledAt)}',
            style: theme.textTheme.titleMedium,
          ),
      ],
    );
  }
}

/// L'annulation, avec la tardiveté **affichée explicitement** (FR-045).
class _CancellationBanner extends StatelessWidget {
  const _CancellationBanner({required this.cancellation});

  final Cancellation cancellation;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? details = cancellation.details;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            cancellation.late
                ? 'Mission annulée — annulation tardive'
                : 'Mission annulée',
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Motif : ${cancellation.reason}',
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          if (details != null && details.isNotEmpty)
            Text(
              details,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.mission});

  final MissionDetail mission;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? serviceLine =
        <String?>[
          mission.pack.serviceTitle,
          mission.pack.serviceTypeName,
        ].whereType<String>().isEmpty
        ? null
        : <String?>[
            mission.pack.serviceTitle,
            mission.pack.serviceTypeName,
          ].whereType<String>().join(' · ');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Prestation', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(mission.pack.title, style: theme.textTheme.bodyLarge),
            if (serviceLine != null)
              Text(
                serviceLine,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            for (final MissionOption option in mission.options)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.add, size: 14),
                    const SizedBox(width: 4),
                    Expanded(child: Text(option.title)),
                    Text(Money.format(option.price)),
                  ],
                ),
              ),
            const Divider(),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('Montant', style: theme.textTheme.titleSmall),
                ),
                // « — » quand le montant n'existe pas — jamais « 0 XOF ».
                Text(
                  Money.formatOrAbsent(mission.quotedAmount),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.address});

  final Address address;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.place_outlined),
      title: Text(address.label),
      subtitle: Text(address.fullLine),
    ),
  );
}

class _InstructionsCard extends StatelessWidget {
  const _InstructionsCard({required this.instructions});

  final String instructions;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.notes_outlined),
      title: const Text('Instructions'),
      subtitle: Text(instructions),
    ),
  );
}

/// Le prestataire — sa vitrine publique, **aucun contact direct**.
class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.mission});

  final MissionDetail mission;

  @override
  Widget build(BuildContext context) {
    final MissionProviderSummary provider = mission.provider;

    return Card(
      child: ListTile(
        leading: ProviderAvatar(name: provider.publicName, radius: 24),
        title: Text(provider.publicName),
        subtitle: Text(
          provider.isNew
              ? 'Nouveau'
              : '${provider.score.toStringAsFixed(1)} '
                    '(${provider.reviewsCount} avis)',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push(Routes.providerProfileFor(provider.id)),
      ),
    );
  }
}

/// Zone d'avis du client (US9, scénarios 9.1 et 9.3).
///
/// Les quatre conditions sont locales (`reviewEligibilityFor`) ; la fenêtre
/// est datée par l'entrée en `completed` de l'HISTORIQUE et dimensionnée par
/// le réglage `reviewsWindowDays` (porte G3). Un avis déjà déposé retire
/// l'action et renvoie vers « Mes avis ».
class _ReviewArea extends ConsumerWidget {
  const _ReviewArea({required this.mission});

  final MissionDetail mission;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool ratableStatus =
        mission.status == MissionStatus.completed ||
        mission.status == MissionStatus.closed;
    if (!ratableStatus) {
      return const SizedBox.shrink();
    }

    final Me? me = ref.watch(meControllerProvider).value;
    if (mission.hasReviewBy(me?.id ?? '')) {
      // 9.3 — action retirée, avis consultable.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 8),
          Text(
            'Vous avez déjà noté cette mission.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: () => context.push(Routes.reviews),
            child: const Text('Voir mes avis'),
          ),
        ],
      );
    }

    // L'historique date l'entrée en `completed` ; tant qu'il charge, rien ne
    // s'affiche — mieux vaut une demi-seconde de retard qu'un bouton qui
    // clignote. S'il échoue, l'action s'affiche sans temps restant : le
    // service reste l'autorité.
    final AsyncValue<MissionHistory> history = ref.watch(
      missionHistoryProvider(mission.id),
    );
    final DateTime? completedAt = switch (history) {
      AsyncValue<MissionHistory>(:final MissionHistory value) =>
        value.completedAt,
      AsyncValue<MissionHistory>(hasError: true) => null,
      _ => null,
    };
    if (history.isLoading) {
      return const SizedBox.shrink();
    }

    final ReviewEligibility verdict = reviewEligibilityFor(
      status: mission.status,
      isClient: true,
      alreadyReviewed: false,
      completedAt: completedAt,
      window: ref.watch(publicSettingsProvider).reviewsWindow,
      now: DateTime.now(),
    );
    if (!verdict.canSubmit) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => SubmitReviewScreen(
                missionId: mission.id,
                remaining: verdict.remaining,
              ),
            ),
          ),
          icon: const Icon(Icons.star_outline_rounded),
          label: const Text('Laisser un avis'),
        ),
        if (verdict.remaining case final Duration remaining)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              remainingWindowLabel(remaining),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _ActionsArea extends ConsumerWidget {
  const _ActionsArea({
    required this.mission,
    required this.asClient,
    required this.asProvider,
  });

  final MissionDetail mission;
  final bool asClient;
  final bool asProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final MissionThreadRef? thread = mission.thread;
    final bool reschedulePending = mission.pendingReschedule != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // La messagerie est la seule mise en relation — le fil existe dès la
        // création de la mission.
        if (thread != null)
          OutlinedButton.icon(
            // La mission accompagne le fil : la conversation lira son statut
            // par l'opération 50 sans dépendre du chargement de /me/threads.
            onPressed: () => context.push(
              Routes.conversationFor(thread.id, missionId: mission.id),
            ),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Ouvrir la conversation'),
          ),
        if (mission.status == MissionStatus.disputed) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Un litige est en cours sur cette mission. Vous serez averti de '
              'chaque évolution.',
              style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
            ),
          ),
        ],
        // Le report se propose des DEUX côtés (data-model §5.3) — même
        // mécanique, même limite d'une seule demande en attente (FR-047).
        if ((asClient || asProvider) &&
            mission.status.isReschedulable) ...<Widget>[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            // UNE seule demande en attente à la fois : l'action est grisée
            // tant qu'elle existe, avec son explication (scénario 3.3).
            onPressed: reschedulePending
                ? null
                : () => openRescheduleRequest(context, mission: mission),
            icon: const Icon(Icons.update),
            label: const Text('Proposer un report'),
          ),
          if (reschedulePending)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Une demande de report est déjà en attente de réponse.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
        // Accepter, refuser, démarrer, terminer, annuler : la barre applique la
        // table des états — aucun bouton sur un état terminal (T170).
        if (asProvider) ...<Widget>[
          const SizedBox(height: 8),
          MissionActionsBar(mission: mission),
        ],
        // La notation est CLIENT SEUL (T227, scénario 9.2) : aucune action
        // d'avis n'existe côté prestataire — ni ici, ni dans la barre
        // d'actions. Le 403 du service n'est que le filet.
        if (asClient) ...<Widget>[
          _ReviewArea(mission: mission),
          if (mission.status == MissionStatus.completed) ...<Widget>[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  context.push(Routes.missionDisputeFor(mission.id)),
              icon: const Icon(Icons.gavel),
              label: const Text('Ouvrir un litige'),
            ),
          ],
          if (mission.status.clientMayCancel) ...<Widget>[
            const SizedBox(height: 8),
            // Hors ligne, l'annulation est indisponible AVEC son explication —
            // et rien n'est mis en file (10.2, T234).
            OfflineWriteGuard(
              builder: (BuildContext context, bool canWrite) => TextButton.icon(
                onPressed: canWrite
                    ? () => showCancelMissionSheet(context, mission: mission)
                    : null,
                icon: Icon(
                  Icons.cancel_outlined,
                  color: canWrite ? theme.colorScheme.error : null,
                ),
                label: Text(
                  'Annuler la mission',
                  style: TextStyle(
                    color: canWrite ? theme.colorScheme.error : null,
                  ),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }
}
