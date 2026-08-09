// T047 — Cycle de vie de la clé d'idempotence.
//
// Voir contracts/retry-and-idempotency.md §2. La règle à protéger : **stable sur
// contenu identique, renouvelée dès que le contenu change**. C'est elle qui empêche
// une seconde réservation après une coupure réseau (scénario 2.9), et qui garantit
// qu'une modification d'option repart sur une clé neuve (scénario 2.10).

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/idempotency.dart';

String fingerprint({
  String packId = 'pack-1',
  List<String> optionIds = const <String>['opt-a'],
  String addressId = 'addr-1',
  String? instructions,
  DateTime? scheduledAt,
}) => bookingFingerprint(
  providerId: 'prov-1',
  packId: packId,
  optionIds: optionIds,
  scheduledAt: scheduledAt ?? DateTime.utc(2026, 8, 12, 9),
  addressId: addressId,
  instructions: instructions,
);

void main() {
  group('Stabilité sur contenu identique', () {
    test('deux appels successifs renvoient la même clé', () {
      final IdempotencyKeyHolder holder = IdempotencyKeyHolder();
      final String content = fingerprint();

      final IdempotencyKey first = holder.keyFor(content);
      final IdempotencyKey second = holder.keyFor(content);

      expect(second.value, first.value);
    });

    test(
      'un rejeu après coupure réseau réutilise la clé — une seule mission créée',
      () {
        final IdempotencyKeyHolder holder = IdempotencyKeyHolder();
        final String content = fingerprint();

        final String attempt1 = holder.keyFor(content).value;
        // Coupure réseau, l'utilisateur laisse réessayer : même contenu.
        final String attempt2 = holder.keyFor(content).value;
        final String attempt3 = holder.keyFor(content).value;

        expect(<String>{attempt1, attempt2, attempt3}, hasLength(1));
      },
    );

    test('l’ordre de sélection des options ne change pas l’empreinte', () {
      expect(
        fingerprint(optionIds: <String>['opt-a', 'opt-b']),
        fingerprint(optionIds: <String>['opt-b', 'opt-a']),
      );
    });

    test('une option cochée deux fois ne change pas l’empreinte', () {
      expect(
        fingerprint(optionIds: <String>['opt-a', 'opt-a']),
        fingerprint(optionIds: <String>['opt-a']),
      );
    });
  });

  group('Renouvellement sur changement de contenu', () {
    test('changer de formule émet une clé neuve', () {
      final IdempotencyKeyHolder holder = IdempotencyKeyHolder();
      final String before = holder.keyFor(fingerprint()).value;
      final String after = holder.keyFor(fingerprint(packId: 'pack-2')).value;
      expect(after, isNot(before));
    });

    test('cocher une option émet une clé neuve (scénario 2.10)', () {
      final IdempotencyKeyHolder holder = IdempotencyKeyHolder();
      final String before = holder.keyFor(fingerprint()).value;
      final String after = holder
          .keyFor(fingerprint(optionIds: <String>['opt-a', 'opt-b']))
          .value;
      expect(after, isNot(before));
    });

    test('changer de date, d’adresse ou d’instructions émet une clé neuve', () {
      final IdempotencyKeyHolder holder = IdempotencyKeyHolder();
      final String base = holder.keyFor(fingerprint()).value;

      expect(
        holder
            .keyFor(fingerprint(scheduledAt: DateTime.utc(2026, 8, 13)))
            .value,
        isNot(base),
      );
      expect(
        holder.keyFor(fingerprint(addressId: 'addr-2')).value,
        isNot(base),
      );
      expect(
        holder.keyFor(fingerprint(instructions: 'Sonner au portail')).value,
        isNot(base),
      );
    });

    test('`reset` fait repartir sur une clé neuve pour le même contenu', () {
      final IdempotencyKeyHolder holder = IdempotencyKeyHolder();
      final String content = fingerprint();
      final String before = holder.keyFor(content).value;

      holder.reset();
      expect(holder.current, isNull);

      expect(holder.keyFor(content).value, isNot(before));
    });
  });

  group('Durée de vie', () {
    test('une clé expirée est remplacée, même à contenu identique', () {
      DateTime now = DateTime.utc(2026, 8, 12, 10);
      final IdempotencyKeyHolder holder = IdempotencyKeyHolder(
        clock: () => now,
      );
      final String content = fingerprint();

      final String before = holder.keyFor(content).value;

      // Au-delà des 10 minutes du service, la clé ne protège plus rien.
      now = now.add(const Duration(minutes: 11));
      expect(holder.keyFor(content).value, isNot(before));
    });

    test('une clé encore valide est conservée', () {
      DateTime now = DateTime.utc(2026, 8, 12, 10);
      final IdempotencyKeyHolder holder = IdempotencyKeyHolder(
        clock: () => now,
      );
      final String content = fingerprint();

      final String before = holder.keyFor(content).value;
      now = now.add(const Duration(minutes: 9));
      expect(holder.keyFor(content).value, before);
    });
  });

  test('l’empreinte normalise la date en UTC', () {
    final DateTime utc = DateTime.utc(2026, 8, 12, 9);
    expect(
      fingerprint(scheduledAt: utc),
      fingerprint(scheduledAt: utc.toLocal()),
    );
  });
}
