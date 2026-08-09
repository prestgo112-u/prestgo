// Dépôt d'avis (T224, FR-070, FR-071 ; scénarios 9.1 et 9.3).
//
// Le temps restant s'affiche dans l'écran même : la fenêtre est courte et le
// client doit savoir qu'elle se ferme. Le « 409 déjà noté » est un succès —
// le dépôt enchaîne exactement comme après un 201 (le dépôt de données rend
// alors `null`).
//
// Après le dépôt, le détail de la mission et « Mes avis » sont invalidés :
// l'action disparaît du détail (9.3) et l'avis apparaît dans la liste.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/missions/presentation/mission_providers.dart';
import 'package:prestgo_mobile/features/reviews/data/review_repository.dart';
import 'package:prestgo_mobile/features/reviews/domain/review.dart';
import 'package:prestgo_mobile/features/reviews/domain/review_eligibility.dart';
import 'package:prestgo_mobile/features/reviews/presentation/my_reviews_screen.dart';

class SubmitReviewScreen extends ConsumerStatefulWidget {
  const SubmitReviewScreen({
    required this.missionId,
    this.remaining,
    super.key,
  });

  final String missionId;

  /// Temps restant de la fenêtre, quand l'historique a permis de le dater.
  final Duration? remaining;

  @override
  ConsumerState<SubmitReviewScreen> createState() => _SubmitReviewScreenState();
}

class _SubmitReviewScreenState extends ConsumerState<SubmitReviewScreen>
    with FormSubmissionMixin<SubmitReviewScreen> {
  int _rating = 0;
  final TextEditingController _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      showFormError('Choisissez une note de 1 à 5 étoiles.');
      return;
    }

    // `null` = avis déjà existant (409) : même chemin que le succès.
    final Object? outcome = await submit<Object?>(() async {
      final Review? created = await ref
          .read(reviewRepositoryProvider)
          .submitReview(
            widget.missionId,
            rating: _rating,
            comment: _comment.text,
          );
      return created ?? 'already';
    });
    if (outcome == null || !mounted) {
      return;
    }

    // L'action se retire du détail (9.3), l'avis rejoint « Mes avis ».
    ref
      ..invalidate(missionDetailProvider(widget.missionId))
      ..invalidate(myReviewsProvider);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome == 'already'
              ? 'Votre avis avait déjà été pris en compte.'
              : 'Merci pour votre avis !',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Duration? remaining = widget.remaining;

    return Scaffold(
      appBar: AppBar(title: const Text('Laisser un avis')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (remaining != null) ...<Widget>[
            Text(
              remainingWindowLabel(remaining),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text('Votre note', style: theme.textTheme.titleSmall),
          Row(
            children: <Widget>[
              for (int star = 1; star <= 5; star++)
                IconButton(
                  tooltip: '$star étoile${star > 1 ? 's' : ''}',
                  onPressed: isSubmitting
                      ? null
                      : () => setState(() {
                          showFormError(null);
                          _rating = star;
                        }),
                  icon: Icon(
                    star <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 32,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _comment,
            maxLength: ContentLimits.reviewCommentMaxLength,
            maxLines: 5,
            enabled: !isSubmitting,
            decoration: const InputDecoration(
              labelText: 'Commentaire (facultatif)',
              border: OutlineInputBorder(),
            ),
          ),
          if (formError case final String message) ...<Widget>[
            Text(message, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
          ],
          FilledButton(
            onPressed: isSubmitting ? null : _submit,
            child: isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Publier mon avis'),
          ),
        ],
      ),
    );
  }
}
