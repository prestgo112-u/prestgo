// Mission telle que `POST /missions` la renvoie.
//
// Volontairement réduit à ce que la confirmation affiche : identifiant, statut,
// horaire, montant **figé** par le service, et de quoi rappeler ce qui a été
// réservé. Le modèle complet de mission — frise, annulations, reports, avis —
// appartient au suivi (US3) et n'a pas sa place ici.
//
// Le montant renvoyé est celui qui fait foi : le prix calculé à l'écran doit lui
// être identique (scénario 2.5). S'il diffère, c'est le service qui a raison.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

class BookedMission {
  const BookedMission({
    required this.id,
    required this.status,
    required this.quotedAmount,
    this.scheduledAt,
    this.providerName,
    this.packTitle,
    this.addressLabel,
    this.threadId,
  });

  factory BookedMission.fromJson(JsonMap json) {
    final Object? provider = json['provider'];
    final Object? pack = json['pack'];
    final Object? address = json['address'];
    final Object? thread = json['thread'];

    return BookedMission(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      quotedAmount: switch (json['quotedAmount']) {
        final int v => v,
        final num v => v.toInt(),
        _ => 0,
      },
      scheduledAt: MissionDates.fromApiOrNull(json['scheduledAt'] as String?),
      providerName: provider is Map<Object?, Object?>
          ? provider['publicName'] as String?
          : null,
      packTitle: pack is Map<Object?, Object?>
          ? pack['title'] as String?
          : null,
      addressLabel: address is Map<Object?, Object?>
          ? address['label'] as String?
          : null,
      threadId: thread is Map<Object?, Object?>
          ? thread['id'] as String?
          : null,
    );
  }

  final String id;

  /// `pending_provider` à la création : le prestataire doit encore accepter.
  final String status;

  /// Montant figé par le service — celui qui sera facturé.
  final int quotedAmount;

  final DateTime? scheduledAt;
  final String? providerName;
  final String? packTitle;
  final String? addressLabel;

  /// Le fil de discussion existe dès la demande : le prestataire peut poser une
  /// question avant d'accepter.
  final String? threadId;

  bool get isPendingProvider => status == 'pending_provider';

  @override
  bool operator ==(Object other) => other is BookedMission && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'BookedMission($id, $status)';
}
