// Accès aux captures JSON de `test/fixtures/` (T053).
//
// Chaque fichier regroupe **toutes** les réponses d'une même opération, nommées par
// cas (`created`, `duplicate`, `rateLimited`…). Les regrouper ainsi plutôt que
// d'éparpiller un fichier par code de statut permet de lire d'un coup d'œil les
// formes qu'une route peut prendre — c'est précisément là que se cachent les pièges
// (`otp/verify` en renvoie deux, incompatibles entre elles).
//
// Les clés commençant par `_` sont de la documentation : elles ne sont jamais servies
// comme cas.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart' show fail;
import 'package:prestgo_mobile/core/api/api_envelope.dart';

/// Réponse capturée : code de statut et corps de l'enveloppe.
typedef Capture = (int statusCode, JsonMap body);

/// Charge un cas d'une capture — `fixture('auth/login', 'authenticated')`.
///
/// Échoue avec la liste des cas disponibles plutôt que par un `null` silencieux :
/// une faute de frappe dans un nom de cas doit se voir immédiatement.
Capture fixture(String file, String caseName) {
  final JsonMap document = fixtureDocument(file);
  final Object? entry = document[caseName];
  if (entry is! Map<Object?, Object?>) {
    final Iterable<String> available = document.keys.where(
      (String key) => !key.startsWith('_'),
    );
    fail(
      'Cas « $caseName » absent de test/fixtures/$file.json '
      '(disponibles : ${available.join(', ')})',
    );
  }
  final JsonMap json = entry.cast<String, Object?>();
  final Object? status = json['status'];
  final Object? body = json['body'];
  if (status is! int || body is! Map<Object?, Object?>) {
    fail(
      'Cas « $caseName » mal formé : `status` (int) et `body` (objet) requis',
    );
  }
  return (status, body.cast<String, Object?>());
}

/// Corps seul, pour les cas où le code de statut n'importe pas.
JsonMap fixtureBody(String file, String caseName) => fixture(file, caseName).$2;

/// Contenu de `data` d'un cas de succès.
///
/// Raccourci des tests de désérialisation, qui n'ont que faire de l'enveloppe.
JsonMap fixtureData(String file, String caseName) {
  final Object? data = fixtureBody(file, caseName)['data'];
  if (data is! Map<Object?, Object?>) {
    fail('Le cas « $caseName » de $file n’a pas d’objet `data`');
  }
  return data.cast<String, Object?>();
}

/// Document complet, mis en cache : les tests de contrat le relisent souvent.
JsonMap fixtureDocument(String file) =>
    _documents[file] ??= _read('test/fixtures/$file.json');

final Map<String, JsonMap> _documents = <String, JsonMap>{};

JsonMap _read(String path) {
  final File source = File(path);
  if (!source.existsSync()) {
    fail(
      'Capture introuvable : $path — les tests s’exécutent depuis la racine du '
      'paquet.',
    );
  }
  final Object? decoded = jsonDecode(source.readAsStringSync());
  if (decoded is! Map<Object?, Object?>) {
    fail('Capture illisible : $path');
  }
  return decoded.cast<String, Object?>();
}
