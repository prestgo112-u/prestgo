// Dossier prestataire — opérations 65 à 88 (T149, complété en Phase 10), plus
// les lectures publiques du catalogue dont l'onboarding a besoin (catégories
// pour P3, zones pour P5) et la relecture des absences (opération 29).
//
// Décisions structurantes :
//
//   • **le 409 de la création n'est pas une erreur** (opération 65) : il signifie
//     « profil déjà là », c'est la reprise d'un parcours interrompu. Le dépôt
//     enchaîne sur `GET /providers/me` et rend l'aperçu, si bien qu'aucun écran
//     n'a ce cas à traiter (scénario 4.3) ;
//   • **zones et agenda s'écrivent par remplacement intégral** (PUT) : l'état
//     complet part à chaque fois, le service ne fait pas de différentiel ;
//   • **rien n'est mis en cache** : le dossier change à chaque étape du parcours,
//     et sa vérité — checklist, `canSubmit` — n'a de valeur que fraîche
//     (porte G1). La lecture publique du catalogue, elle, a son cache 24 h côté
//     client (`features/search`), hors de portée de cette surface (porte G5) :
//     l'onboarding la relit, deux routes légères et non paginées.
//
// Toutes les routes `/providers/me/*` répondent 403 tant que le profil n'existe
// pas — `ApiException.hasNoProviderProfile` renvoie l'écran vers la création.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/provider_space/domain/portfolio_item.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_document.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_offer.dart';
import 'package:prestgo_mobile/features/provider_space/domain/unavailability.dart';
import 'package:prestgo_mobile/features/provider_space/domain/weekly_slot.dart';
import 'package:prestgo_mobile/shared/catalog/catalog.dart';

class ProviderSelfRepository {
  const ProviderSelfRepository(this._client);

  final ApiClient _client;

  // --- Dossier (65 à 68) ----------------------------------------------------------

  /// `POST /providers/me` — opération 65.
  ///
  /// Le 201 répond le même DTO que `GET /providers/me` : l'aperçu complet,
  /// checklist déjà calculée — le hub s'alimente sans second appel. Le **409 est
  /// un succès** : le profil existe, on le relit et on rend la même chose.
  Future<ProviderProfile> createProfile({
    required String publicName,
    String? bio,
    int? experienceYears,
  }) async {
    try {
      final ApiEnvelope<ProviderProfile> envelope = await _client
          .post<ProviderProfile>(
            '/providers/me',
            body: <String, Object?>{
              'publicName': publicName,
              // Chaîne vide = « pas de présentation » côté service : autant ne
              // rien envoyer.
              'bio': ?_nonEmpty(bio),
              'experienceYears': ?experienceYears,
            },
            parse: parseObject<ProviderProfile>(ProviderProfile.fromJson),
          );
      return envelope.requireData;
    } on ApiException catch (error) {
      if (error.isConflict) {
        return overview();
      }
      rethrow;
    }
  }

  /// `GET /providers/me` — opération 66. Source unique de la checklist (P8) et du
  /// suivi (P9).
  Future<ProviderProfile> overview() async {
    final ApiEnvelope<ProviderProfile> envelope = await _client
        .get<ProviderProfile>(
          '/providers/me',
          parse: parseObject<ProviderProfile>(ProviderProfile.fromJson),
        );
    return envelope.requireData;
  }

  /// `PATCH /providers/me` — opération 67, identité du profil.
  ///
  /// En `pending_review`, le service refuse (400) dès que le corps touche
  /// `publicName`, `bio`, `experienceYears` ou `avatarFileId` — le verrou est le
  /// sien, l'écran se contente de griser (FR-062). Pour la disponibilité seule,
  /// passer par [setAvailability].
  Future<ProviderProfile> updateProfile({
    String? publicName,
    String? bio,
    int? experienceYears,
    String? avatarFileId,
  }) async {
    final ApiEnvelope<ProviderProfile> envelope = await _client
        .patch<ProviderProfile>(
          '/providers/me',
          body: <String, Object?>{
            'publicName': ?publicName,
            'bio': ?bio,
            'experienceYears': ?experienceYears,
            'avatarFileId': ?avatarFileId,
          },
          parse: parseObject<ProviderProfile>(ProviderProfile.fromJson),
        );
    return envelope.requireData;
  }

  /// `PATCH /providers/me` avec `availabilityStatus` **seul** — le seul champ qui
  /// traverse le verrou de `pending_review` (scénario 4.8).
  Future<ProviderProfile> setAvailability(AvailabilityStatus status) async {
    final ApiEnvelope<ProviderProfile> envelope = await _client
        .patch<ProviderProfile>(
          '/providers/me',
          body: <String, Object?>{'availabilityStatus': status.wireValue},
          parse: parseObject<ProviderProfile>(ProviderProfile.fromJson),
        );
    return envelope.requireData;
  }

  /// `POST /providers/me/submit` — opération 68, sans corps.
  ///
  /// Piloté par `canSubmit`, jamais par la checklist. Un 400 « dossier
  /// incomplet » porte `errors[].field` = les lignes à marquer en rouge
  /// (`ChecklistStep.fromSubmitError`) ; un 403 correspond à
  /// `resubmissionBlocked` — bouton retiré définitivement.
  Future<ProviderProfile> submit() async {
    final ApiEnvelope<ProviderProfile> envelope = await _client
        .post<ProviderProfile>(
          '/providers/me/submit',
          parse: parseObject<ProviderProfile>(ProviderProfile.fromJson),
        );
    return envelope.requireData;
  }

  // --- Catalogue public (P3, P5) --------------------------------------------------

  /// `GET /categories` — sélecteur à deux niveaux de P3. `data` est un tableau
  /// nu, sans pagination.
  Future<List<Category>> categories() async {
    final ApiEnvelope<List<Category>> envelope = await _client
        .get<List<Category>>(
          '/categories',
          parse: parseList<Category>(Category.fromJson),
        );
    return envelope.data ?? const <Category>[];
  }

  /// `GET /zones` — liste à cocher de P5, zones actives seulement.
  Future<List<Zone>> availableZones() async {
    final ApiEnvelope<List<Zone>> envelope = await _client.get<List<Zone>>(
      '/zones',
      parse: parseList<Zone>(Zone.fromJson),
    );
    return envelope.data ?? const <Zone>[];
  }

  // --- Offre (69 à 76) ------------------------------------------------------------

  /// `GET /providers/me/services` — opération 69, non paginé, formules imbriquées.
  Future<List<ProviderService>> services() async {
    final ApiEnvelope<List<ProviderService>> envelope = await _client
        .get<List<ProviderService>>(
          '/providers/me/services',
          parse: parseList<ProviderService>(ProviderService.fromJson),
        );
    return envelope.data ?? const <ProviderService>[];
  }

  /// `POST /providers/me/services` — opération 70.
  ///
  /// La réponse est la forme brute, sans packs : **retenir `id`**, c'est le
  /// `providerServiceId` exigé par la création de formule. Un 409 signifie qu'un
  /// service actif de ce type existe déjà — l'écran redirige vers lui plutôt que
  /// d'afficher l'erreur brute.
  Future<ProviderService> createService({
    required String serviceTypeId,
    required String title,
    String? description,
  }) async {
    final ApiEnvelope<ProviderService> envelope = await _client
        .post<ProviderService>(
          '/providers/me/services',
          body: <String, Object?>{
            'serviceTypeId': serviceTypeId,
            'title': title,
            'description': ?_nonEmpty(description),
          },
          parse: parseObject<ProviderService>(ProviderService.fromJson),
        );
    return envelope.requireData;
  }

  /// `PATCH /providers/me/services/{id}` — opération 71. `active: false`
  /// désactive ; il n'existe pas de suppression.
  Future<ProviderService> updateService(
    String serviceId, {
    String? title,
    String? description,
    bool? active,
  }) async {
    final ApiEnvelope<ProviderService> envelope = await _client
        .patch<ProviderService>(
          '/providers/me/services/$serviceId',
          body: <String, Object?>{
            'title': ?title,
            'description': ?description,
            'active': ?active,
          },
          parse: parseObject<ProviderService>(ProviderService.fromJson),
        );
    return envelope.requireData;
  }

  /// `POST /providers/me/service-packs` — opération 72, exige `providerServiceId`.
  ///
  /// C'est **cette** création qui fait passer la case `services` de la checklist
  /// au vert : un service sans formule ne compte pas (piège n°2 de P8).
  Future<ServicePack> createPack({
    required String providerServiceId,
    required String title,
    required num price,
    required int durationMinutes,
    String? description,
  }) async {
    final ApiEnvelope<ServicePack> envelope = await _client.post<ServicePack>(
      '/providers/me/service-packs',
      body: <String, Object?>{
        'providerServiceId': providerServiceId,
        'title': title,
        'description': ?_nonEmpty(description),
        'price': price,
        'durationMinutes': durationMinutes,
      },
      parse: parseObject<ServicePack>(ServicePack.fromJson),
    );
    return envelope.requireData;
  }

  /// `PATCH /providers/me/service-packs/{id}` — opération 73.
  Future<ServicePack> updatePack(
    String packId, {
    String? title,
    String? description,
    num? price,
    int? durationMinutes,
    bool? active,
  }) async {
    final ApiEnvelope<ServicePack> envelope = await _client.patch<ServicePack>(
      '/providers/me/service-packs/$packId',
      body: <String, Object?>{
        'title': ?title,
        'description': ?description,
        'price': ?price,
        'durationMinutes': ?durationMinutes,
        'active': ?active,
      },
      parse: parseObject<ServicePack>(ServicePack.fromJson),
    );
    return envelope.requireData;
  }

  /// `GET /providers/me/service-packs/{packId}/options` — opération 74, non
  /// paginé.
  Future<List<PackOption>> packOptions(String packId) async {
    final ApiEnvelope<List<PackOption>> envelope = await _client
        .get<List<PackOption>>(
          '/providers/me/service-packs/$packId/options',
          parse: parseList<PackOption>(PackOption.fromJson),
        );
    return envelope.data ?? const <PackOption>[];
  }

  /// `POST /providers/me/service-packs/{packId}/options` — opération 75, chemin
  /// **imbriqué**.
  Future<PackOption> createOption(
    String packId, {
    required String title,
    required num price,
    int? durationMinutes,
  }) async {
    final ApiEnvelope<PackOption> envelope = await _client.post<PackOption>(
      '/providers/me/service-packs/$packId/options',
      body: <String, Object?>{
        'title': title,
        'price': price,
        'durationMinutes': ?durationMinutes,
      },
      parse: parseObject<PackOption>(PackOption.fromJson),
    );
    return envelope.requireData;
  }

  /// `PATCH /providers/me/service-pack-options/{id}` — opération 76.
  ///
  /// ⚠️ Chemin **à plat**, sans le pack porteur — la seule route d'option qui ne
  /// soit pas imbriquée (api-consumption.md).
  Future<PackOption> updateOption(
    String optionId, {
    String? title,
    num? price,
    int? durationMinutes,
    bool? active,
  }) async {
    final ApiEnvelope<PackOption> envelope = await _client.patch<PackOption>(
      '/providers/me/service-pack-options/$optionId',
      body: <String, Object?>{
        'title': ?title,
        'price': ?price,
        'durationMinutes': ?durationMinutes,
        'active': ?active,
      },
      parse: parseObject<PackOption>(PackOption.fromJson),
    );
    return envelope.requireData;
  }

  // --- Zones et agenda (77 à 82) --------------------------------------------------

  /// `GET /providers/me/zones` — opération 77, pré-cochage de l'écran P5.
  Future<List<Zone>> myZones() async {
    final ApiEnvelope<List<Zone>> envelope = await _client.get<List<Zone>>(
      '/providers/me/zones',
      parse: parseList<Zone>(Zone.fromJson),
    );
    return envelope.data ?? const <Zone>[];
  }

  /// `PUT /providers/me/zones` — opération 78, **remplacement intégral**.
  ///
  /// Le contrôle serveur est atomique : une seule zone inconnue et rien n'est
  /// écrit (le 400 liste les fautives). Une liste vide est acceptée — c'est
  /// l'écran qui exige la confirmation avant de tout effacer (scénario 4.4).
  Future<ZonesUpdate> replaceZones(List<String> zoneIds) async {
    final ApiEnvelope<List<Zone>> envelope = await _client.put<List<Zone>>(
      '/providers/me/zones',
      body: <String, Object?>{'zoneIds': zoneIds},
      parse: parseList<Zone>(Zone.fromJson),
    );
    return ZonesUpdate(
      zones: envelope.data ?? const <Zone>[],
      message: envelope.message ?? 'Zones d’intervention mises à jour',
    );
  }

  /// `GET /providers/me/availabilities` — opération 79, miroir exact du PUT.
  Future<List<WeeklySlot>> availabilities() async {
    final ApiEnvelope<List<WeeklySlot>> envelope = await _client
        .get<List<WeeklySlot>>(
          '/providers/me/availabilities',
          parse: parseList<WeeklySlot>(WeeklySlot.fromJson),
        );
    return envelope.data ?? const <WeeklySlot>[];
  }

  /// `PUT /providers/me/availabilities` — opération 80, **remplacement intégral**,
  /// au plus 50 créneaux.
  ///
  /// Les heures partent **telles quelles** (`HH:MM`) : aucune conversion de
  /// fuseau, ni ici ni à l'affichage. Les contrôles locaux
  /// (`validateWeeklySlots`) ont déjà tourné à l'écran — le service reste
  /// l'autorité.
  Future<AvailabilitiesUpdate> replaceAvailabilities(
    List<WeeklySlot> slots,
  ) async {
    final ApiEnvelope<List<WeeklySlot>> envelope = await _client
        .put<List<WeeklySlot>>(
          '/providers/me/availabilities',
          body: <String, Object?>{
            'slots': <JsonMap>[
              for (final WeeklySlot slot in slots) slot.toJson(),
            ],
          },
          parse: parseList<WeeklySlot>(WeeklySlot.fromJson),
        );
    return AvailabilitiesUpdate(
      slots: envelope.data ?? const <WeeklySlot>[],
      message: envelope.message ?? 'Disponibilités mises à jour',
    );
  }

  /// `GET /providers/{id}/unavailabilities` — opération 29, la relecture de
  /// **mes** absences.
  ///
  /// La route est publique et exige l'identifiant du profil : il n'existe pas
  /// de `GET /providers/me/unavailabilities` — l'écran le prend sur l'aperçu
  /// du dossier.
  Future<List<Unavailability>> unavailabilities(String providerId) async {
    final ApiEnvelope<List<Unavailability>> envelope = await _client
        .get<List<Unavailability>>(
          '/providers/${Uri.encodeComponent(providerId)}/unavailabilities',
          parse: parseList<Unavailability>(Unavailability.fromJson),
        );
    return envelope.data ?? const <Unavailability>[];
  }

  /// `POST /providers/me/unavailabilities` — opération 81, bornes en UTC.
  Future<Unavailability> createUnavailability({
    required DateTime startAt,
    required DateTime endAt,
    String? reason,
  }) async {
    final ApiEnvelope<Unavailability> envelope = await _client
        .post<Unavailability>(
          '/providers/me/unavailabilities',
          body: <String, Object?>{
            'startAt': MissionDates.toApi(startAt),
            'endAt': MissionDates.toApi(endAt),
            'reason': ?_nonEmpty(reason),
          },
          parse: parseObject<Unavailability>(Unavailability.fromJson),
        );
    return envelope.requireData;
  }

  /// `DELETE /providers/me/unavailabilities/{id}` — opération 82, appartenance
  /// vérifiée par le service.
  Future<void> deleteUnavailability(String unavailabilityId) async {
    await _client.delete<void>(
      '/providers/me/unavailabilities/$unavailabilityId',
      parse: parseNothing(),
    );
  }

  // --- Justificatifs (83, 84) -----------------------------------------------------

  /// `GET /providers/me/documents` — opération 83, la vue d'écran complète.
  Future<ProviderDocumentsOverview> documents() async {
    final ApiEnvelope<ProviderDocumentsOverview> envelope = await _client
        .get<ProviderDocumentsOverview>(
          '/providers/me/documents',
          parse: parseStructured<ProviderDocumentsOverview>(
            ProviderDocumentsOverview.fromJson,
          ),
        );
    return envelope.requireData;
  }

  /// `POST /providers/me/documents` — opération 84, rattache un fichier déjà
  /// envoyé (`POST /files/upload`, visibilité forcée à `sensitive`).
  ///
  /// ⚠️ Effet de bord serveur : en `changes_requested`, ce seul dépôt repasse le
  /// dossier en `pending_review`. L'appelant **recharge l'aperçu** après chaque
  /// dépôt (FR-059) — c'est ce que fait l'écran P7 (T160).
  Future<ProviderDocument> attachDocument({
    required String type,
    required String fileId,
  }) async {
    final ApiEnvelope<ProviderDocument> envelope = await _client
        .post<ProviderDocument>(
          '/providers/me/documents',
          body: <String, Object?>{'type': type, 'fileId': fileId},
          parse: parseObject<ProviderDocument>(ProviderDocument.fromJson),
        );
    return envelope.requireData;
  }

  // --- Portfolio (85 à 88) --------------------------------------------------------

  /// `GET /providers/me/portfolio` — opération 85, non paginé, trié par ordre
  /// d'affichage.
  Future<List<PortfolioItem>> portfolio() async {
    final ApiEnvelope<List<PortfolioItem>> envelope = await _client
        .get<List<PortfolioItem>>(
          '/providers/me/portfolio',
          parse: parseList<PortfolioItem>(PortfolioItem.fromJson),
        );
    return envelope.data ?? const <PortfolioItem>[];
  }

  /// `POST /providers/me/portfolio` — opération 86.
  ///
  /// 20 réalisations au maximum, images uniquement — les deux refus sont des
  /// 400 exploitables, mais l'écran désactive l'ajout à 20 **avant** l'appel
  /// (scénario 8.3). Le fichier rattaché passe en visibilité `public`.
  Future<PortfolioItem> addPortfolioItem({
    required String fileId,
    String? title,
    String? description,
    int? displayOrder,
  }) async {
    final ApiEnvelope<PortfolioItem> envelope = await _client
        .post<PortfolioItem>(
          '/providers/me/portfolio',
          body: <String, Object?>{
            'fileId': fileId,
            'title': ?_nonEmpty(title),
            'description': ?_nonEmpty(description),
            'displayOrder': ?displayOrder,
          },
          parse: parseObject<PortfolioItem>(PortfolioItem.fromJson),
        );
    return envelope.requireData;
  }

  /// `PATCH /providers/me/portfolio/{id}` — opération 87.
  ///
  /// **Pas de changement d'image** : la route n'accepte aucun `fileId` —
  /// remplacer la photo, c'est retirer puis rajouter. Le réordonnancement
  /// passe par ici, élément par élément (`displayOrder` seul).
  Future<PortfolioItem> updatePortfolioItem(
    String itemId, {
    String? title,
    String? description,
    int? displayOrder,
  }) async {
    final ApiEnvelope<PortfolioItem> envelope = await _client
        .patch<PortfolioItem>(
          '/providers/me/portfolio/$itemId',
          body: <String, Object?>{
            'title': ?title,
            'description': ?description,
            'displayOrder': ?displayOrder,
          },
          parse: parseObject<PortfolioItem>(PortfolioItem.fromJson),
        );
    return envelope.requireData;
  }

  /// `DELETE /providers/me/portfolio/{id}` — opération 88.
  ///
  /// Le fichier est **ramené en `restricted`** : l'appelant purge le cache
  /// d'image local, l'URL publique ne sert plus rien (T215).
  Future<PortfolioRemoval> removePortfolioItem(String itemId) async {
    final ApiEnvelope<PortfolioRemoval> envelope = await _client
        .delete<PortfolioRemoval>(
          '/providers/me/portfolio/$itemId',
          parse: parseStructured<PortfolioRemoval>(PortfolioRemoval.fromJson),
        );
    return envelope.requireData;
  }
}

/// `null` pour une chaîne absente **ou** vide — le service traite les deux pareil,
/// autant ne rien envoyer.
String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

/// Résultat d'un remplacement de zones : la liste à jour et le message serveur,
/// affiché tel quel.
class ZonesUpdate {
  const ZonesUpdate({required this.zones, required this.message});

  final List<Zone> zones;
  final String message;
}

/// Résultat d'un remplacement d'agenda — même principe.
class AvailabilitiesUpdate {
  const AvailabilitiesUpdate({required this.slots, required this.message});

  final List<WeeklySlot> slots;
  final String message;
}

final Provider<ProviderSelfRepository> providerSelfRepositoryProvider =
    Provider<ProviderSelfRepository>(
      (Ref ref) => ProviderSelfRepository(ref.watch(apiClientProvider)),
    );
