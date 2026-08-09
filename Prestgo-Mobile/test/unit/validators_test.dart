// T048 — Validateurs de saisie.
//
// Chaque borne vient de `app_constants.dart` (contracts/settings-and-limits.md §2).
// Ces contrôles sont du confort de saisie : en cas de désaccord, le message du
// service prime (porte G1).

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/validation/validators.dart';

void main() {
  group('Mot de passe — 8 à 128, au moins une lettre et un chiffre', () {
    test('accepte un mot de passe conforme', () {
      expect(Validators.password('prestgo123!'), isNull);
      expect(Validators.password('Abcdefg1'), isNull);
    });

    test('refuse trop court', () {
      expect(Validators.password('Ab1'), isNotNull);
      expect(Validators.password('a' * 7 + '1'), isNull);
    });

    test('refuse au-delà de 128 caractères', () {
      expect(
        Validators.password('a1${'x' * AuthLimits.passwordMaxLength}'),
        isNotNull,
      );
    });

    test('refuse sans chiffre ou sans lettre', () {
      expect(Validators.password('motdepasse'), isNotNull);
      expect(Validators.password('12345678'), isNotNull);
    });

    test('confirmation — contrôle purement local', () {
      expect(Validators.passwordConfirmation('abc123ab', 'abc123ab'), isNull);
      expect(Validators.passwordConfirmation('abc123ab', 'autre'), isNotNull);
      expect(Validators.passwordConfirmation('', 'abc123ab'), isNotNull);
    });
  });

  group('Téléphone', () {
    test('accepte les formes tolérées par le service', () {
      expect(Validators.phone('+2250700000000'), isNull);
      expect(Validators.phone('07 00 00 00 00'), isNull);
      expect(Validators.phone('07-00-00-00'), isNull);
    });

    test('refuse trop court ou avec des lettres', () {
      expect(Validators.phone('0700'), isNotNull);
      expect(Validators.phone('07000000AB'), isNotNull);
    });

    test('facultatif quand il n’est pas requis', () {
      expect(Validators.phone('', required: false), isNull);
      expect(Validators.phone(null, required: false), isNull);
      expect(Validators.phone(null), isNotNull);
    });
  });

  group('Email', () {
    test('accepte une forme plausible', () {
      expect(Validators.email('client.demo@prestgo.test'), isNull);
    });

    test('refuse les formes manifestement invalides', () {
      expect(Validators.email('sans-arobase'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
      expect(Validators.email('a @b.test'), isNotNull);
    });
  });

  group('Code de vérification — exactement 6 chiffres', () {
    test('accepte 6 chiffres', () {
      expect(Validators.verificationCode('123456'), isNull);
    });

    test('refuse une autre longueur ou des caractères non numériques', () {
      expect(Validators.verificationCode('12345'), isNotNull);
      expect(Validators.verificationCode('1234567'), isNotNull);
      expect(Validators.verificationCode('12345a'), isNotNull);
    });
  });

  group('Jeton de réinitialisation', () {
    test('accepte un jeton long, refuse un fragment', () {
      expect(Validators.passwordResetToken('a' * 64), isNull);
      expect(Validators.passwordResetToken('abc'), isNotNull);
      expect(Validators.passwordResetToken('  '), isNotNull);
    });
  });

  group('Longueurs de contenu', () {
    test('motif — 3 à 500 caractères', () {
      expect(Validators.reason('ok'), isNotNull);
      expect(Validators.reason('oui'), isNull);
      expect(
        Validators.reason('x' * (ContentLimits.reasonMaxLength + 1)),
        isNotNull,
      );
    });

    test('instructions de réservation — facultatives, 500 au plus', () {
      expect(Validators.bookingInstructions(null), isNull);
      expect(Validators.bookingInstructions(''), isNull);
      expect(
        Validators.bookingInstructions(
          'x' * ContentLimits.bookingInstructionsMaxLength,
        ),
        isNull,
      );
      expect(
        Validators.bookingInstructions(
          'x' * (ContentLimits.bookingInstructionsMaxLength + 1),
        ),
        isNotNull,
      );
    });

    test('message — 1 à 4000 caractères', () {
      expect(Validators.messageBody(''), isNotNull);
      expect(Validators.messageBody('a'), isNull);
      expect(
        Validators.messageBody('x' * ContentLimits.messageMaxLength),
        isNull,
      );
      expect(
        Validators.messageBody('x' * (ContentLimits.messageMaxLength + 1)),
        isNotNull,
      );
    });

    test('commentaire d’avis — facultatif, 1000 au plus', () {
      expect(Validators.reviewComment(null), isNull);
      expect(
        Validators.reviewComment(
          'x' * (ContentLimits.reviewCommentMaxLength + 1),
        ),
        isNotNull,
      );
    });
  });

  group('Nombres', () {
    test('note d’avis — entier de 1 à 5', () {
      expect(Validators.rating(null), isNotNull);
      expect(Validators.rating(0), isNotNull);
      expect(Validators.rating(1), isNull);
      expect(Validators.rating(5), isNull);
      expect(Validators.rating(6), isNotNull);
    });

    test('prix — jamais négatif, virgule décimale acceptée', () {
      expect(Validators.price(0), isNull);
      expect(Validators.price(15000), isNull);
      expect(Validators.price('15000,50'), isNull);
      expect(Validators.price(-1), isNotNull);
      expect(Validators.price('abc'), isNotNull);
    });

    test('durée de formule — 5 à 1440 minutes', () {
      String? duration(Object? v) => Validators.integerInRange(
        v,
        label: 'La durée',
        min: ContentLimits.packDurationMinMinutes,
        max: ContentLimits.packDurationMaxMinutes,
      );
      expect(duration(4), isNotNull);
      expect(duration(5), isNull);
      expect(duration(1440), isNull);
      expect(duration(1441), isNotNull);
      expect(duration('90'), isNull);
    });

    test('années d’expérience — 0 à 70', () {
      String? years(Object? v) => Validators.integerInRange(
        v,
        label: 'L’expérience',
        min: ContentLimits.experienceYearsMin,
        max: ContentLimits.experienceYearsMax,
      );
      expect(years(0), isNull);
      expect(years(70), isNull);
      expect(years(71), isNotNull);
    });
  });

  group('Agenda — aucune conversion de fuseau', () {
    test('heure `HH:MM`', () {
      expect(Validators.clockTime('09:30'), isNull);
      expect(Validators.clockTime('00:00'), isNull);
      expect(Validators.clockTime('23:59'), isNull);
      expect(Validators.clockTime('24:00'), isNotNull);
      expect(Validators.clockTime('9:30'), isNotNull);
      expect(Validators.clockTime('09:60'), isNotNull);
    });

    test('créneau — fin strictement après le début', () {
      expect(
        Validators.weeklySlot(weekday: 0, startTime: '08:00', endTime: '12:00'),
        isNull,
      );
      expect(
        Validators.weeklySlot(weekday: 0, startTime: '12:00', endTime: '08:00'),
        isNotNull,
      );
      expect(
        Validators.weeklySlot(weekday: 0, startTime: '08:00', endTime: '08:00'),
        isNotNull,
      );
    });

    test('jour — 0 (dimanche) à 6 (samedi)', () {
      expect(
        Validators.weeklySlot(weekday: 6, startTime: '08:00', endTime: '09:00'),
        isNull,
      );
      expect(
        Validators.weeklySlot(weekday: 7, startTime: '08:00', endTime: '09:00'),
        isNotNull,
      );
      expect(
        Validators.weeklySlot(
          weekday: -1,
          startTime: '08:00',
          endTime: '09:00',
        ),
        isNotNull,
      );
    });

    test('absence — fin strictement après le début', () {
      expect(
        Validators.unavailability(
          startAt: DateTime.utc(2026, 8, 12),
          endAt: DateTime.utc(2026, 8, 13),
        ),
        isNull,
      );
      expect(
        Validators.unavailability(
          startAt: DateTime.utc(2026, 8, 13),
          endAt: DateTime.utc(2026, 8, 12),
        ),
        isNotNull,
      );
    });
  });

  group('Adresses — une adresse sans position est inutilisable', () {
    test('exige les deux coordonnées', () {
      expect(Validators.coordinates(latitude: 5.35, longitude: -4.02), isNull);
      expect(Validators.coordinates(latitude: 5.35), isNotNull);
      expect(Validators.coordinates(), isNotNull);
    });

    test('refuse des coordonnées hors bornes', () {
      expect(Validators.coordinates(latitude: 91, longitude: 0), isNotNull);
      expect(Validators.coordinates(latitude: 0, longitude: 181), isNotNull);
    });
  });

  group('Fichiers — filtrage avant tout appel réseau', () {
    test('accepte les types du service sous 10 Mo', () {
      expect(
        Validators.file(mimeType: 'application/pdf', sizeBytes: 1024),
        isNull,
      );
      expect(Validators.file(mimeType: 'image/webp', sizeBytes: 1024), isNull);
    });

    test('refuse un type non accepté', () {
      expect(
        Validators.file(mimeType: 'video/mp4', sizeBytes: 1024),
        isNotNull,
      );
    });

    test('refuse au-delà de 10 Mo, avec le plafond dans le message', () {
      final String? message = Validators.file(
        mimeType: 'image/jpeg',
        sizeBytes: FileLimits.maxSizeBytes + 1,
      );
      expect(message, isNotNull);
      expect(message, contains('10 Mo'));
    });

    test('avatar et portfolio n’acceptent que des images', () {
      expect(
        Validators.file(
          mimeType: 'application/pdf',
          sizeBytes: 1024,
          acceptedMimeTypes: FileLimits.imageOnlyMimeTypes,
        ),
        isNotNull,
      );
      expect(
        Validators.file(
          mimeType: 'image/png',
          sizeBytes: 1024,
          acceptedMimeTypes: FileLimits.imageOnlyMimeTypes,
        ),
        isNull,
      );
    });
  });

  group('Plafonds de collection', () {
    test('l’ajout devient indisponible au plafond, pas au-delà', () {
      expect(
        Validators.isAtCapacity(9, ContentLimits.addressesPerAccount),
        isFalse,
      );
      expect(
        Validators.isAtCapacity(10, ContentLimits.addressesPerAccount),
        isTrue,
      );
      expect(
        Validators.isAtCapacity(15, ContentLimits.zonesPerProvider),
        isTrue,
      );
      expect(Validators.isAtCapacity(20, ContentLimits.portfolioItems), isTrue);
      expect(Validators.isAtCapacity(50, ContentLimits.weeklySlots), isTrue);
    });

    test('le motif affiché nomme le plafond', () {
      expect(
        Validators.capacityMessage(
          'adresses',
          ContentLimits.addressesPerAccount,
        ),
        contains('10'),
      );
    });
  });
}
