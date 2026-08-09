// Justificatifs du dossier prestataire (data-model §4.6).
//
// L'écran ne décide de rien : la vue complète — types exigés, types manquants,
// dernière version par type, historique — est **fournie par le service**
// (`GET /providers/me/documents`). Coder « pièce d'identité » en dur casserait le
// jour où le back-office exige un second justificatif (FR-057).
//
// Règles serveur à ne pas contourner :
//   • un document `approved` ne se remplace pas ;
//   • un redépôt crée une **version**, il n'écrase rien ;
//   • un dépôt en `changes_requested` repasse le dossier en `pending_review`
//     tout seul → recharger `GET /providers/me` après **chaque** dépôt (FR-059).

import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';

enum ProviderDocumentStatus {
  pending,
  approved,
  rejected;

  static ProviderDocumentStatus parse(String? raw) => switch (raw) {
    'approved' => ProviderDocumentStatus.approved,
    'rejected' => ProviderDocumentStatus.rejected,
    _ => ProviderDocumentStatus.pending,
  };

  String get label => switch (this) {
    ProviderDocumentStatus.pending => 'En attente d’examen',
    ProviderDocumentStatus.approved => 'Validé',
    ProviderDocumentStatus.rejected => 'Refusé',
  };
}

/// Une version d'un justificatif.
class ProviderDocument {
  const ProviderDocument({
    required this.id,
    required this.type,
    required this.status,
    required this.version,
    required this.file,
    this.rejectionReason,
    this.reviewedAt,
    this.createdAt,
  });

  factory ProviderDocument.fromJson(JsonMap json) => ProviderDocument(
    id: json['id'] as String? ?? '',
    type: json['type'] as String? ?? '',
    status: ProviderDocumentStatus.parse(json['status'] as String?),
    version: switch (json['version']) {
      final num v => v.toInt(),
      _ => 1,
    },
    rejectionReason: json['rejectionReason'] as String?,
    reviewedAt: MissionDates.fromApiOrNull(json['reviewedAt'] as String?),
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
        visibility: FileVisibility.sensitive,
      ),
    },
  );

  final String id;
  final String type;
  final ProviderDocumentStatus status;
  final int version;

  /// **La** donnée de l'écran de correction : ce que le prestataire doit refaire.
  final String? rejectionReason;

  final DateTime? reviewedAt;
  final DateTime? createdAt;
  final FileRef file;

  /// Un document validé ne se remplace pas — l'action de redépôt est grisée.
  bool get isLocked => status == ProviderDocumentStatus.approved;

  @override
  bool operator ==(Object other) => other is ProviderDocument && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ProviderDocument($type v$version, ${status.name})';
}

/// La vue d'écran complète, telle que le service la construit.
class ProviderDocumentsOverview {
  const ProviderDocumentsOverview({
    required this.requiredTypes,
    required this.missingTypes,
    required this.current,
    required this.documents,
  });

  factory ProviderDocumentsOverview.fromJson(JsonMap json) =>
      ProviderDocumentsOverview(
        requiredTypes: _strings(json['requiredTypes']),
        missingTypes: _strings(json['missingTypes']),
        current: _documents(json['current']),
        documents: _documents(json['documents']),
      );

  /// Construit les lignes de l'écran — l'ordre du service est conservé.
  final List<String> requiredTypes;

  /// Types **sans justificatif exploitable** (absent ou rejeté) → lignes rouges.
  final List<String> missingTypes;

  /// Dernière version de chaque type — ce qui est affiché par ligne.
  final List<ProviderDocument> current;

  /// Toutes les versions, du plus récent au plus ancien par type — l'historique.
  final List<ProviderDocument> documents;

  ProviderDocument? currentFor(String type) =>
      current.where((ProviderDocument d) => d.type == type).firstOrNull;

  List<ProviderDocument> versionsFor(String type) => documents
      .where((ProviderDocument d) => d.type == type)
      .toList(growable: false);

  bool isMissing(String type) => missingTypes.contains(type);

  static List<String> _strings(Object? value) => switch (value) {
    final List<Object?> list => list.whereType<String>().toList(
      growable: false,
    ),
    _ => const <String>[],
  };

  static List<ProviderDocument> _documents(Object? value) => switch (value) {
    final List<Object?> list =>
      list
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> e) =>
                ProviderDocument.fromJson(e.cast<String, Object?>()),
          )
          .toList(growable: false),
    _ => const <ProviderDocument>[],
  };

  @override
  String toString() =>
      'ProviderDocumentsOverview(required: $requiredTypes, '
      'missing: $missingTypes, current: ${current.length})';
}

/// Libellé affichable d'un type de justificatif.
///
/// Seuls les types **connus** ont une traduction ; un type inconnu s'affiche tel
/// quel plutôt que d'être masqué — le back-office peut en créer à tout moment.
String documentTypeLabel(String type) => switch (type) {
  'id_card' => 'Pièce d’identité',
  'business_registration' => 'Registre de commerce',
  'proof_of_address' => 'Justificatif de domicile',
  _ => type,
};
