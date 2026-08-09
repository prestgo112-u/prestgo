// Dépassement de débit sur les écrans d'authentification (T079, FR-089).
//
// Le service serre le débit là où ça compte : 10 connexions par minute, 5 inscriptions
// ou envois de code, 30 renouvellements. Quand le plafond tombe, la seule réponse
// correcte est **d'attendre** : rejouer ne ferait qu'aggraver le compteur, et
// l'utilisateur verrait le même refus plus longtemps (porte G4).
//
// D'où ce compte à rebours : le bouton se ferme, la durée restante s'affiche, et il
// se rouvre tout seul. Aucune reprise automatique n'est déclenchée à l'expiration —
// c'est l'utilisateur qui décide de réessayer.
//
// La même mécanique sert au renvoi de code, limité par l'application à un par minute
// pour ne pas atteindre le plafond du service dès le troisième essai.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';

/// Compte à rebours pendant lequel une action reste fermée.
class ActionCooldown extends ChangeNotifier {
  ActionCooldown({Duration? duration})
    : _duration = duration ?? const Duration(minutes: 1);

  final Duration _duration;
  Timer? _ticker;
  DateTime? _openAt;

  /// Temps restant, arrondi à la seconde supérieure.
  Duration get remaining {
    final DateTime? openAt = _openAt;
    if (openAt == null) {
      return Duration.zero;
    }
    final Duration left = openAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  bool get isActive => remaining > Duration.zero;

  /// Ferme l'action pour la durée configurée.
  void start([Duration? duration]) {
    _openAt = DateTime.now().add(duration ?? _duration);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!isActive) {
        timer.cancel();
        _ticker = null;
        _openAt = null;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  /// Rouvre immédiatement — après une connexion réussie, par exemple.
  void reset() {
    _ticker?.cancel();
    _ticker = null;
    _openAt = null;
    notifyListeners();
  }

  /// Ferme l'action **si** [error] est un dépassement de débit, et le signale.
  ///
  /// Renvoyer un booléen laisse l'appelant décider du reste : sur un écran de
  /// connexion, un 429 ne se présente pas comme un identifiant erroné.
  bool absorb(ApiException? error) {
    if (error == null || !error.isRateLimited) {
      return false;
    }
    start();
    return true;
  }

  /// Message d'attente, avec le temps restant.
  ///
  /// Le message du service (« Trop de tentatives en peu de temps. Merci de réessayer
  /// dans une minute. ») ne dit pas *combien* de temps il reste réellement : celui-ci
  /// se met à jour à chaque seconde.
  String get waitMessage {
    final int seconds = remaining.inSeconds;
    if (seconds <= 0) {
      return ApiFallbackMessages.rateLimited;
    }
    if (seconds < 60) {
      return 'Trop de tentatives. Réessayez dans $seconds seconde'
          '${seconds > 1 ? 's' : ''}.';
    }
    final int minutes = (seconds / 60).ceil();
    return 'Trop de tentatives. Réessayez dans $minutes minute'
        '${minutes > 1 ? 's' : ''}.';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

/// Compte à rebours du renvoi de code — un par minute (`AuthLimits`).
ActionCooldown resendCooldown() =>
    ActionCooldown(duration: AuthLimits.verificationResendCooldown);
