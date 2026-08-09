// Mur d'authentification (T117, FR-028, scénario 2.4).
//
// Deux murs coexistent, et ils ne servent pas à la même chose :
//
//   • **celui du gardien** (`resolveRedirect`) intercepte l'accès à une route
//     protégée — un lien profond, un retour d'historique. Il mémorise la route
//     demandée et y ramène après connexion ;
//   • **celui-ci**, au niveau du geste. Une fiche prestataire est publique, mais
//     « Réserver » et « Mettre en favori » exigent un compte. Laisser le gardien s'en
//     charger ferait quitter la fiche pour une route protégée, puis y revenir : le
//     retour se ferait sur la réservation, pas sur la fiche que l'utilisateur
//     regardait. Le scénario 2.4 demande explicitement le retour **sur la fiche**.
//
// D'où la règle : on mémorise la route **courante**, pas celle qu'on allait ouvrir.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';

/// Vrai si une session est ouverte ; sinon, ouvre la connexion et renvoie faux.
///
/// L'appelant s'arrête sur `false` :
///
/// ```dart
/// if (!requireSession(context, ref)) return;
/// ```
bool requireSession(BuildContext context, WidgetRef ref) {
  if (ref.read(sessionControllerProvider).isAuthenticated) {
    return true;
  }

  // Route courante avec ses paramètres : c'est là qu'on reviendra.
  final String origin = GoRouterState.of(context).uri.toString();

  // ⚠️ `go`, et surtout pas `push`. Empiler la connexion au-dessus de la fiche
  // laisserait le gardien évaluer la route de **base** — la fiche — qu'il détourne
  // vers l'écran de démarrage dès que la session s'ouvre, faute de profil chargé.
  // L'écran de connexion empilé disparaît alors au milieu de sa séquence, et la
  // route mémorisée avec lui. En remplaçant la pile, l'adresse devient
  // `/login?from=…` : le gardien la voit, la laisse en place le temps du
  // chargement, puis y lit la destination (FR-028, scénario 2.4).
  context.go(Routes.loginWithRedirect(origin));
  return false;
}
