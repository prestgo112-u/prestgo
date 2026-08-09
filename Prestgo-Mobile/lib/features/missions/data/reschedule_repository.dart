// Reports — opérations 41 à 44 (T126, FR-047, FR-048).
//
// Trois règles du service donnent leur forme à ces méthodes :
//
//   • **une seule demande en attente par mission** — le 400 « déjà en attente »
//     existe, mais l'écran grise l'action avant de l'atteindre ;
//   • le créneau est **revalidé au moment de l'acceptation** : le 400 « n'est plus
//     disponible » n'est pas une impasse, il ouvre une contre-proposition
//     (scénario 3.5) ;
//   • répondre à **sa propre** demande est un 403 — jamais atteint, puisque les
//     boutons sont masqués sur `createdBy == me.id` (scénario 3.4).
//
// Ces quatre routes sont des écritures non idempotentes : la politique de rejeu du
// socle ne les rejoue jamais (porte G4). `newDate` part en **UTC** (R11).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/features/missions/domain/reschedule_request.dart';

/// Demande envoyée, accompagnée du message serveur à afficher tel quel.
class RescheduleSubmission {
  const RescheduleSubmission({required this.request, required this.message});

  final RescheduleRequest request;
  final String message;
}

class RescheduleRepository {
  const RescheduleRepository(this._client);

  final ApiClient _client;

  /// `GET /missions/{id}/reschedules` — opération 41, historique **complet**.
  ///
  /// Contrairement à `mission.reschedules` (détail), qui ne porte que les demandes
  /// en attente, cette liste contient tous les statuts.
  Future<List<RescheduleRequest>> history(String missionId) async {
    final ApiEnvelope<List<RescheduleRequest>> envelope = await _client
        .get<List<RescheduleRequest>>(
          '/missions/$missionId/reschedules',
          parse: parseList<RescheduleRequest>(RescheduleRequest.fromJson),
        );
    return envelope.data ?? const <RescheduleRequest>[];
  }

  /// `POST /missions/{id}/reschedule` — opération 42.
  ///
  /// Le message du service (« Demande de report envoyée… ») accompagne la
  /// demande : c'est lui qui est affiché, jamais une reformulation locale.
  Future<RescheduleSubmission> propose(
    String missionId, {
    required DateTime newDate,
    String? reason,
  }) async {
    final ApiEnvelope<RescheduleRequest> envelope = await _client
        .post<RescheduleRequest>(
          '/missions/$missionId/reschedule',
          body: <String, Object?>{
            'newDate': MissionDates.toApi(newDate),
            'reason': ?reason,
          },
          parse: parseObject<RescheduleRequest>(RescheduleRequest.fromJson),
        );
    return RescheduleSubmission(
      request: envelope.requireData,
      message:
          envelope.message ??
          'Demande de report envoyée. Elle doit être acceptée par l’autre '
              'partie.',
    );
  }

  /// `POST /missions/{id}/reschedule/{rid}/accept` — opération 43, sans corps.
  ///
  /// Sur succès, **la mission est déplacée** : `scheduledAt` de la réponse est la
  /// nouvelle date. Le 400 « n'est plus disponible » remonte tel quel — l'écran
  /// propose alors une contre-proposition.
  Future<RescheduleDecision> accept(
    String missionId,
    String rescheduleId,
  ) async {
    final ApiEnvelope<JsonMap> envelope = await _client.post<JsonMap>(
      '/missions/$missionId/reschedule/$rescheduleId/accept',
      parse: parseObject<JsonMap>((JsonMap json) => json),
    );
    return RescheduleDecision.fromJson(
      envelope.data ?? const <String, Object?>{},
      message: envelope.message ?? 'Report accepté.',
    );
  }

  /// `POST /missions/{id}/reschedule/{rid}/reject` — opération 44, motif 3 à 500.
  ///
  /// La date d'origine tient.
  Future<RescheduleDecision> reject(
    String missionId,
    String rescheduleId, {
    required String reason,
  }) async {
    final ApiEnvelope<JsonMap> envelope = await _client.post<JsonMap>(
      '/missions/$missionId/reschedule/$rescheduleId/reject',
      body: <String, Object?>{'reason': reason},
      parse: parseObject<JsonMap>((JsonMap json) => json),
    );
    return RescheduleDecision.fromJson(
      envelope.data ?? const <String, Object?>{},
      message: envelope.message ?? 'Report refusé.',
    );
  }
}

final Provider<RescheduleRepository> rescheduleRepositoryProvider =
    Provider<RescheduleRepository>(
      (Ref ref) => RescheduleRepository(ref.watch(apiClientProvider)),
    );
