// Signalement d'un avis (T226, FR-073 ; scénario 9.4).
//
// Trois règles :
//   • **masquée sur ses propres avis** — « Mes avis » ne rend jamais cette
//     action, et tout appelant qui sait que l'avis est le sien passe
//     `isOwn: true` ; le 403 du service reste le filet ;
//   • **« déjà signalé » est une mention, pas une erreur** : le premier
//     signalement comme le doublon (409) inscrivent l'avis dans un état de
//     session — l'action devient la mention et n'est plus proposée ;
//   • le motif (3 à 500 caractères) est contrôlé localement avant l'envoi.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/reviews/data/review_repository.dart';

/// Avis signalés pendant cette session — la mention survit à la navigation.
class ReportedReviewIds extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void add(String reviewId) => state = <String>{...state, reviewId};
}

final NotifierProvider<ReportedReviewIds, Set<String>>
reportedReviewIdsProvider = NotifierProvider<ReportedReviewIds, Set<String>>(
  ReportedReviewIds.new,
);

class ReportReviewAction extends ConsumerWidget {
  const ReportReviewAction({
    required this.reviewId,
    this.isOwn = false,
    super.key,
  });

  final String reviewId;

  /// Vrai quand l'appelant sait que l'avis est celui du lecteur : l'action
  /// n'est alors jamais rendue.
  final bool isOwn;

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => const _ReportReasonDialog(),
    );
    if (reason == null || !context.mounted) {
      return;
    }

    try {
      final ReportResult result = await ref
          .read(reviewRepositoryProvider)
          .reportReview(reviewId, reason: reason);
      // Transmis OU déjà fait : dans les deux cas, l'action devient mention.
      ref.read(reportedReviewIdsProvider.notifier).add(reviewId);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      }
    } on ApiException catch (failure) {
      // Son propre avis (403), limite quotidienne (429), session absente :
      // le message du service, tel quel.
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (isOwn) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final bool alreadyReported = ref
        .watch(reportedReviewIdsProvider)
        .contains(reviewId);

    if (alreadyReported) {
      return Text(
        'Déjà signalé',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return TextButton(
      onPressed: () => _report(context, ref),
      child: Text('Signaler', style: theme.textTheme.bodySmall),
    );
  }
}

class _ReportReasonDialog extends StatefulWidget {
  const _ReportReasonDialog();

  @override
  State<_ReportReasonDialog> createState() => _ReportReasonDialogState();
}

class _ReportReasonDialogState extends State<_ReportReasonDialog> {
  final TextEditingController _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final String reason = _reason.text.trim();
    if (reason.length < ContentLimits.reasonMinLength) {
      setState(
        () => _error =
            'Indiquez un motif d’au moins '
            '${ContentLimits.reasonMinLength} caractères.',
      );
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Signaler cet avis'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _reason,
            maxLength: ContentLimits.reasonMaxLength,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Motif (obligatoire)',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onChanged: (String _) => setState(() => _error = null),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Signaler')),
      ],
    );
  }
}
