// Écran de démarrage — la séquence de T064 rendue visible.
//
// Trois choses s'y passent, dans cet ordre :
//   1. les jetons sont relus dans le stockage sécurisé ;
//   2. le profil est chargé — cache d'abord, `GET /me` ensuite ;
//   3. le gardien, qui observe ces deux états, conduit vers l'atterrissage.
//
// Le troisième point explique pourquoi cet écran ne navigue jamais lui-même : la
// décision appartient au gardien unique, et lui seul connaît les sept branches du
// dossier prestataire.
//
// Le cas qui justifie l'écran d'erreur : `GET /me` échoue **et** aucun profil n'est
// en cache. Sans lui, le gardien renverrait indéfiniment vers ce même écran, et
// l'application resterait bloquée sur un indicateur qui tourne.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Après la première trame : `restore()` publie un état que le routeur observe,
    // et notifier pendant la construction du premier écran serait refusé.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(sessionControllerProvider.notifier).restore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // `watch` maintient le contrôleur en vie pendant tout le démarrage : sans lui,
    // rien ne déclencherait le chargement du profil.
    final AsyncValue<Me?> profile = ref.watch(meControllerProvider);

    return Scaffold(
      body: Center(
        child: profile.hasError
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: ErrorView(
                  message: switch (profile.error) {
                    final ApiException error => error.message,
                    _ => ApiFallbackMessages.unknown,
                  },
                  onRetry: () =>
                      ref.read(meControllerProvider.notifier).reload(),
                ),
              )
            : const SizedBox.square(
                dimension: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
      ),
    );
  }
}
