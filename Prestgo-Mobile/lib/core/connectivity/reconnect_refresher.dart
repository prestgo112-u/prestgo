// Rafraîchissement automatique au retour du réseau (T235, FR-099).
//
// Le mécanisme est UNIQUE et par écran : chaque écran clé enveloppe son corps
// dans [RefreshOnReconnect] avec SA relecture — c'est l'écran courant qui se
// rafraîchit, pas une purge globale qui rechargerait tout ce que le conteneur
// porte encore.
//
// Seule la transition hors ligne → en ligne déclenche : ni le premier
// chargement (l'écran vient de lire), ni les répétitions d'état.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/core_providers.dart';

class RefreshOnReconnect extends ConsumerWidget {
  const RefreshOnReconnect({
    required this.onReconnect,
    required this.child,
    super.key,
  });

  /// La relecture de l'écran — typiquement des `ref.invalidate`.
  final VoidCallback onReconnect;

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<bool>>(isOnlineProvider, (
      AsyncValue<bool>? previous,
      AsyncValue<bool> next,
    ) {
      if (previous?.value == false && next.value == true) {
        onReconnect();
      }
    });
    return child;
  }
}
