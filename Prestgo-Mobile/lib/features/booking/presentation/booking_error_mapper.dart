// Refus métier → étape corrigeable (T116, FR-035).
//
// Quand une réservation est refusée pour un motif que l'utilisateur peut corriger, le
// ramener au début lui ferait tout ressaisir. On le ramène donc à **l'étape fautive**,
// le reste du brouillon intact.
//
// ⚠️ La correspondance se fait sur le **texte** du message, et c'est un compromis
// assumé : le service ne pose pas de code métier sur ces refus — son `errors[]` est
// vide, seul `message` porte l'information (écart n°13 du cahier des charges). Trois
// précautions en découlent :
//   • on reconnaît des **fragments stables**, pas des phrases entières, pour survivre
//     à une reformulation mineure ;
//   • le message affiché reste **celui du service**, jamais une reformulation locale :
//     lui seul porte les nombres interpolés (délai en vigueur, nombre de missions) ;
//   • l'absence de correspondance n'est pas un échec — le refus s'affiche sur le
//     récapitulatif, où l'utilisateur peut revenir sur n'importe quelle étape.

import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/features/booking/domain/booking_draft.dart';

/// Ce qu'il faut faire d'un refus.
class BookingCorrection {
  const BookingCorrection({
    required this.message,
    this.step,
    this.showsCoveredZones = false,
    this.isRecoverable = true,
  });

  /// Message du service, affiché tel quel (FR-088).
  final String message;

  /// Étape à rouvrir, ou `null` si le refus ne désigne pas d'étape précise.
  final BookingStep? step;

  /// Vrai quand l'écran doit rappeler les zones couvertes par le prestataire.
  ///
  /// Il les a déjà en mémoire depuis la fiche publique : les afficher évite à
  /// l'utilisateur de deviner quelle adresse conviendrait (scénario 2.8).
  final bool showsCoveredZones;

  /// Faux quand rien ne peut être corrigé dans ce brouillon — le prestataire ne
  /// prend plus de réservation, par exemple.
  final bool isRecoverable;

  /// Conseil affiché sous le message, quand l'étape le permet.
  String? get hint => switch (step) {
    BookingStep.schedule => 'Choisissez un autre créneau.',
    BookingStep.address =>
      showsCoveredZones
          ? 'Choisissez une adresse située dans une zone couverte.'
          : 'Choisissez une autre adresse.',
    BookingStep.pack => 'Vérifiez la formule et les options choisies.',
    _ => null,
  };
}

abstract final class BookingErrorMapper {
  /// Fragments reconnus, associés à leur étape.
  ///
  /// L'ordre compte : le premier fragment trouvé l'emporte, et les plus précis sont
  /// donc placés avant les plus généraux.
  static const List<(String, BookingStep)> _fragments = <(String, BookingStep)>[
    // --- Créneau -----------------------------------------------------------
    ('pas disponible sur ce créneau', BookingStep.schedule),
    ('déjà réservé', BookingStep.schedule),
    ('absent à cette date', BookingStep.schedule),
    ('à l\'avance', BookingStep.schedule),
    ('Date d\'intervention invalide', BookingStep.schedule),
    ('déjà une réservation en cours', BookingStep.schedule),

    // --- Adresse -----------------------------------------------------------
    ('zone d\'intervention', BookingStep.address),
    ('pas géolocalisée', BookingStep.address),
    ('Adresse introuvable', BookingStep.address),
    ('aucune zone d\'intervention', BookingStep.address),

    // --- Formule et options -------------------------------------------------
    ('Option inconnue', BookingStep.pack),
    ('Formule introuvable', BookingStep.pack),
  ];

  /// Interprète un refus.
  static BookingCorrection map(ApiException error) {
    final String message = error.message;

    // Un débit dépassé n'est pas corrigeable : il faut attendre, pas modifier.
    if (error.isRateLimited) {
      return BookingCorrection(message: message, isRecoverable: false);
    }

    // Le prestataire ne prend plus de réservation : aucune étape ne sauvera ce
    // brouillon.
    if (message.contains('ne prend pas de réservation') ||
        message.contains('Prestataire introuvable')) {
      return BookingCorrection(message: message, isRecoverable: false);
    }

    final String normalised = _normalise(message);
    for (final (String fragment, BookingStep step) in _fragments) {
      if (normalised.contains(_normalise(fragment))) {
        return BookingCorrection(
          message: message,
          step: step,
          showsCoveredZones: step == BookingStep.address,
        );
      }
    }

    // Refus non reconnu : il reste affichable, et le récapitulatif laisse revenir
    // sur n'importe quelle étape.
    return BookingCorrection(message: message);
  }

  /// Rend la comparaison insensible à la casse et à la forme de l'apostrophe.
  ///
  /// Le service écrit l'apostrophe droite ; une reformulation pourrait employer la
  /// typographique. Les distinguer ferait échouer la correspondance sur un détail
  /// invisible à la relecture.
  static String _normalise(String value) =>
      value.toLowerCase().replaceAll('’', "'");
}
