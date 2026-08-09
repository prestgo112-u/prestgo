// Déconnexion — le geste, en un seul endroit.
//
// Tout écran d'atterrissage doit permettre de quitter la session : le tableau de bord
// prestataire, le suivi de dossier, la checklist et l'accueil client. Sans ce point
// commun, trois parcours sur quatre enfermaient l'utilisateur — il ne pouvait changer
// de compte qu'en vidant les données de l'application depuis les réglages Android.
//
// La confirmation n'est pas une politesse : la déconnexion purge le cache local
// (SC-012), et tout ce qui était consultable hors ligne disparaît avec elle. Le
// message le dit, plutôt que de laisser la surprise à l'utilisateur.
//
// `auth` étant commune aux deux surfaces, les écrans client comme prestataire
// peuvent s'y référer sans franchir la frontière de la porte G5.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/features/auth/presentation/logout_controller.dart';

/// Action de barre de titre — à poser dans `AppBar.actions`.
class LogoutAction extends ConsumerWidget {
  const LogoutAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    icon: const Icon(Icons.logout),
    tooltip: 'Me déconnecter',
    onPressed: () => confirmAndSignOut(context, ref),
  );
}

/// Demande confirmation, ferme la session, puis ramène à la connexion.
///
/// Ne fait rien si l'utilisateur renonce. Le retour à `/login` est demandé
/// explicitement : le gardien y conduirait de lui-même, mais l'attendre laisserait
/// l'écran courant affiché le temps que la fin de session se propage.
Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final bool confirmed =
      await showDialog<bool>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: const Text('Me déconnecter ?'),
          content: const Text(
            'Vos données hors ligne seront effacées de cet appareil.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Me déconnecter'),
            ),
          ],
        ),
      ) ??
      false;

  if (!confirmed) {
    return;
  }
  await ref.read(logoutControllerProvider).signOut();
  if (context.mounted) {
    context.go(Routes.login);
  }
}
