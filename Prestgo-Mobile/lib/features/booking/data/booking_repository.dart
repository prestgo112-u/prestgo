// Réservation — opération 31 (T097).
//
// La séquence de confirmation du §3 de contracts/retry-and-idempotency.md est
// répartie entre trois endroits, et il vaut la peine de dire lequel fait quoi :
//
//   • **la clé** est tenue par le contrôleur de brouillon (T110) : elle est émise une
//     fois à l'affichage du récapitulatif et suit le contenu, pas l'appel ;
//   • **le rejeu réseau** (2 tentatives, 1 s puis 3 s) est celui du socle :
//     `RetryPolicy` classe `POST /missions` en `RequestKind.booking`. L'intercepteur
//     rejoue la même `RequestOptions`, donc le même en-tête `Idempotency-Key` —
//     c'est ce qui rend le rejeu sûr ;
//   • **la boucle sur 409 « déjà en cours de traitement »** est ici. Le socle ne la
//     couvre pas, et ne le doit pas : un 409 n'est pas une erreur transitoire au sens
//     réseau, c'est une réponse qui dit « attends ». La traiter dans la politique de
//     rejeu générique en ferait un cas particulier au mauvais niveau.
//
// ⚠️ Un 409 ici ne doit **jamais** être présenté comme une erreur : la première
// requête est probablement en train d'aboutir.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_client.dart';
import 'package:prestgo_mobile/core/api/api_envelope.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/api/idempotency.dart';
import 'package:prestgo_mobile/features/booking/domain/booked_mission.dart';

/// Comment le service a répondu à une confirmation réussie.
enum BookingOutcome {
  /// 201 — la mission vient d'être créée.
  created,

  /// 200 — une clé rejouée a rendu la mission déjà enregistrée. **C'est un succès**
  /// (FR-034) : le premier appel était passé, la coupure réseau n'a fait perdre que
  /// la réponse.
  alreadyRecorded,
}

class BookingConfirmation {
  const BookingConfirmation({required this.mission, required this.outcome});

  final BookedMission mission;
  final BookingOutcome outcome;

  bool get wasAlreadyRecorded => outcome == BookingOutcome.alreadyRecorded;
}

/// Levée quand le service répond 409 plus longtemps que la boucle ne patiente.
///
/// N'est **pas** une erreur d'affichage : l'écran recharge la liste des missions,
/// où la réservation se trouve très probablement.
class BookingStillProcessing implements Exception {
  const BookingStillProcessing(this.lastFailure);

  final ApiException lastFailure;

  @override
  String toString() => 'BookingStillProcessing(${lastFailure.message})';
}

class BookingRepository {
  const BookingRepository(this._client, {this.pause = _defaultPause});

  /// Attente entre deux tentatives sur un 409. Injectable pour les tests, qui ne
  /// doivent pas patienter deux secondes.
  final Future<void> Function(Duration delay) pause;

  final ApiClient _client;

  static Future<void> _defaultPause(Duration delay) =>
      Future<void>.delayed(delay);

  /// Attente prescrite entre deux tentatives sur un 409 (§3 du contrat).
  static const Duration inFlightDelay = Duration(seconds: 2);

  /// Nombre de reprises sur 409, au-delà desquelles on recharge les missions.
  static const int inFlightAttempts = 2;

  /// `POST /missions`, un seul appel.
  ///
  /// Le rejeu réseau reste à la charge du socle : cette méthode ne rattrape rien.
  Future<BookingConfirmation> create({
    required JsonMap body,
    required String idempotencyKey,
  }) async {
    final ApiEnvelope<BookedMission> envelope = await _client
        .post<BookedMission>(
          '/missions',
          body: body,
          headers: <String, String>{kIdempotencyKeyHeader: idempotencyKey},
          parse: parseObject<BookedMission>(BookedMission.fromJson),
        );

    return BookingConfirmation(
      mission: envelope.requireData,
      // `isCreated` porte le sens ; le code lui-même reste dans le socle (porte G2).
      outcome: (envelope.isCreated ?? true)
          ? BookingOutcome.created
          : BookingOutcome.alreadyRecorded,
    );
  }

  /// Confirmation complète, boucle sur 409 comprise.
  ///
  /// Ce que cette méthode ne fait **pas**, et ne doit pas faire :
  ///   • réessayer un 400 métier — le contenu doit changer d'abord, et une clé neuve
  ///     sera émise (§3, étape 4) ;
  ///   • réessayer un 429 — cela ne ferait qu'aggraver le débit (porte G4).
  /// Les deux remontent tels quels à l'écran, qui ramène à l'étape fautive.
  Future<BookingConfirmation> confirm({
    required JsonMap body,
    required String idempotencyKey,
  }) async {
    ApiException? lastConflict;

    for (int attempt = 0; attempt <= inFlightAttempts; attempt++) {
      try {
        return await create(body: body, idempotencyKey: idempotencyKey);
      } on ApiException catch (error) {
        if (!error.isConflict) {
          rethrow;
        }
        // 409 : la requête d'origine est encore en vol. On patiente et on
        // repropose **la même clé** — surtout pas une nouvelle, qui créerait une
        // seconde mission.
        lastConflict = error;
        if (attempt < inFlightAttempts) {
          await pause(inFlightDelay);
        }
      }
    }

    throw BookingStillProcessing(lastConflict!);
  }
}

final Provider<BookingRepository> bookingRepositoryProvider =
    Provider<BookingRepository>(
      (Ref ref) => BookingRepository(ref.watch(apiClientProvider)),
    );
