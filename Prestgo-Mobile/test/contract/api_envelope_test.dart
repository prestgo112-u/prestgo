// T043 — Contrat de l'enveloppe : les **trois formes** de `data`.
//
// Voir contracts/api-envelope.md §2. Ces captures reproduisent la forme réelle des
// réponses du service ; le jour où elle change, ce test tombe.

import 'package:flutter_test/flutter_test.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';

/// Modèle minimal, suffisant pour vérifier le décodage.
class _Item {
  const _Item(this.id, this.name);

  factory _Item.fromJson(JsonMap json) =>
      _Item(json['id'] as String, json['name'] as String);

  final String id;
  final String name;
}

/// Vue structurée de `GET /providers/me/documents`.
class _DocumentsView {
  const _DocumentsView({
    required this.requiredTypes,
    required this.missingTypes,
    required this.documents,
  });

  factory _DocumentsView.fromJson(JsonMap json) => _DocumentsView(
    requiredTypes: (json['requiredTypes']! as List<Object?>).cast<String>(),
    missingTypes: (json['missingTypes']! as List<Object?>).cast<String>(),
    documents: (json['documents']! as List<Object?>)
        .cast<Map<Object?, Object?>>()
        .map(
          (Map<Object?, Object?> e) =>
              _Item.fromJson(e.cast<String, Object?>()),
        )
        .toList(),
  );

  final List<String> requiredTypes;
  final List<String> missingTypes;
  final List<_Item> documents;
}

void main() {
  group('Forme 1 — objet (GET /me, GET /missions/{id})', () {
    test('décode `data` en modèle', () {
      const JsonMap body = <String, Object?>{
        'success': true,
        'message': 'Profil récupéré',
        'data': <String, Object?>{'id': 'u-1', 'name': 'Awa'},
      };

      final ApiEnvelope<_Item> envelope = ApiEnvelope<_Item>.fromJson(
        body,
        parseObject<_Item>(_Item.fromJson),
      );

      expect(envelope.success, isTrue);
      expect(envelope.message, 'Profil récupéré');
      expect(envelope.requireData.id, 'u-1');
      expect(envelope.requireData.name, 'Awa');
      expect(envelope.errors, isEmpty);
    });

    test('refuse un tableau là où un objet est attendu', () {
      const JsonMap body = <String, Object?>{
        'success': true,
        'data': <Object?>[],
      };

      expect(
        () => ApiEnvelope<_Item>.fromJson(
          body,
          parseObject<_Item>(_Item.fromJson),
        ),
        throwsFormatException,
      );
    });
  });

  group('Forme 2 — tableau (GET /me/addresses, GET /providers/search)', () {
    test('décode `data` en liste et lit la pagination dans `meta`', () {
      const JsonMap body = <String, Object?>{
        'success': true,
        'data': <Object?>[
          <String, Object?>{'id': 'a-1', 'name': 'Domicile'},
          <String, Object?>{'id': 'a-2', 'name': 'Bureau'},
        ],
        'meta': <String, Object?>{'page': 1, 'limit': 20, 'total': 42},
      };

      final ApiEnvelope<List<_Item>> envelope =
          ApiEnvelope<List<_Item>>.fromJson(
            body,
            parseList<_Item>(_Item.fromJson),
          );

      expect(envelope.requireData, hasLength(2));
      expect(envelope.requireData.first.name, 'Domicile');
      expect(envelope.meta!.total, 42);
      expect(envelope.meta!.isPaginated, isTrue);
      expect(envelope.meta!.hasMore, isTrue);
    });

    test('GET /providers/{id}/reviews renvoie un tableau, pas `data.reviews` '
        '(correction de l’écart n°15)', () {
      const JsonMap body = <String, Object?>{
        'success': true,
        'data': <Object?>[
          <String, Object?>{'id': 'r-1', 'name': 'Très bien'},
        ],
        'meta': <String, Object?>{'page': 3, 'limit': 20, 'total': 60},
      };

      final ApiEnvelope<List<_Item>> envelope =
          ApiEnvelope<List<_Item>>.fromJson(
            body,
            parseList<_Item>(_Item.fromJson),
          );

      expect(envelope.requireData, hasLength(1));
      // Dernière page : 3 × 20 = 60 = total.
      expect(envelope.meta!.hasMore, isFalse);
    });
  });

  group('Forme 3 — objet structuré (GET /providers/me/documents)', () {
    test('décode les quatre sections en un seul modèle de vue', () {
      const JsonMap body = <String, Object?>{
        'success': true,
        'data': <String, Object?>{
          'requiredTypes': <Object?>['identity', 'address_proof'],
          'missingTypes': <Object?>['address_proof'],
          'current': <String, Object?>{},
          'documents': <Object?>[
            <String, Object?>{'id': 'd-1', 'name': 'CNI recto'},
          ],
        },
      };

      final ApiEnvelope<_DocumentsView> envelope =
          ApiEnvelope<_DocumentsView>.fromJson(
            body,
            parseStructured<_DocumentsView>(_DocumentsView.fromJson),
          );

      expect(envelope.requireData.requiredTypes, <String>[
        'identity',
        'address_proof',
      ]);
      expect(envelope.requireData.missingTypes, <String>['address_proof']);
      expect(envelope.requireData.documents, hasLength(1));
      // Réponse non paginée : aucune `meta` de pagination.
      expect(envelope.meta, isNull);
    });
  });

  group('Cas limites', () {
    test('succès sans contenu — `parse` n’est jamais appelé', () {
      const JsonMap body = <String, Object?>{
        'success': true,
        'message': 'Déconnexion effectuée',
      };
      var parsed = false;

      final ApiEnvelope<_Item> envelope = ApiEnvelope<_Item>.fromJson(body, (
        Object? data,
      ) {
        parsed = true;
        return const _Item('x', 'x');
      });

      expect(parsed, isFalse);
      expect(envelope.data, isNull);
      expect(() => envelope.requireData, throwsStateError);
    });

    test('`meta` sans pagination ne porte que le correlationId', () {
      const JsonMap body = <String, Object?>{
        'success': false,
        'message': 'Erreur',
        'meta': <String, Object?>{'correlationId': 'req-42'},
      };

      final ApiEnvelope<void> envelope = ApiEnvelope<void>.fromJson(
        body,
        parseNothing(),
      );

      expect(envelope.meta!.correlationId, 'req-42');
      expect(envelope.meta!.isPaginated, isFalse);
      expect(envelope.meta!.hasMore, isFalse);
    });

    test('`errors[]` porte le chemin complet d’un champ imbriqué', () {
      const JsonMap body = <String, Object?>{
        'success': false,
        'message': 'Validation échouée',
        'errors': <Object?>[
          <String, Object?>{
            'field': 'slots.1.startTime',
            'code': 'invalid_time',
            'message': 'Heure invalide',
          },
        ],
      };

      final ApiEnvelope<void> envelope = ApiEnvelope<void>.fromJson(
        body,
        parseNothing(),
      );

      expect(envelope.errors.single.field, 'slots.1.startTime');
      expect(envelope.errors.single.code, 'invalid_time');
    });
  });
}
