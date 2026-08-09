// Brouillon de réservation et **cycle de vie de la clé d'idempotence** (T110, FR-033).
//
// La règle, telle que la formule le §2 du contrat :
//
//   > la clé est un UUID v4 généré **une seule fois**, à l'affichage du récapitulatif,
//   > et réutilisée par toutes les confirmations — y compris les rejeux après coupure
//   > réseau. Une nouvelle clé n'est émise que si le **contenu** change.
//
// ⚠️ La clé n'est jamais demandée depuis une méthode de construction de widget :
// chaque reconstruction en produirait une neuve et annulerait la protection. Elle est
// émise ici, dans un contrôleur, depuis [prepareSummary] — appelée à l'ouverture du
// récapitulatif — et relue par [confirm].
//
// `IdempotencyKeyHolder` fait le reste : même empreinte, même clé ; empreinte
// différente, clé neuve. C'est pourquoi toute modification du brouillon suffit à en
// déclencher une (scénario 2.10), sans qu'aucun écran ait à y penser.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/idempotency.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/features/booking/data/booking_repository.dart';
import 'package:prestgo_mobile/features/booking/domain/booked_mission.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_draft.dart';
import 'package:prestgo_mobile/features/booking/presentation/booking_error_mapper.dart';
import 'package:prestgo_mobile/features/profile/domain/address.dart';
import 'package:prestgo_mobile/features/search/domain/provider_profile.dart';

/// Où en est la confirmation.
enum BookingPhase {
  /// L'utilisateur compose sa réservation.
  composing,

  /// Appel en cours — y compris pendant l'attente sur un 409, où l'indicateur
  /// **reste affiché** : la première requête est probablement en train d'aboutir.
  confirming,

  /// Réservation enregistrée.
  confirmed,

  /// Refusée pour un motif corrigeable, ou trop longtemps en traitement.
  failed,
}

class BookingState {
  const BookingState({
    required this.draft,
    this.phase = BookingPhase.composing,
    this.correction,
    this.mission,
    this.wasAlreadyRecorded = false,
    this.isStillProcessing = false,
  });

  final BookingDraft draft;
  final BookingPhase phase;

  /// Refus interprété : étape à rouvrir et message du service.
  final BookingCorrection? correction;

  /// Mission créée, une fois la confirmation aboutie.
  final BookedMission? mission;

  /// Vrai quand le service a rendu une réservation **déjà enregistrée** : c'est un
  /// succès, avec un mot différent à l'écran.
  final bool wasAlreadyRecorded;

  /// Vrai quand le service a répondu « déjà en cours de traitement » plus longtemps
  /// que la boucle ne patiente. L'écran renvoie alors vers les missions, où la
  /// réservation se trouve très probablement — il n'affiche pas d'erreur.
  final bool isStillProcessing;

  bool get isConfirming => phase == BookingPhase.confirming;
  bool get isConfirmed => phase == BookingPhase.confirmed;

  BookingState copyWith({
    BookingDraft? draft,
    BookingPhase? phase,
    BookingCorrection? correction,
    BookedMission? mission,
    bool? wasAlreadyRecorded,
    bool? isStillProcessing,
    bool clearCorrection = false,
  }) => BookingState(
    draft: draft ?? this.draft,
    phase: phase ?? this.phase,
    correction: clearCorrection ? null : correction ?? this.correction,
    mission: mission ?? this.mission,
    wasAlreadyRecorded: wasAlreadyRecorded ?? this.wasAlreadyRecorded,
    isStillProcessing: isStillProcessing ?? this.isStillProcessing,
  );
}

class BookingDraftController extends Notifier<BookingState?> {
  /// Porte la clé courante. Vit avec le contrôleur, donc avec le brouillon — pas
  /// avec un widget.
  final IdempotencyKeyHolder _keys = IdempotencyKeyHolder();

  @override
  BookingState? build() => null;

  /// Clé actuellement émise — exposée pour les tests et le suivi réseau.
  IdempotencyKey? get currentKey => _keys.current;

  /// Ouvre un brouillon pour un prestataire.
  ///
  /// Repartir d'un nouveau brouillon abandonne la clé : le contenu n'a plus rien à
  /// voir avec celui qu'elle protégeait.
  void start(ProviderPublicProfile provider) {
    _keys.reset();
    state = BookingState(draft: BookingDraft(provider: provider));
  }

  void _mutate(BookingDraft Function(BookingDraft draft) transform) {
    final BookingState? current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(
      draft: transform(current.draft),
      phase: BookingPhase.composing,
      clearCorrection: true,
    );
  }

  void selectPack(ServicePack pack) =>
      _mutate((BookingDraft draft) => draft.withPack(pack));

  void toggleOption(String optionId) =>
      _mutate((BookingDraft draft) => draft.toggleOption(optionId));

  void selectSchedule(DateTime scheduledAt) =>
      _mutate((BookingDraft draft) => draft.copyWith(scheduledAt: scheduledAt));

  void selectAddress(Address address) =>
      _mutate((BookingDraft draft) => draft.copyWith(address: address));

  void setInstructions(String? instructions) => _mutate(
    (BookingDraft draft) => draft.copyWith(
      instructions: instructions,
      clearInstructions: instructions == null || instructions.trim().isEmpty,
    ),
  );

  /// Délai minimum en vigueur, lu auprès du service au démarrage (porte G3).
  int get minLeadTimeMinutes =>
      ref.read(publicSettingsProvider).missionMinLeadTimeMinutes;

  /// Émet — ou réutilise — la clé du contenu courant.
  ///
  /// À appeler **à l'affichage** du récapitulatif, jamais depuis un `build`. Deux
  /// appels sur le même contenu renvoient la même clé ; le premier appel après une
  /// modification en émet une neuve.
  IdempotencyKey prepareSummary() {
    final BookingState current = state!;
    return _keys.keyFor(current.draft.fingerprint);
  }

  /// Confirme la réservation.
  ///
  /// Applique la séquence du §3 du contrat : la boucle sur 409 est dans le dépôt,
  /// le rejeu réseau dans le socle, et l'interprétation du refus ici.
  Future<void> confirm() async {
    final BookingState? current = state;
    if (current == null || current.isConfirming) {
      return;
    }

    final IdempotencyKey key = prepareSummary();
    state = current.copyWith(
      phase: BookingPhase.confirming,
      clearCorrection: true,
      isStillProcessing: false,
    );

    try {
      final BookingConfirmation confirmation = await ref
          .read(bookingRepositoryProvider)
          .confirm(
            body: current.draft.toRequestBody(),
            idempotencyKey: key.value,
          );

      // Succès : la clé a fait son office et n'a plus de raison d'exister.
      _keys.reset();
      state = current.copyWith(
        phase: BookingPhase.confirmed,
        mission: confirmation.mission,
        wasAlreadyRecorded: confirmation.wasAlreadyRecorded,
      );
    } on BookingStillProcessing {
      // Ni succès ni erreur : la première requête est encore en vol. L'écran
      // renvoie vers les missions plutôt que d'annoncer un échec.
      state = current.copyWith(
        phase: BookingPhase.failed,
        isStillProcessing: true,
      );
    } on ApiException catch (error) {
      // Refus métier : le service a **libéré** la clé de son côté. L'utilisateur
      // corrige, ce qui change l'empreinte, et une clé neuve sera émise au retour
      // sur le récapitulatif.
      state = current.copyWith(
        phase: BookingPhase.failed,
        correction: BookingErrorMapper.map(error),
      );
    }
  }

  /// Referme le refus pour revenir à la composition.
  void dismissCorrection() {
    final BookingState? current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(
      phase: BookingPhase.composing,
      clearCorrection: true,
      isStillProcessing: false,
    );
  }

  /// Abandonne le brouillon **et** sa clé.
  void clear() {
    _keys.reset();
    state = null;
  }
}

final NotifierProvider<BookingDraftController, BookingState?>
bookingDraftProvider = NotifierProvider<BookingDraftController, BookingState?>(
  BookingDraftController.new,
);
