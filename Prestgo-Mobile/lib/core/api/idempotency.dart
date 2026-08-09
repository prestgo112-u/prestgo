// Génération et cycle de vie de la clé d'idempotence.
//
// Voir contracts/retry-and-idempotency.md §2. La règle tient en une phrase :
//
//   > la clé est générée **une seule fois**, à l'affichage du récapitulatif, et
//   > réutilisée à chaque tentative sur le **même contenu** — y compris après une
//   > coupure réseau. Elle n'est renouvelée que si le contenu change.
//
// ⚠️ Ne jamais appeler [IdempotencyKeyHolder.keyFor] depuis une méthode de
// construction de widget : chaque reconstruction produirait une clé neuve et
// annulerait la protection (piège n°5 de §6 de quickstart.md).

import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:uuid/uuid.dart';

/// Nom de l'en-tête attendu par le service.
const String kIdempotencyKeyHeader = 'Idempotency-Key';

/// Clé émise, avec l'empreinte du contenu qui l'a justifiée.
class IdempotencyKey {
  const IdempotencyKey({
    required this.value,
    required this.fingerprint,
    required this.issuedAt,
  });

  /// UUID v4 transmis dans l'en-tête.
  final String value;

  /// Empreinte du contenu de la réservation au moment de l'émission.
  final String fingerprint;

  final DateTime issuedAt;

  /// Vrai au-delà de la durée de vie côté service : au-delà, la clé ne protège
  /// plus rien et il vaut mieux en émettre une neuve.
  bool isExpiredAt(DateTime now) =>
      now.difference(issuedAt) >= RateLimits.idempotencyKeyLifetime;

  @override
  bool operator ==(Object other) =>
      other is IdempotencyKey &&
      other.value == value &&
      other.fingerprint == fingerprint &&
      other.issuedAt == issuedAt;

  @override
  int get hashCode => Object.hash(value, fingerprint, issuedAt);

  @override
  String toString() => 'IdempotencyKey($value, empreinte: $fingerprint)';
}

/// Porte la clé courante et décide quand la renouveler.
///
/// Une instance vit dans l'état de l'écran de récapitulatif (T110), pas dans un
/// widget : sa durée de vie est celle du brouillon de réservation.
class IdempotencyKeyHolder {
  IdempotencyKeyHolder({Uuid? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? const Uuid(),
      _clock = clock ?? DateTime.now;

  final Uuid _uuid;
  final DateTime Function() _clock;

  IdempotencyKey? _current;

  /// Clé actuellement émise, sans en créer de nouvelle.
  IdempotencyKey? get current => _current;

  /// Clé associée à [fingerprint].
  ///
  /// Renvoie la clé existante si l'empreinte est inchangée et la clé encore
  /// valide ; en émet une neuve sinon. Deux appels successifs sur le même contenu
  /// renvoient donc exactement la même valeur — c'est ce qui garantit qu'un rejeu
  /// après coupure réseau ne crée pas de seconde réservation.
  IdempotencyKey keyFor(String fingerprint) {
    final DateTime now = _clock();
    final IdempotencyKey? existing = _current;

    if (existing != null &&
        existing.fingerprint == fingerprint &&
        !existing.isExpiredAt(now)) {
      return existing;
    }

    final IdempotencyKey issued = IdempotencyKey(
      value: _uuid.v4(),
      fingerprint: fingerprint,
      issuedAt: now,
    );
    _current = issued;
    return issued;
  }

  /// Abandonne la clé courante.
  ///
  /// Appelé après un succès, ou quand l'utilisateur repart d'un nouveau brouillon.
  /// Une erreur **métier** libère la clé côté service : l'utilisateur corrige et
  /// repart avec une clé neuve, puisque le contenu a changé.
  void reset() => _current = null;
}

/// Construit l'empreinte du contenu d'une réservation.
///
/// Deux compositions identiques produisent la même empreinte, quel que soit l'ordre
/// dans lequel les options ont été cochées ; toute modification de formule,
/// d'options, de date, d'adresse ou d'instructions en produit une différente et
/// déclenche donc l'émission d'une nouvelle clé.
String bookingFingerprint({
  required String providerId,
  required String packId,
  required Iterable<String> optionIds,
  required DateTime scheduledAt,
  required String addressId,
  String? instructions,
}) {
  final List<String> sortedOptions = optionIds.toSet().toList()..sort();
  return <String>[
    providerId,
    packId,
    sortedOptions.join(','),
    scheduledAt.toUtc().toIso8601String(),
    addressId,
    instructions ?? '',
  ].join('|');
}
