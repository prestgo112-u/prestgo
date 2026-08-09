// Transitions de mission côté prestataire — opérations 36 à 40 (T166, T174).
//
// Cinq actions, une réponse commune, et une règle absolue (porte G4, FR-046) :
// une transition n'est **jamais** rejouée automatiquement. Un rejeu après un
// succès dont la réponse s'est perdue répondrait « Action impossible depuis le
// statut … » — incompréhensible pour l'utilisateur. La conduite est donc :
//
//   • réponse jamais reçue ([outcomeUnknown]) → l'issue est **inconnue** : le
//     cache est purgé ici même, l'écran recharge l'état réel et laisse
//     l'utilisateur décider (scénario 5.5) ;
//   • « Action impossible depuis le statut … », « Transition de mission
//     invalide », « pas encore acceptée : utilisez le refus »
//     ([stateChanged]) → la réalité a changé entre l'affichage et l'envoi :
//     rechargement, le message du service affiché tel quel ;
//   • tout autre échec (403 « pas le prestataire », 400 fenêtre de démarrage…)
//     → le message du service est l'affichage, rien d'autre à faire.
//
// Le service vérifie D'ABORD l'appartenance (403), PUIS le statut exact (400).
// La machine à états reste chez lui (porte G1) : ce fichier ne décide jamais
// qu'une transition est possible, il transporte la réponse.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/cache/cache_dao.dart';
import 'package:prestgo_mobile/core/cache/cache_providers.dart';
import 'package:prestgo_mobile/features/missions/domain/mission_status.dart';

/// `MissionTransitionResultDto` — la réponse commune aux cinq actions.
class MissionTransitionResult {
  const MissionTransitionResult({
    required this.missionId,
    required this.previousStatus,
    required this.status,
    required this.late,
    required this.message,
  });

  factory MissionTransitionResult.fromJson(
    JsonMap json, {
    required String message,
  }) => MissionTransitionResult(
    missionId: json['missionId'] as String? ?? '',
    previousStatus: MissionStatus.parse(json['previousStatus'] as String?),
    status: MissionStatus.parse(json['status'] as String?),
    late: json['late'] as bool? ?? false,
    message: message,
  );

  final String missionId;
  final MissionStatus previousStatus;
  final MissionStatus status;

  /// Verdict de tardiveté du service — affiché tel quel, jamais recalculé.
  final bool late;

  /// Message de l'enveloppe (« Mission acceptée »…) — l'affichage du succès.
  final String message;
}

class MissionTransitionController {
  const MissionTransitionController(this._client, this._cache);

  final ApiClient _client;
  final CacheDao _cache;

  /// `POST /missions/{id}/accept` — `pending_provider` → `confirmed`, sans corps.
  Future<MissionTransitionResult> accept(String missionId) =>
      _transition(missionId, 'accept');

  /// `POST /missions/{id}/refuse` — `pending_provider` → `cancelled`.
  ///
  /// Refus **avant** acceptation — jamais interchangeable avec [cancel].
  Future<MissionTransitionResult> refuse(
    String missionId, {
    required String reason,
  }) => _transition(
    missionId,
    'refuse',
    body: <String, Object?>{'reason': reason},
  );

  /// `POST /missions/{id}/start` — `confirmed` → `in_progress`, sans corps.
  ///
  /// Le service refuse hors fenêtre avec un message interpolé de la valeur en
  /// vigueur — il prime sur l'estimation locale (FR-042).
  Future<MissionTransitionResult> start(String missionId) =>
      _transition(missionId, 'start');

  /// `POST /missions/{id}/complete` — `in_progress` → `completed`, sans corps.
  Future<MissionTransitionResult> complete(String missionId) =>
      _transition(missionId, 'complete');

  /// `POST /missions/{id}/cancel` — `confirmed` → `cancelled`, motif exigé.
  ///
  /// Annulation **après** acceptation ; le verdict de tardiveté est celui du
  /// service (FR-045).
  Future<MissionTransitionResult> cancel(
    String missionId, {
    required String reason,
    String? details,
  }) => _transition(
    missionId,
    'cancel',
    body: <String, Object?>{'reason': reason, 'details': ?details},
  );

  /// Vrai si la réponse n'est jamais parvenue : l'issue est **inconnue**.
  ///
  /// L'écran recharge l'état réel et laisse l'utilisateur décider — jamais de
  /// rejeu (FR-046).
  static bool outcomeUnknown(ApiException error) => error.isNetwork;

  /// Vrai si le statut a changé entre l'affichage et l'envoi : recharger.
  static bool stateChanged(ApiException error) =>
      error.message.startsWith('Action impossible depuis le statut') ||
      error.message.startsWith('Transition de mission invalide') ||
      error.message.startsWith("Cette mission n'est pas encore acceptée");

  Future<MissionTransitionResult> _transition(
    String missionId,
    String action, {
    Map<String, Object?>? body,
  }) async {
    final ApiEnvelope<JsonMap> envelope;
    try {
      envelope = await _client.post<JsonMap>(
        '/missions/$missionId/$action',
        body: body,
        parse: parseObject<JsonMap>((JsonMap json) => json),
      );
    } on ApiException catch (error) {
      if (outcomeUnknown(error)) {
        // L'appel est peut-être passé : ce que le cache porte est peut-être
        // faux. Purger ici garantit que la relecture partira du service.
        await _invalidate(missionId);
      }
      rethrow;
    }
    // Le statut vient de changer : détail et listes des DEUX rôles sont à relire.
    await _invalidate(missionId);
    return MissionTransitionResult.fromJson(
      envelope.data ?? const <String, Object?>{},
      message: envelope.message ?? 'Mission mise à jour',
    );
  }

  Future<void> _invalidate(String missionId) async {
    await _cache.invalidateMissionDetail(missionId);
    await _cache.invalidateMissions();
  }
}

final Provider<MissionTransitionController>
missionTransitionControllerProvider = Provider<MissionTransitionController>(
  (Ref ref) => MissionTransitionController(
    ref.watch(apiClientProvider),
    ref.watch(cacheDaoProvider),
  ),
);
