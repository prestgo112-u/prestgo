// Ouverture de session — le geste commun aux trois chemins de connexion.
//
// Connexion par mot de passe, connexion par code, connexion automatique après
// activation : tous trois obtiennent un couple de jetons puis doivent faire
// exactement la même chose. Le regrouper ici évite qu'un des trois oublie une étape —
// typiquement le chargement du profil, sans lequel le gardien reste bloqué sur
// l'écran de démarrage.
//
// L'ordre est imposé : jetons **d'abord**, profil ensuite. `GET /me` exige l'en-tête
// d'autorisation, que l'intercepteur ne pose qu'à partir des jetons stockés.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';

/// Enregistre les jetons puis charge le profil.
///
/// Ne lève pas : un profil illisible laisse le gardien sur l'écran de démarrage avec
/// l'erreur dans l'état du contrôleur, ce qui est plus juste que de faire échouer la
/// connexion elle-même — la session, elle, est bel et bien ouverte.
Future<Me?> openSession(WidgetRef ref, {required AuthTokens tokens}) async {
  await ref.read(sessionControllerProvider.notifier).signIn(tokens);

  // ⚠️ Charger **explicitement**, et non attendre le rechargement que le contrôleur
  // déclenche en observant la session. La nuance a des conséquences visibles : ce
  // rechargement-là est asynchrone, et `read(…future)` juste après peut rendre le
  // futur *précédent* — celui qui valait `null` faute de session. L'appelant croit
  // alors le profil chargé, navigue, et le gardien — qui voit encore un profil nul —
  // le détourne vers l'écran de démarrage puis vers l'atterrissage. La route
  // mémorisée est perdue, sans qu'aucune erreur ne le signale.
  //
  // `reload()` publie un état résolu avant de rendre la main : la navigation qui
  // suit se fait sur un profil réellement connu.
  try {
    await ref.read(meControllerProvider.notifier).reload();
    return ref.read(meControllerProvider).value;
  } on ApiException {
    return null;
  }
}
