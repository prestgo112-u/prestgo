// Réalisation du portfolio (data-model §4.7).
//
// Le fichier porte la règle de visibilité : ajouté au portfolio il devient
// `public` (affichable et mis en cache disque), retiré il redevient
// `restricted` — le cache d'image local doit alors être purgé (T215).
// Le réordonnancement se fait élément par élément : il n'existe aucune route
// de lot, chaque déplacement est un PATCH `displayOrder`.

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

class PortfolioItem {
  const PortfolioItem({
    required this.id,
    required this.displayOrder,
    required this.file,
    this.title,
    this.description,
    this.createdAt,
  });

  factory PortfolioItem.fromJson(JsonMap json) => PortfolioItem(
    id: json['id'] as String? ?? '',
    title: json['title'] as String?,
    description: json['description'] as String?,
    displayOrder: switch (json['displayOrder']) {
      final num v => v.toInt(),
      _ => 0,
    },
    createdAt: MissionDates.fromApiOrNull(json['createdAt'] as String?),
    file: switch (json['file']) {
      final Map<Object?, Object?> file => FileRef.fromJson(
        file.cast<String, Object?>(),
      ),
      _ => const FileRef(
        id: '',
        originalName: '',
        mimeType: '',
        size: 0,
        visibility: FileVisibility.restricted,
      ),
    },
  );

  final String id;

  /// ≤ 120 caractères, facultatif.
  final String? title;

  /// ≤ 1000 caractères, facultatif.
  final String? description;

  /// 0 à 100 — l'ordre d'affichage, celui de la liste servie.
  final int displayOrder;

  final DateTime? createdAt;
  final FileRef file;

  @override
  bool operator ==(Object other) => other is PortfolioItem && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PortfolioItem($id, ordre $displayOrder)';
}

/// Résultat du retrait d'une réalisation : le fichier est ramené en
/// `restricted` — l'appelant purge le cache d'image correspondant.
class PortfolioRemoval {
  const PortfolioRemoval({required this.removed, this.file});

  factory PortfolioRemoval.fromJson(JsonMap json) => PortfolioRemoval(
    removed: json['removed'] as bool? ?? true,
    file: switch (json['file']) {
      final Map<Object?, Object?> file => FileRef.fromJson(
        file.cast<String, Object?>(),
      ),
      _ => null,
    },
  );

  final bool removed;
  final FileRef? file;
}
