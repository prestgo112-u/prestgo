// Enveloppe de réponse — modèle **unique** de l'application.
//
// Voir contracts/api-envelope.md. Porte G2 : aucun écran, aucun dépôt ne lit
// `response.data['data']` ; tout passe par ce fichier.
//
// Écrit à la main plutôt que généré (R9) : `data` prend trois formes dans le
// périmètre et un `parse` explicite par appel est plus sûr qu'un client généré qui
// masquerait la variation.

/// Carte JSON telle que la renvoie `dio`.
typedef JsonMap = Map<String, Object?>;

/// Fonction d'interprétation de `data`, fournie par l'appelant.
typedef EnvelopeParser<T> = T Function(Object? data);

/// Détail d'erreur de validation : `{ field?, code, message }`.
class ApiErrorDetail {
  const ApiErrorDetail({required this.code, required this.message, this.field});

  factory ApiErrorDetail.fromJson(JsonMap json) => ApiErrorDetail(
    field: json['field'] as String?,
    code: json['code'] as String? ?? '',
    message: json['message'] as String? ?? '',
  );

  /// Chemin complet du champ, y compris imbriqué (`slots.1.startTime`).
  ///
  /// Absent sur les erreurs métier posées à la main par un service (écart n°13).
  final String? field;
  final String code;
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ApiErrorDetail &&
      other.field == field &&
      other.code == code &&
      other.message == message;

  @override
  int get hashCode => Object.hash(field, code, message);

  @override
  String toString() => 'ApiErrorDetail($field, $code, $message)';
}

/// Métadonnées : pagination et identifiant de corrélation.
class ApiMeta {
  const ApiMeta({this.page, this.limit, this.total, this.correlationId});

  factory ApiMeta.fromJson(JsonMap json) => ApiMeta(
    page: _asInt(json['page']),
    limit: _asInt(json['limit']),
    total: _asInt(json['total']),
    correlationId: json['correlationId'] as String?,
  );

  final int? page;
  final int? limit;
  final int? total;

  /// Présent dans `meta` de **toutes** les erreurs — joint à chaque incident
  /// remonté (FR-091, SC-010), jamais affiché tel quel à l'utilisateur.
  final String? correlationId;

  /// Vrai s'il reste au moins une page après celle-ci.
  ///
  /// Faux dès qu'une des trois valeurs manque : une réponse non paginée ne porte
  /// pas de `meta` de pagination.
  bool get hasMore {
    final int? page = this.page;
    final int? limit = this.limit;
    final int? total = this.total;
    if (page == null || limit == null || total == null) {
      return false;
    }
    return page * limit < total;
  }

  /// Vrai si cette `meta` décrit une pagination (et non le seul `correlationId`).
  bool get isPaginated => page != null && limit != null && total != null;

  @override
  bool operator ==(Object other) =>
      other is ApiMeta &&
      other.page == page &&
      other.limit == limit &&
      other.total == total &&
      other.correlationId == correlationId;

  @override
  int get hashCode => Object.hash(page, limit, total, correlationId);

  @override
  String toString() =>
      'ApiMeta(page: $page, limit: $limit, total: $total, cid: $correlationId)';
}

/// Enveloppe générique `{ success, message, data, errors, meta }`.
class ApiEnvelope<T> {
  const ApiEnvelope({
    required this.success,
    this.message,
    this.data,
    this.errors = const <ApiErrorDetail>[],
    this.meta,
    this.statusCode,
  });

  /// Décode une enveloppe et délègue l'interprétation de `data` à [parse].
  ///
  /// [parse] n'est appelé **que** si `data` est présent : une réponse de succès sans
  /// contenu (déconnexion, suppression) reste valide.
  factory ApiEnvelope.fromJson(
    JsonMap json,
    EnvelopeParser<T> parse, {
    int? statusCode,
  }) {
    final Object? rawErrors = json['errors'];
    final Object? rawMeta = json['meta'];
    final Object? rawData = json['data'];

    return ApiEnvelope<T>(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String?,
      data: rawData == null ? null : parse(rawData),
      errors: rawErrors is List
          ? rawErrors
                .whereType<Map<Object?, Object?>>()
                .map(
                  (Map<Object?, Object?> e) =>
                      ApiErrorDetail.fromJson(e.cast<String, Object?>()),
                )
                .toList(growable: false)
          : const <ApiErrorDetail>[],
      meta: rawMeta is Map<Object?, Object?>
          ? ApiMeta.fromJson(rawMeta.cast<String, Object?>())
          : null,
      statusCode: statusCode,
    );
  }

  final bool success;

  /// Message affichable tel quel, sauf exceptions listées au §4 du contrat.
  final String? message;

  /// Contenu interprété — `null` sur une réponse de succès sans contenu.
  final T? data;

  final List<ApiErrorDetail> errors;
  final ApiMeta? meta;

  /// Code de la réponse **de succès**, quand l'appelant en a besoin.
  ///
  /// N'existe que pour les rares routes dont deux succès ont un sens différent.
  /// Une seule aujourd'hui : `POST /missions` répond 201 quand la mission vient
  /// d'être créée et 200 quand une clé d'idempotence rejouée renvoie celle qui
  /// existait déjà.
  ///
  /// Il n'est **pas** exposé aux dépôts ni aux écrans sous cette forme : ils lisent
  /// [isCreated], qui porte le sens plutôt que le nombre (porte G2). Les échecs, eux,
  /// passent tous par `ApiException` et ses prédicats.
  final int? statusCode;

  /// Vrai si la ressource vient d'être créée, faux si la réponse rend une ressource
  /// déjà existante. `null` sur les routes qui ne distinguent pas les deux.
  bool? get isCreated => statusCode == null ? null : statusCode == 201;

  /// Contenu obligatoire : lève si le service a répondu sans `data`.
  ///
  /// À utiliser par les dépôts dont la route renvoie toujours un contenu ; les
  /// routes qui peuvent répondre à vide lisent [data].
  T get requireData {
    final T? value = data;
    if (value == null) {
      throw StateError(
        'Réponse sans contenu alors que la route en attend un (message: $message)',
      );
    }
    return value;
  }

  @override
  String toString() =>
      'ApiEnvelope(success: $success, message: $message, data: $data)';
}

// --- Interprètes de `data` — les trois formes du contrat -------------------------

/// Forme **objet** : `GET /me`, `GET /missions/{id}`, `GET /providers/me`.
EnvelopeParser<T> parseObject<T>(T Function(JsonMap json) fromJson) =>
    (Object? data) {
      if (data is! Map<Object?, Object?>) {
        throw FormatException(
          'Objet attendu dans `data`, reçu ${data.runtimeType}',
        );
      }
      return fromJson(data.cast<String, Object?>());
    };

/// Forme **tableau** : `GET /me/addresses`, `GET /providers/search`,
/// `GET /providers/{id}/reviews` (depuis la correction de l'écart n°15).
EnvelopeParser<List<T>> parseList<T>(T Function(JsonMap json) fromJson) =>
    (Object? data) {
      if (data is! List) {
        throw FormatException(
          'Tableau attendu dans `data`, reçu ${data.runtimeType}',
        );
      }
      return data
          .whereType<Map<Object?, Object?>>()
          .map((Map<Object?, Object?> e) => fromJson(e.cast<String, Object?>()))
          .toList(growable: false);
    };

/// Forme **objet structuré non paginé** : `GET /providers/me/documents`
/// (`requiredTypes`, `missingTypes`, `current`, `documents`).
///
/// Identique à [parseObject] dans sa mécanique : elle existe pour que l'intention
/// soit lisible à l'appel et que le contrat reste explicite.
EnvelopeParser<T> parseStructured<T>(T Function(JsonMap json) fromJson) =>
    parseObject<T>(fromJson);

/// `data` ignoré — réponses de succès sans contenu exploitable.
EnvelopeParser<void> parseNothing() => (Object? _) {};

int? _asInt(Object? value) => switch (value) {
  final int v => v,
  final num v => v.toInt(),
  final String v => int.tryParse(v),
  _ => null,
};
