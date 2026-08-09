// Bascule entre espace client et espace prestataire (T078, FR-014).
//
// Un compte prestataire **reste** un compte client : il a des adresses, il peut
// réserver, il a des missions à lui. La bascule ne change donc ni la session ni les
// jetons — elle change de route, rien de plus. C'est pourquoi le gardien laisse
// passer les routes client pour un prestataire approuvé.
//
// Ce que cet élément n'est pas : un sélecteur de rôle. Il n'y a pas de « mode »
// mémorisé quelque part ; l'espace ouvert est celui de la route courante.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';

/// Entrée vers l'autre espace, ou vers le parcours « devenir prestataire ».
///
/// Rend `null` quand il n'y a rien à proposer : compte inactif, ou dossier en cours
/// de vérification dont le suivi est déjà accessible depuis l'écran d'atterrissage.
class RoleSwitchTile extends ConsumerWidget {
  const RoleSwitchTile({required this.me, super.key});

  final Me me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!me.status.isActive) {
      return const SizedBox.shrink();
    }

    final bool onProviderSide = Routes.isProviderSpace(
      GoRouterState.of(context).uri.path,
    );

    if (!me.hasProviderProfile) {
      return _Tile(
        icon: Icons.handyman_outlined,
        title: 'Devenir prestataire',
        subtitle: 'Proposez vos services et recevez des demandes.',
        onTap: () => context.push(Routes.providerOnboarding),
      );
    }

    final ProviderValidationStatus? validation = me.providerValidationStatus;
    if (!(validation?.opensProviderSpace ?? false)) {
      return _Tile(
        icon: Icons.pending_actions_outlined,
        title: 'Suivi de mon dossier prestataire',
        subtitle: _statusLabel(validation),
        onTap: () => context.push(Routes.providerStatus),
      );
    }

    return onProviderSide
        ? _Tile(
            icon: Icons.shopping_bag_outlined,
            title: 'Passer à l’espace client',
            subtitle: 'Réserver, suivre mes demandes.',
            onTap: () => context.go(Routes.clientHome),
          )
        : _Tile(
            icon: Icons.dashboard_outlined,
            title: 'Passer à l’espace prestataire',
            subtitle: 'Mon planning, mes demandes, mon offre.',
            onTap: () => context.go(Routes.providerDashboard),
          );
  }

  static String _statusLabel(ProviderValidationStatus? validation) =>
      switch (validation) {
        ProviderValidationStatus.pendingReview => 'Dossier en cours d’examen.',
        ProviderValidationStatus.changesRequested =>
          'Des corrections sont attendues.',
        ProviderValidationStatus.rejected => 'Dossier refusé.',
        ProviderValidationStatus.suspended => 'Dossier suspendu.',
        ProviderValidationStatus.profileIncomplete ||
        ProviderValidationStatus.approved ||
        null => 'Dossier à compléter.',
      };
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
