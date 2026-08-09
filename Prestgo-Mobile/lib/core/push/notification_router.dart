// Routage UNIQUE des notifications — internes et poussées (T203, FR-083).
//
// Une seule fonction d'ouverture sert le tap sur une notification du centre, le
// tap sur un push (arrière-plan), le message initial (application tuée) et la
// bannière locale du premier plan : tous transportent la même charge utile.
//
// La **destination différée** est le cas de l'application tuée, ouverte par une
// notification : le routeur go_router existe avant que la session soit restaurée
// et le profil chargé — naviguer immédiatement ferait rebondir le gardien vers
// l'écran de démarrage et perdrait la destination. Elle attend donc [isReady] et
// part **une seule fois**, au premier aiguillage.
//
// La résolution du chemin est **injectée** : le socle ne connaît pas la table des
// routes (`lib/app/routes.dart` lui est interdit) — c'est la couche applicative
// qui fournit la correspondance charge utile → chemin.

import 'package:prestgo_mobile/core/push/notification_payload.dart';

class NotificationRouter {
  NotificationRouter({
    required this.resolvePath,
    required this.navigate,
    required this.isReady,
  });

  /// Correspondance charge utile → chemin, fournie par la couche applicative.
  final String Function(NotificationPayload payload) resolvePath;

  /// Navigation effective — `GoRouter.push` en production.
  final void Function(String location) navigate;

  /// Vrai quand la session et le profil permettent de naviguer.
  final bool Function() isReady;

  String? _pending;

  /// Destination en attente d'aiguillage, s'il y en a une.
  String? get pendingDestination => _pending;

  /// Ouvre l'écran désigné par [data] — ou le met en attente de session.
  ///
  /// Une nouvelle notification remplace la destination en attente : seule la
  /// dernière intention de l'utilisateur compte.
  void open(Map<Object?, Object?>? data) {
    final String destination = resolvePath(NotificationPayload.parse(data));
    if (isReady()) {
      _pending = null;
      navigate(destination);
    } else {
      _pending = destination;
    }
  }

  /// Fait partir la destination différée, une seule fois.
  ///
  /// À appeler quand l'aiguillage devient possible (profil chargé). Sans
  /// destination en attente, l'appel est sans effet.
  void flushPending() {
    final String? destination = _pending;
    if (destination == null || !isReady()) {
      return;
    }
    _pending = null;
    navigate(destination);
  }
}
