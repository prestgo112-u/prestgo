// Détection de connectivité et **verrou d'écriture** hors ligne (FR-097, US10).
//
// Règle non négociable : aucune écriture n'est acceptée hors ligne et **rien** n'est
// mis en file pour être rejoué plus tard. Une action différée qui partirait au
// retour du réseau, sur un créneau devenu indisponible ou une mission déjà annulée,
// produirait des effets que l'utilisateur n'a pas demandés.
//
// Les lectures, elles, continuent de servir le cache avec leur âge.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/core_providers.dart';

/// Levée quand une écriture est tentée sans connexion.
///
/// Les écrans ne devraient jamais la voir : le mécanisme unique de désactivation
/// (T234) rend l'action indisponible en amont. Elle reste le garde-fou de dernier
/// recours pour les chemins qui l'oublieraient.
class OfflineWriteBlocked implements Exception {
  const OfflineWriteBlocked([this.message = defaultMessage]);

  static const String defaultMessage =
      'Action indisponible hors ligne. Reconnectez-vous au réseau pour continuer.';

  final String message;

  @override
  String toString() => 'OfflineWriteBlocked($message)';
}

/// Source de vérité de l'état réseau de l'application.
class OfflineGate {
  OfflineGate({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// Vrai dès qu'au moins un transport est disponible.
  ///
  /// La connectivité du système ne garantit pas que le service réponde : c'est un
  /// filtre d'ergonomie, pas une preuve de joignabilité. Les erreurs réseau
  /// réelles restent traitées par `ApiException.isNetwork`.
  static bool isOnlineFrom(List<ConnectivityResult> results) =>
      results.any((ConnectivityResult r) => r != ConnectivityResult.none);

  /// État courant.
  ///
  /// Un greffon muet (plateforme de test, environnement sans connectivité
  /// native) vaut EN LIGNE : bloquer des écritures sur une incertitude serait
  /// pire que laisser le service répondre.
  Future<bool> isOnline() async {
    try {
      return isOnlineFrom(await _connectivity.checkConnectivity());
    } on Object {
      return true;
    }
  }

  /// Changements d'état, sans répétition. Les erreurs du greffon sont
  /// avalées : mieux vaut une bannière qui ne s'affiche jamais qu'un flux en
  /// erreur qui casse tous les écrans qui l'écoutent.
  Stream<bool> onlineChanges() => _connectivity.onConnectivityChanged
      .map(isOnlineFrom)
      .handleError((Object _) {})
      .distinct();

  /// Exécute [action] seulement si le réseau est disponible.
  ///
  /// Ne met **rien** en file : un refus est définitif, l'utilisateur relance
  /// l'action lui-même une fois reconnecté.
  Future<T> guardWrite<T>(
    Future<T> Function() action, {
    String? message,
  }) async {
    if (!await isOnline()) {
      throw OfflineWriteBlocked(message ?? OfflineWriteBlocked.defaultMessage);
    }
    return action();
  }
}

/// Le mécanisme **unique** de désactivation des écritures hors ligne (T234).
///
/// Chaque action d'écriture des écrans clés passe par ici : le bouton reçoit
/// `canWrite == false` hors ligne — donc `onPressed: null` — et l'explication
/// s'affiche dessous. RIEN n'est mis en file : le bouton fermé ne mémorise
/// aucun geste, l'utilisateur relance lui-même une fois reconnecté.
class OfflineWriteGuard extends ConsumerWidget {
  const OfflineWriteGuard({
    required this.builder,
    super.key,
    this.explanation = OfflineWriteBlocked.defaultMessage,
  });

  /// Construit l'action ; `canWrite` est faux hors ligne.
  final Widget Function(BuildContext context, bool canWrite) builder;

  final String explanation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Un état réseau inconnu vaut en ligne : filtre d'ergonomie, pas preuve.
    final bool online = ref.watch(isOnlineProvider).value ?? true;
    if (online) {
      return builder(context, true);
    }

    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        builder(context, false),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            explanation,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
