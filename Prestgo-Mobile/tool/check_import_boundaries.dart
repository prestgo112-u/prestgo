// Vérificateur de la règle de frontière d'import — porte G5 du plan.
//
// Les règles sont déclarées dans `analysis_options.yaml`, sous la clé
// `prestgo_import_boundaries`, à côté des autres règles d'analyse. Dart n'offrant
// aucun lint natif d'interdiction d'import, ce script les applique.
//
// Usage :
//   dart run tool/check_import_boundaries.dart
//
// Sortie : 0 si aucune violation, 1 sinon (avec le détail fichier / ligne / import).

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Nom du paquet, pour résoudre les imports `package:` internes.
const String _packageName = 'prestgo_mobile';

/// Racines analysées.
const List<String> _analysedRoots = <String>['lib'];

/// Fichiers générés : ils reproduisent les imports de leur source.
bool _isGenerated(String path) =>
    path.endsWith('.g.dart') || path.endsWith('.freezed.dart');

final RegExp _directive = RegExp(
  r'''^\s*(?:import|export)\s+(?:'([^']+)'|"([^"]+)")''',
  multiLine: true,
);

class Violation {
  Violation({
    required this.rule,
    required this.file,
    required this.line,
    required this.target,
    required this.message,
  });

  final String rule;
  final String file;
  final int line;
  final String target;
  final String message;
}

void main(List<String> args) {
  final File optionsFile = File('analysis_options.yaml');
  if (!optionsFile.existsSync()) {
    stderr.writeln(
      'analysis_options.yaml introuvable — lancer depuis la racine.',
    );
    exit(2);
  }

  final Object? loaded = loadYaml(optionsFile.readAsStringSync());
  final Object? config = loaded is YamlMap
      ? loaded['prestgo_import_boundaries']
      : null;
  if (config is! YamlMap) {
    stderr.writeln(
      'Aucune section `prestgo_import_boundaries` dans analysis_options.yaml.',
    );
    exit(2);
  }

  final List<_DirectedRule> rules = _readRules(config);
  final _Surfaces? surfaces = _readSurfaces(config);
  final _CrossFeatureData? crossFeatureData = _readCrossFeatureData(config);

  final List<Violation> violations = <Violation>[];
  int filesScanned = 0;

  for (final String root in _analysedRoots) {
    final Directory dir = Directory(root);
    if (!dir.existsSync()) {
      continue;
    }
    for (final FileSystemEntity entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final String file = _normalise(p.relative(entity.path));
      if (_isGenerated(file)) {
        continue;
      }
      filesScanned++;

      final String source = entity.readAsStringSync();
      for (final RegExpMatch match in _directive.allMatches(source)) {
        final String uri = match.group(1) ?? match.group(2)!;
        final String? target = _resolve(uri, file);
        if (target == null) {
          continue;
        }
        final int line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;

        for (final _DirectedRule rule in rules) {
          if (!_within(file, rule.from)) {
            continue;
          }
          for (final String denied in rule.deny) {
            if (_within(target, denied)) {
              violations.add(
                Violation(
                  rule: rule.name,
                  file: file,
                  line: line,
                  target: target,
                  message: rule.message,
                ),
              );
            }
          }
        }

        if (surfaces != null) {
          final String? fromGroup = surfaces.groupOf(file);
          final String? toGroup = surfaces.groupOf(target);
          if (fromGroup != null && toGroup != null && fromGroup != toGroup) {
            violations.add(
              Violation(
                rule: 'surfaces ($fromGroup → $toGroup)',
                file: file,
                line: line,
                target: target,
                message: surfaces.message,
              ),
            );
          }
        }

        if (crossFeatureData != null) {
          final String? fromFeature = _featureOf(file);
          final String? toFeature = _featureOf(target);
          final bool targetIsDataLayer =
              toFeature != null &&
              _within(target, 'lib/features/$toFeature/data');
          if (targetIsDataLayer &&
              fromFeature != null &&
              fromFeature != toFeature) {
            violations.add(
              Violation(
                rule: 'cross_feature_data',
                file: file,
                line: line,
                target: target,
                message: crossFeatureData.message,
              ),
            );
          }
        }
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln(
      'Frontières d\'import respectées — $filesScanned fichier(s) analysé(s). 🎉',
    );
    return;
  }

  stdout.writeln(
    '${violations.length} violation(s) de frontière d\'import '
    '($filesScanned fichier(s) analysé(s)) :\n',
  );
  for (final Violation v in violations) {
    stdout
      ..writeln('  [${v.rule}] ${v.file}:${v.line}')
      ..writeln('    importe : ${v.target}')
      ..writeln('    ${v.message}\n');
  }
  exit(1);
}

// --- Lecture de la configuration ------------------------------------------------

class _DirectedRule {
  _DirectedRule({
    required this.name,
    required this.from,
    required this.deny,
    required this.message,
  });

  final String name;
  final String from;
  final List<String> deny;
  final String message;
}

class _Surfaces {
  _Surfaces({required this.groups, required this.message});

  final Map<String, List<String>> groups;
  final String message;

  String? groupOf(String path) {
    for (final MapEntry<String, List<String>> entry in groups.entries) {
      for (final String prefix in entry.value) {
        if (_within(path, prefix)) {
          return entry.key;
        }
      }
    }
    return null;
  }
}

class _CrossFeatureData {
  _CrossFeatureData({required this.message});

  final String message;
}

List<_DirectedRule> _readRules(YamlMap config) {
  final Object? raw = config['rules'];
  if (raw is! YamlList) {
    return const <_DirectedRule>[];
  }
  return raw.whereType<YamlMap>().map((YamlMap entry) {
    final Object? deny = entry['deny'];
    return _DirectedRule(
      name: (entry['name'] as String?) ?? 'règle sans nom',
      from: _normalise(entry['from'] as String),
      deny: deny is YamlList
          ? deny.map((Object? e) => _normalise(e! as String)).toList()
          : <String>[_normalise(deny! as String)],
      message: _text(entry['message']),
    );
  }).toList();
}

_Surfaces? _readSurfaces(YamlMap config) {
  final Object? raw = config['surfaces'];
  if (raw is! YamlMap) {
    return null;
  }
  final Object? groups = raw['groups'];
  if (groups is! YamlMap) {
    return null;
  }
  return _Surfaces(
    message: _text(raw['message']),
    groups: <String, List<String>>{
      for (final MapEntry<Object?, Object?> entry in groups.entries)
        entry.key! as String: (entry.value! as YamlList)
            .map((Object? e) => _normalise(e! as String))
            .toList(),
    },
  );
}

_CrossFeatureData? _readCrossFeatureData(YamlMap config) {
  final Object? raw = config['cross_feature_data'];
  if (raw is! YamlMap || raw['enabled'] != true) {
    return null;
  }
  return _CrossFeatureData(message: _text(raw['message']));
}

String _text(Object? value) =>
    (value as String? ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

// --- Résolution des chemins ------------------------------------------------------

String _normalise(String path) => path.replaceAll(r'\', '/');

/// Vrai si [path] est [prefix] ou vit sous [prefix].
bool _within(String path, String prefix) =>
    path == prefix || path.startsWith('$prefix/');

/// Nom de la fonctionnalité portant [path], ou `null` hors de `lib/features/`.
String? _featureOf(String path) {
  const String root = 'lib/features/';
  if (!path.startsWith(root)) {
    return null;
  }
  final int slash = path.indexOf('/', root.length);
  return slash == -1 ? null : path.substring(root.length, slash);
}

/// Traduit l'URI d'un import en chemin du dépôt, ou `null` s'il est externe.
String? _resolve(String uri, String fromFile) {
  if (uri.startsWith('dart:')) {
    return null;
  }
  if (uri.startsWith('package:')) {
    const String selfPrefix = 'package:$_packageName/';
    if (!uri.startsWith(selfPrefix)) {
      return null;
    }
    return 'lib/${uri.substring(selfPrefix.length)}';
  }
  // Import relatif : résolu depuis le dossier du fichier courant.
  return _normalise(p.normalize(p.join(p.dirname(fromFile), uri)));
}
