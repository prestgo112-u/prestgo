// T046 — Matrice de la politique de rejeu (porte G4).
//
// Voir contracts/retry-and-idempotency.md §1. Chaque ligne du tableau y est vérifiée
// dans les deux sens : ce qui doit être rejoué, et surtout ce qui ne doit jamais
// l'être.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/retry_policy.dart';

const RetryPolicy policy = RetryPolicy();

const ApiException network = ApiException.network();
final ApiException gateway = ApiException.fromResponse(statusCode: 503);
final ApiException rateLimited = ApiException.fromResponse(statusCode: 429);
final ApiException serverError = ApiException.fromResponse(statusCode: 500);
final ApiException badRequest = ApiException.fromResponse(statusCode: 400);

void main() {
  group('Classement des requêtes', () {
    test('lectures', () {
      expect(
        RetryPolicy.classify(method: 'GET', path: '/me/missions'),
        RequestKind.read,
      );
      expect(
        RetryPolicy.classify(
          method: 'GET',
          path: '/providers/search?radiusKm=10',
        ),
        RequestKind.read,
      );
    });

    test('réservation', () {
      expect(
        RetryPolicy.classify(method: 'POST', path: '/missions'),
        RequestKind.booking,
      );
    });

    test('écritures idempotentes par construction', () {
      const List<(String, String)> cases = <(String, String)>[
        ('PUT', '/providers/me/zones'),
        ('PUT', '/providers/me/availabilities'),
        ('POST', '/me/favorites/p-1'),
        ('DELETE', '/me/favorites/p-1'),
        ('PATCH', '/me/notifications/n-1/read'),
        ('POST', '/me/devices'),
      ];
      for (final (String method, String path) in cases) {
        expect(
          RetryPolicy.classify(method: method, path: path),
          RequestKind.idempotentWrite,
          reason: '$method $path',
        );
      }
    });

    test('transitions de mission', () {
      for (final String action in <String>[
        'accept',
        'refuse',
        'start',
        'complete',
        'cancel',
      ]) {
        expect(
          RetryPolicy.classify(method: 'POST', path: '/missions/m-1/$action'),
          RequestKind.missionTransition,
          reason: action,
        );
      }
    });

    test('avis, message, envoi de fichier, authentification', () {
      expect(
        RetryPolicy.classify(method: 'POST', path: '/missions/m-1/review'),
        RequestKind.review,
      );
      expect(
        RetryPolicy.classify(
          method: 'POST',
          path: '/messages/threads/t-1/messages',
        ),
        RequestKind.message,
      );
      expect(
        RetryPolicy.classify(method: 'POST', path: '/files/upload'),
        RequestKind.fileUpload,
      );
      expect(
        RetryPolicy.classify(method: 'POST', path: '/auth/login'),
        RequestKind.auth,
      );
      expect(
        RetryPolicy.classify(method: 'POST', path: '/auth/refresh'),
        RequestKind.auth,
      );
    });

    test('toute autre écriture est traitée comme non sûre', () {
      expect(
        RetryPolicy.classify(method: 'PATCH', path: '/me'),
        RequestKind.unsafeWrite,
      );
      expect(
        RetryPolicy.classify(method: 'DELETE', path: '/me'),
        RequestKind.unsafeWrite,
      );
      expect(
        RetryPolicy.classify(method: 'POST', path: '/me/addresses'),
        RequestKind.unsafeWrite,
      );
    });
  });

  group('Lectures — 2 tentatives, 500 ms puis 1,5 s', () {
    test('sur erreur réseau', () {
      expect(
        policy.delayFor(kind: RequestKind.read, error: network, attempt: 0),
        const Duration(milliseconds: 500),
      );
      expect(
        policy.delayFor(kind: RequestKind.read, error: network, attempt: 1),
        const Duration(milliseconds: 1500),
      );
      // Troisième échec : on s'arrête.
      expect(
        policy.delayFor(kind: RequestKind.read, error: network, attempt: 2),
        isNull,
      );
    });

    test('sur 502/503/504 seulement', () {
      expect(
        policy.delayFor(kind: RequestKind.read, error: gateway, attempt: 0),
        isNotNull,
      );
      // Une 500 franche n'est pas rejouée : le service a traité la requête.
      expect(
        policy.delayFor(kind: RequestKind.read, error: serverError, attempt: 0),
        isNull,
      );
      expect(
        policy.delayFor(kind: RequestKind.read, error: badRequest, attempt: 0),
        isNull,
      );
    });
  });

  group('Réservation — 1 s puis 3 s, avec la même clé d’idempotence', () {
    test('sur erreur réseau', () {
      expect(
        policy.delayFor(kind: RequestKind.booking, error: network, attempt: 0),
        const Duration(seconds: 1),
      );
      expect(
        policy.delayFor(kind: RequestKind.booking, error: network, attempt: 1),
        const Duration(seconds: 3),
      );
      expect(
        policy.delayFor(kind: RequestKind.booking, error: network, attempt: 2),
        isNull,
      );
    });

    test(
      'une erreur métier n’est jamais rejouée — le contenu doit changer',
      () {
        expect(
          policy.delayFor(
            kind: RequestKind.booking,
            error: badRequest,
            attempt: 0,
          ),
          isNull,
        );
      },
    );
  });

  test('écriture idempotente — une seule reprise', () {
    expect(
      policy.delayFor(
        kind: RequestKind.idempotentWrite,
        error: network,
        attempt: 0,
      ),
      isNotNull,
    );
    expect(
      policy.delayFor(
        kind: RequestKind.idempotentWrite,
        error: network,
        attempt: 1,
      ),
      isNull,
    );
  });

  group('Ce qui n’est JAMAIS rejoué', () {
    test('les transitions de mission, quelle que soit l’erreur', () {
      for (final ApiException error in <ApiException>[
        network,
        gateway,
        serverError,
      ]) {
        expect(
          policy.delayFor(
            kind: RequestKind.missionTransition,
            error: error,
            attempt: 0,
          ),
          isNull,
          reason:
              'un rejeu renverrait « Action impossible depuis le statut … », '
              'incompréhensible pour l’utilisateur',
        );
      }
    });

    test(
      'les avis, les messages, les envois de fichier et l’authentification',
      () {
        for (final RequestKind kind in <RequestKind>[
          RequestKind.review,
          RequestKind.message,
          RequestKind.fileUpload,
          RequestKind.auth,
          RequestKind.unsafeWrite,
        ]) {
          expect(
            policy.delayFor(kind: kind, error: network, attempt: 0),
            isNull,
            reason: kind.name,
          );
        }
      },
    );

    test('un 429, pour aucune famille de requête', () {
      for (final RequestKind kind in RequestKind.values) {
        expect(
          policy.delayFor(kind: kind, error: rateLimited, attempt: 0),
          isNull,
          reason:
              'un rejeu sur 429 ne ferait qu’aggraver le débit (${kind.name})',
        );
      }
    });

    test('une requête annulée par l’application', () {
      expect(
        policy.delayFor(
          kind: RequestKind.read,
          error: const ApiException.cancelled(),
          attempt: 0,
        ),
        isNull,
      );
    });
  });
}
