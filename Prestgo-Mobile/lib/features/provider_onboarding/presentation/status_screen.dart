// P9 — Suivi du dossier (T158, FR-060, FR-064, FR-065).
//
// Un seul appel — `GET /providers/me` — alimente les cinq états, et il n'existe
// pas de flux temps réel : rafraîchissement au geste et au retour sur l'écran.
// Les actions par état suivent le §2.2 P9 du cahier des charges :
//
//   pending_review    — date de soumission, rappel des étapes validées, AUCUNE
//                       modification de fond ; l'interrupteur de disponibilité
//                       reste actif (scénario 4.8) ;
//   changes_requested — motif EN TÊTE, corrections ouvertes (hub + accès direct
//                       aux justificatifs) ; « Re-soumettre » si `canSubmit` —
//                       et si le motif porte sur un document, le redépôt fait
//                       repartir le dossier tout seul, sans re-soumission ;
//   rejected          — motif ; mêmes corrections si la re-soumission est
//                       ouverte, contact support seul sinon ;
//   approved          — bascule vers l'espace prestataire ;
//   suspended         — contact support, aucune action de gestion.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/auth/presentation/logout_action.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/documents_step_screen.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_overview_controller.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/submit_controller.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/availability_switch.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/provider_profile_screen.dart';

/// Adresse affichée quand la seule issue est humaine.
const String kSupportContact = 'support@prestgo.ci';

class ProviderStatusScreen extends ConsumerWidget {
  const ProviderStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ProviderProfile> overview = ref.watch(
      providerOverviewProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon dossier prestataire'),
        // Écran d'atterrissage d'un dossier en vérification, refusé ou suspendu :
        // sans cette action, son titulaire n'a aucune issue — le tableau de bord
        // lui reste fermé tant que le dossier n'est pas approuvé.
        actions: const <Widget>[LogoutAction()],
      ),
      body: switch (overview) {
        AsyncValue<ProviderProfile>(:final ProviderProfile value) =>
          RefreshIndicator(
            onRefresh: () =>
                ref.read(providerOverviewProvider.notifier).reload(),
            child: _StatusBody(profile: value),
          ),
        AsyncValue<ProviderProfile>(:final Object error?) =>
          error is ApiException
              ? ErrorView.fromException(
                  error,
                  onRetry: () =>
                      ref.read(providerOverviewProvider.notifier).reload(),
                )
              : ErrorView(
                  message: 'Une erreur est survenue. Réessayez.',
                  onRetry: () =>
                      ref.read(providerOverviewProvider.notifier).reload(),
                ),
        _ => const LoadingView(label: 'Chargement du dossier…'),
      },
    );
  }
}

class _StatusBody extends ConsumerWidget {
  const _StatusBody({required this.profile});

  final ProviderProfile profile;

  Future<void> _resubmit(BuildContext context, WidgetRef ref) async {
    final ProviderProfile? submitted = await ref
        .read(submitControllerProvider.notifier)
        .submit();
    if (submitted != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dossier soumis à la vérification')),
      );
    }
  }

  Future<void> _openDocuments(BuildContext context, WidgetRef ref) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => const DocumentsStepScreen(),
      ),
    );
    // Un dépôt a pu faire repartir le dossier tout seul : la vérité se relit.
    await ref.read(providerOverviewProvider.notifier).reload();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SubmitState submitState = ref.watch(submitControllerProvider);
    final ProviderValidationStatus? status = profile.validationStatus;

    final (IconData icon, Color color, String title) = switch (status) {
      ProviderValidationStatus.pendingReview => (
        Icons.hourglass_top,
        theme.colorScheme.tertiary,
        'Dossier en cours de vérification',
      ),
      ProviderValidationStatus.changesRequested => (
        Icons.edit_note,
        theme.colorScheme.error,
        'Corrections demandées',
      ),
      ProviderValidationStatus.rejected => (
        Icons.cancel_outlined,
        theme.colorScheme.error,
        'Dossier refusé',
      ),
      ProviderValidationStatus.approved => (
        Icons.verified,
        Colors.green,
        'Dossier validé',
      ),
      ProviderValidationStatus.suspended => (
        Icons.pause_circle_outline,
        theme.colorScheme.error,
        'Compte suspendu',
      ),
      ProviderValidationStatus.profileIncomplete || null => (
        Icons.pending_actions_outlined,
        theme.colorScheme.tertiary,
        'Dossier à compléter',
      ),
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Icon(icon, size: 56, color: color),
        const SizedBox(height: 8),
        Text(
          title,
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),

        // Le motif d'abord — c'est lui qui dit quoi corriger.
        if (profile.rejectionReason case final String reason) ...<Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              reason,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
          const SizedBox(height: 16),
        ],

        ...switch (status) {
          ProviderValidationStatus.pendingReview => _pendingReview(theme, ref),
          ProviderValidationStatus.changesRequested ||
          ProviderValidationStatus.rejected => _corrections(
            context,
            ref,
            theme,
            submitState,
          ),
          ProviderValidationStatus.approved => _approved(context),
          ProviderValidationStatus.suspended => _suspended(theme),
          ProviderValidationStatus.profileIncomplete || null => <Widget>[
            FilledButton(
              onPressed: () => context.go(Routes.providerChecklist),
              child: const Text('Reprendre mon dossier'),
            ),
          ],
        },
      ],
    );
  }

  List<Widget> _pendingReview(ThemeData theme, WidgetRef ref) => <Widget>[
    if (profile.submittedAt case final DateTime submittedAt)
      Text(
        'Soumis le ${DateLabels.dayAndTime(submittedAt)}. Nos équipes '
        'examinent votre dossier — vous serez averti dès la décision.',
        style: theme.textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
    const SizedBox(height: 16),
    // Le rappel des cinq étapes validées : ce qui a été soumis, noir sur blanc.
    for (final ChecklistStep step in ChecklistStep.values)
      ListTile(
        dense: true,
        leading: Icon(
          profile.checklist[step]
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
          color: profile.checklist[step]
              ? Colors.green.shade700
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(step.title),
      ),
    const SizedBox(height: 8),
    Text(
      'Pendant la vérification, votre dossier n’est plus modifiable. Seule '
      'votre disponibilité reste réglable :',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
    const SizedBox(height: 8),
    // Le seul levier encore ouvert (4.8) — et l'accès au profil verrouillé,
    // en lecture seule, pour vérifier ce qui a été soumis.
    AvailabilityControl(profile: profile),
    const SizedBox(height: 8),
    Builder(
      builder: (BuildContext context) => OutlinedButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext context) =>
                const ProviderSpaceProfileScreen(),
          ),
        ),
        child: const Text('Voir mon profil'),
      ),
    ),
  ];

  List<Widget> _corrections(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    SubmitState submitState,
  ) {
    // Refusé ET bloqué : plus aucune correction n'aboutira — support seul.
    if (profile.resubmissionBlocked) {
      return <Widget>[
        Text(
          'La re-soumission de votre dossier a été bloquée. Contactez le '
          'support pour comprendre la décision.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        const _SupportTile(),
      ];
    }

    return <Widget>[
      Text(
        'Corrigez les éléments signalés puis re-soumettez votre dossier. Si '
        'le motif porte sur un justificatif, le simple redépôt le renvoie en '
        'vérification — sans re-soumission.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      for (final ChecklistStep step in ChecklistStep.values)
        ListTile(
          dense: true,
          leading: Icon(
            profile.checklist[step]
                ? Icons.check_circle
                : Icons.radio_button_unchecked,
            color: profile.checklist[step]
                ? Colors.green.shade700
                : theme.colorScheme.error,
          ),
          title: Text(step.title),
          subtitle: profile.checklist[step]
              ? null
              : Text(
                  step.requirementLabel,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
        ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => context.go(Routes.providerChecklist),
        icon: const Icon(Icons.folder_open_outlined),
        label: const Text('Ouvrir mon dossier'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => _openDocuments(context, ref),
        icon: const Icon(Icons.description_outlined),
        label: const Text('Mes justificatifs'),
      ),
      const SizedBox(height: 8),
      if (submitState.banner case final String banner) ...<Widget>[
        Text(
          banner,
          style: TextStyle(color: theme.colorScheme.error),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
      ],
      // « Re-soumettre » n'existe que si le service le permet : après un
      // redépôt de justificatif, `canSubmit` retombe et le bouton disparaît
      // de lui-même (scénario 4.9).
      if (profile.canSubmit)
        FilledButton(
          onPressed: submitState.submitting
              ? null
              : () => _resubmit(context, ref),
          child: submitState.submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Re-soumettre mon dossier'),
        ),
    ];
  }

  List<Widget> _approved(BuildContext context) => <Widget>[
    const Text(
      'Félicitations, votre dossier est validé : votre espace prestataire '
      'est ouvert.',
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 16),
    FilledButton(
      onPressed: () => context.go(Routes.providerDashboard),
      child: const Text('Ouvrir mon espace prestataire'),
    ),
  ];

  List<Widget> _suspended(ThemeData theme) => <Widget>[
    Text(
      'Votre compte prestataire est suspendu. Aucune action de gestion n’est '
      'possible : contactez le support.',
      style: theme.textTheme.bodyMedium,
      textAlign: TextAlign.center,
    ),
    const SizedBox(height: 16),
    const _SupportTile(),
  ];
}

class _SupportTile extends StatelessWidget {
  const _SupportTile();

  @override
  Widget build(BuildContext context) => const Card(
    child: ListTile(
      leading: Icon(Icons.support_agent_outlined),
      title: Text('Contacter le support'),
      subtitle: Text(kSupportContact),
    ),
  );
}
