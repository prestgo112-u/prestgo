// Litiges — opérations 89 et 90 (T134, FR-100).
//
// Deux routes seulement, accessibles aux deux rôles sur **leur** mission :
// l'ouverture, et le suivi. L'ouverture est une écriture non idempotente — jamais
// rejouée (porte G4).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/features/disputes/domain/dispute.dart';

class DisputeRepository {
  const DisputeRepository(this._client);

  final ApiClient _client;

  /// `POST /disputes` — opération 89.
  Future<Dispute> open({
    required String missionId,
    required String reason,
  }) async {
    final ApiEnvelope<Dispute> envelope = await _client.post<Dispute>(
      '/disputes',
      body: <String, Object?>{'missionId': missionId, 'reason': reason},
      parse: parseObject<Dispute>(Dispute.fromJson),
    );
    // Une réponse sans contenu reste un litige ouvert : l'écran de suivi
    // retombe sur ce qu'il connaît déjà.
    return envelope.data ??
        Dispute(
          id: '',
          missionId: missionId,
          reason: reason,
          status: 'open',
          messages: const <DisputeMessage>[],
        );
  }

  /// `GET /disputes/{id}` — opération 90. Les commentaires internes des agents ne
  /// sont jamais renvoyés.
  Future<Dispute> detail(String disputeId) async {
    final ApiEnvelope<Dispute> envelope = await _client.get<Dispute>(
      '/disputes/$disputeId',
      parse: parseObject<Dispute>(Dispute.fromJson),
    );
    return envelope.requireData;
  }
}

final Provider<DisputeRepository> disputeRepositoryProvider =
    Provider<DisputeRepository>(
      (Ref ref) => DisputeRepository(ref.watch(apiClientProvider)),
    );
