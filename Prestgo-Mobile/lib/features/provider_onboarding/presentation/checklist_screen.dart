// P8 — Le **hub** de complétude (T151, FR-051, FR-060, FR-061).
//
// Le parcours n'est pas un tunnel : l'ordre P3 → P7 est libre côté service, et
// c'est cette liberté que le hub matérialise — cinq lignes alimentées par la
// checklist du service, chaque ligne rouge ouvrant l'étape correspondante. C'est
// aussi la présentation qui gère naturellement la reprise après
// `changes_requested`.
//
// Trois règles non négociables :
//   • les cinq états viennent du service, JAMAIS d'un recalcul local (porte G1) ;
//   • les libellés des lignes rouges reprennent les libellés **officiels** — ce
//     sont eux qui désamorcent les deux pièges du calcul (« nom public ET
//     présentation », « service AVEC formule active ») ;
//   • le bouton « Soumettre » est piloté par `canSubmit`, pas par la checklist.
//
// Après un refus de soumission, les lignes désignées par `errors[].field`
// passent en rouge — exactement celles-là (T157, scénario 4.7).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/auth/presentation/logout_action.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/availabilities_step_screen.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/documents_step_screen.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_overview_controller.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_profile_form_screen.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/service_step_screen.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/submit_controller.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/zones_step_screen.dart';

class ChecklistScreen extends ConsumerWidget {
  const ChecklistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ProviderProfile> overview = ref.watch(
      providerOverviewProvider,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mon dossier prestataire'),
        // Écran d'atterrissage d'un dossier incomplet — même impasse que le suivi
        // de dossier sans cette action.
        actions: const <Widget>[LogoutAction()],
      ),
      body: switch (overview) {
        AsyncValue<ProviderProfile>(:final ProviderProfile value) =>
          _ChecklistBody(profile: value),
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

class _ChecklistBody extends ConsumerWidget {
  const _ChecklistBody({required this.profile});

  final ProviderProfile profile;

  Future<void> _openStep(
    BuildContext context,
    WidgetRef ref,
    ChecklistStep step,
  ) async {
    // Rouvrir une étape efface son verdict de soumission : l'utilisateur est en
    // train de corriger, la ligne rouge a fait son office.
    ref.read(submitControllerProvider.notifier).clearStep(step);

    final Widget screen = switch (step) {
      ChecklistStep.profile => ProviderProfileFormScreen(existing: profile),
      ChecklistStep.services => const ServiceStepScreen(),
      ChecklistStep.zones => const ZonesStepScreen(),
      ChecklistStep.availabilities => const AvailabilitiesStepScreen(),
      ChecklistStep.documents => const DocumentsStepScreen(),
    };
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (BuildContext context) => screen));

    // La checklist dépend de ce qui vient d'être écrit (FR-050) : au retour,
    // elle est relue plutôt que devinée.
    await ref.read(providerOverviewProvider.notifier).reload();
  }

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final ProviderProfile? submitted = await ref
        .read(submitControllerProvider.notifier)
        .submit();
    if (submitted == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dossier soumis à la vérification')),
    );
    context.go(Routes.providerStatus);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SubmitState submitState = ref.watch(submitControllerProvider);
    final String? rejectionReason = profile.rejectionReason;

    return RefreshIndicator(
      onRefresh: () => ref.read(providerOverviewProvider.notifier).reload(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (rejectionReason != null) ...<Widget>[
            // En reprise après « corrections demandées », le motif reste sous
            // les yeux pendant toute la correction.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                rejectionReason,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Complétez les cinq étapes, dans l’ordre que vous voulez, puis '
            'soumettez votre dossier.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (final ChecklistStep step in ChecklistStep.values)
            _ChecklistTile(
              step: step,
              done: profile.checklist[step],
              submitMessage: submitState.failedSteps.contains(step)
                  ? (submitState.messageFor(step) ?? step.requirementLabel)
                  : null,
              onTap: () => _openStep(context, ref, step),
            ),
          const SizedBox(height: 16),
          if (submitState.banner case final String banner) ...<Widget>[
            Text(banner, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
          ],
          if (profile.resubmissionBlocked || submitState.blocked)
            Text(
              'La re-soumission de votre dossier a été bloquée. Contactez le '
              'support.',
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            )
          else
            FilledButton(
              // `canSubmit` décide — la checklist n'est qu'un affichage. Le
              // bouton reste visible mais inerte tant que le service dit non :
              // un bouton qui disparaît sans explication serait illisible.
              onPressed: profile.canSubmit && !submitState.submitting
                  ? () => _submit(context, ref)
                  : null,
              child: submitState.submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Soumettre mon dossier'),
            ),
          if (!profile.canSubmit &&
              !profile.resubmissionBlocked &&
              !submitState.blocked) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Le bouton s’activera quand toutes les étapes seront complètes.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({
    required this.step,
    required this.done,
    required this.onTap,
    this.submitMessage,
  });

  final ChecklistStep step;
  final bool done;
  final VoidCallback onTap;

  /// Libellé du refus de soumission — la ligne a été désignée par le service.
  final String? submitMessage;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? submitMessage = this.submitMessage;
    final bool flagged = submitMessage != null;
    final bool incomplete = !done || flagged;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: flagged
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.error),
            )
          : null,
      child: ListTile(
        leading: Icon(
          done && !flagged ? Icons.check_circle : Icons.radio_button_unchecked,
          color: done && !flagged
              ? Colors.green.shade700
              : theme.colorScheme.error,
        ),
        title: Text(step.title),
        // Le libellé officiel sous chaque ligne incomplète : c'est lui qui dit
        // « nom public ET présentation », « service AVEC formule active ».
        subtitle: incomplete
            ? Text(
                submitMessage ?? step.requirementLabel,
                style: TextStyle(color: theme.colorScheme.error),
              )
            : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
