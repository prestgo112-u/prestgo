// Recherche et fiche publique — opérations 25 et 26 (T095).
//
// ⚠️ **Aucun cache persistant ici**, et c'est délibéré. Un résultat de recherche
// dépend de la position, de l'heure demandée et de la disponibilité déclarée du
// prestataire : servi depuis le disque au démarrage suivant, il proposerait des
// créneaux déjà pris et des prestataires devenus indisponibles. Le seul cache est en
// **mémoire**, pour la durée de la session : il évite de recharger une fiche qu'on
// vient de quitter d'un retour arrière (data-model §12).
//
// Ces deux routes sont publiques : elles fonctionnent sans session, ce qui est la
// condition d'un accueil consultable sans compte (FR-022).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/pagination/paged_notifier.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/search/domain/provider_search.dart';

class SearchRepository {
  SearchRepository(this._client);

  final ApiClient _client;

  /// Fiches déjà chargées pendant cette session. Vidé avec le conteneur d'état,
  /// donc à la déconnexion (SC-012).
  final Map<String, ProviderPublicProfile> _profiles =
      <String, ProviderPublicProfile>{};

  /// `GET /providers/search` — la seule route paginée de cette phase.
  ///
  /// `limit` est plafonné à 50 côté service : le dépasser produirait un 400. On
  /// écrête ici plutôt que de faire confiance à l'appelant.
  Future<PagedPage<ProviderSearchResult>> search(
    ProviderSearchQuery query, {
    required int page,
    required int limit,
  }) async {
    final ApiEnvelope<List<ProviderSearchResult>> envelope = await _client
        .get<List<ProviderSearchResult>>(
          '/providers/search',
          query: query.toQueryParameters(
            page: page,
            limit: limit.clamp(1, PaginationLimits.maxSearchPageSize),
          ),
          parse: parseList<ProviderSearchResult>(ProviderSearchResult.fromJson),
        );

    return PagedPage<ProviderSearchResult>(
      items: envelope.data ?? const <ProviderSearchResult>[],
      meta: envelope.meta,
    );
  }

  /// `GET /providers/{id}/public` — la fiche entière en un appel.
  ///
  /// [refresh] force la relecture : le retour arrière depuis une réservation doit
  /// montrer un agenda à jour.
  Future<ProviderPublicProfile> publicProfile(
    String providerId, {
    bool refresh = false,
  }) async {
    if (!refresh) {
      final ProviderPublicProfile? cached = _profiles[providerId];
      if (cached != null) {
        return cached;
      }
    }

    final ApiEnvelope<ProviderPublicProfile> envelope = await _client
        .get<ProviderPublicProfile>(
          '/providers/$providerId/public',
          parse: parseObject<ProviderPublicProfile>(
            ProviderPublicProfile.fromJson,
          ),
        );

    final ProviderPublicProfile profile = envelope.requireData;
    _profiles[providerId] = profile;
    return profile;
  }

  /// Fiche déjà chargée, sans requête — utilisée par le parcours de réservation,
  /// qui a besoin de l'agenda et des zones sans les recharger à chaque étape.
  ProviderPublicProfile? loadedProfile(String providerId) =>
      _profiles[providerId];

  /// `GET /providers/{id}/reviews` — paginé, `data` est un **tableau**.
  Future<PagedPage<ProviderReview>> reviews(
    String providerId, {
    required int page,
    required int limit,
  }) async {
    final ApiEnvelope<List<ProviderReview>> envelope = await _client
        .get<List<ProviderReview>>(
          '/providers/$providerId/reviews',
          query: <String, Object?>{'page': page, 'limit': limit},
          parse: parseList<ProviderReview>(ProviderReview.fromJson),
        );
    return PagedPage<ProviderReview>(
      items: envelope.data ?? const <ProviderReview>[],
      meta: envelope.meta,
    );
  }
}

final Provider<SearchRepository> searchRepositoryProvider =
    Provider<SearchRepository>(
      (Ref ref) => SearchRepository(ref.watch(apiClientProvider)),
    );
