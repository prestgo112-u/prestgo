// Formateur monétaire **unique** (R11).
//
// La devise n'est portée par aucun champ de l'API : c'est une décision produit,
// centralisée ici. Le franc CFA n'a pas de sous-unité — aucun montant n'est affiché
// avec des décimales.

import 'package:intl/intl.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

abstract final class Money {
  /// Affiché à la place d'un montant absent.
  ///
  /// `quotedAmount` peut valoir `null` sur les missions antérieures au montant figé
  /// (data-model §5.1) : afficher « 0 XOF » laisserait croire à la gratuité.
  static const String absent = '—';

  static final NumberFormat _format = NumberFormat.currency(
    locale: AppFormats.locale,
    symbol: AppFormats.currencyCode,
    decimalDigits: AppFormats.currencyDecimalDigits,
  );

  /// Montant formaté — `12 500 XOF`.
  static String format(num amount) => _format.format(amount);

  /// Montant formaté, ou [absent] si le montant n'existe pas.
  static String formatOrAbsent(num? amount) =>
      amount == null ? absent : format(amount);

  /// Somme d'une formule et de ses options.
  ///
  /// Reproduit exactement le calcul du service : le total affiché avant
  /// confirmation doit être identique au montant figé retourné après réservation
  /// (scénario 2.5 de quickstart.md).
  static num total({
    required num packPrice,
    required Iterable<num> optionPrices,
  }) => optionPrices.fold<num>(packPrice, (num sum, num price) => sum + price);
}
