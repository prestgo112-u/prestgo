// Avis — opérations 45 à 47 (T223 ; FR-070 à FR-073).
//
// Décisions structurantes :
//
//   • **le 409 du dépôt n'est pas une erreur** (opération 45) : « déjà noté »
//     signifie que l'objectif est atteint — le dépôt rend `null` et l'écran
//     enchaîne exactement comme après un 201, sans message d'échec ;
//   • **le doublon de signalement non plus** (opération 47) : le second envoi
//     devient la mention « déjà signalé » (scénario 9.4) ;
//   • les gardes locales (note entière 1 à 5, commentaire ≤ 1000, motif 3 à
//     500) refusent AVANT tout appel réseau — le service reste l'autorité.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/reviews/domain/review.dart';

/// Issue d'un signalement : transmis, ou déjà fait — jamais une erreur brute.
enum ReportOutcome { reported, alreadyReported }

class ReportResult {
  const ReportResult({required this.outcome, required this.message});

  final ReportOutcome outcome;

  /// Message serveur, affiché tel quel.
  final String message;

  bool get alreadyReported => outcome == ReportOutcome.alreadyReported;
}

class ReviewRepository {
  const ReviewRepository(this._client);

  final ApiClient _client;

  /// `POST /missions/{id}/review` — opération 45, **client seul**.
  ///
  /// Rend l'avis créé, ou `null` si un avis existait déjà (409 = succès
  /// fonctionnel). Les autres refus — fenêtre écoulée, mission non terminée,
  /// rôle — remontent en [ApiException] avec le message du service.
  Future<Review?> submitReview(
    String missionId, {
    required int rating,
    String? comment,
  }) async {
    if (rating < 1 || rating > 5) {
      throw ArgumentError.value(rating, 'rating', 'Note entière de 1 à 5');
    }
    final String? trimmed = _nonEmpty(comment);
    if (trimmed != null &&
        trimmed.length > ContentLimits.reviewCommentMaxLength) {
      throw ArgumentError.value(
        comment,
        'comment',
        'Au plus ${ContentLimits.reviewCommentMaxLength} caractères',
      );
    }

    try {
      final ApiEnvelope<Review> envelope = await _client.post<Review>(
        '/missions/$missionId/review',
        body: <String, Object?>{'rating': rating, 'comment': ?trimmed},
        parse: parseObject<Review>(Review.fromJson),
      );
      return envelope.requireData;
    } on ApiException catch (error) {
      if (error.isConflict) {
        return null;
      }
      rethrow;
    }
  }

  /// `GET /me/reviews` — opération 46, paginé.
  Future<PagedPage<Review>> myReviews({
    required int page,
    required int limit,
  }) async {
    final ApiEnvelope<List<Review>> envelope = await _client.get<List<Review>>(
      '/me/reviews',
      query: <String, Object?>{'page': page, 'limit': limit},
      parse: parseList<Review>(Review.fromJson),
    );
    return PagedPage<Review>(
      items: envelope.data ?? const <Review>[],
      meta: envelope.meta,
    );
  }

  /// `POST /reviews/{id}/report` — opération 47, au plus 20 par jour.
  ///
  /// Le 409 « déjà signalé » est rendu comme une issue, pas levé : l'écran
  /// affiche la mention (9.4). Le 403 « votre propre avis » et le 429 de la
  /// limite quotidienne remontent avec le message du service.
  Future<ReportResult> reportReview(
    String reviewId, {
    required String reason,
  }) async {
    // Mêmes bornes que tous les motifs du contrat : 3 à 500 caractères.
    final String trimmed = reason.trim();
    if (trimmed.length < ContentLimits.reasonMinLength ||
        trimmed.length > ContentLimits.reasonMaxLength) {
      throw ArgumentError.value(
        reason,
        'reason',
        'Motif de ${ContentLimits.reasonMinLength} à '
            '${ContentLimits.reasonMaxLength} caractères',
      );
    }

    try {
      final ApiEnvelope<void> envelope = await _client.post<void>(
        '/reviews/$reviewId/report',
        body: <String, Object?>{'reason': trimmed},
        parse: parseNothing(),
      );
      return ReportResult(
        outcome: ReportOutcome.reported,
        message: envelope.message ?? 'Signalement transmis',
      );
    } on ApiException catch (error) {
      if (error.isConflict) {
        return ReportResult(
          outcome: ReportOutcome.alreadyReported,
          message: error.message,
        );
      }
      rethrow;
    }
  }
}

String? _nonEmpty(String? value) {
  final String? trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

final Provider<ReviewRepository> reviewRepositoryProvider =
    Provider<ReviewRepository>(
      (Ref ref) => ReviewRepository(ref.watch(apiClientProvider)),
    );
