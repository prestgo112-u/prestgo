// Mon profil (T075, FR-016).
//
// Un contact non vérifié y est signalé **et** réparable : afficher la pastille sans
// proposer la vérification laisserait l'utilisateur devant un reproche sans issue.
// Le lien mène à l'écran de code, sur le bon canal — `sms` pour le téléphone,
// `email` pour l'adresse.
//
// L'ancienneté du compte n'est pas décorative : c'est un repère de confiance, et le
// seul endroit où `createdAt` est employé.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/auth/presentation/logout_action.dart';
import 'package:prestgo_mobile/features/auth/presentation/verify/verify_screen.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';
import 'package:prestgo_mobile/features/profile/presentation/role_switch.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Me?> profile = ref.watch(meControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil')),
      body: profile.when(
        loading: () => const LoadingView(label: 'Chargement du profil…'),
        error: (Object error, StackTrace _) => ErrorView(
          message: error is ApiException
              ? error.message
              : ApiFallbackMessages.unknown,
          onRetry: () => ref.read(meControllerProvider.notifier).reload(),
        ),
        data: (Me? me) => me == null
            ? const LoadingView()
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(meControllerProvider.notifier).reload(),
                child: _ProfileBody(me: me),
              ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        _Identity(me: me),
        const SizedBox(height: 24),

        const _SectionTitle('Mes contacts'),
        if (me.email case final String email)
          _ContactTile(
            icon: Icons.mail_outline,
            value: email,
            isVerified: me.emailVerified,
            onVerify: () => _verify(context, email, VerificationChannel.email),
          ),
        if (me.phone case final String phone)
          _ContactTile(
            icon: Icons.phone_outlined,
            value: phone,
            isVerified: me.phoneVerified,
            onVerify: () => _verify(context, phone, VerificationChannel.sms),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.profileEdit),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Modifier mes informations'),
        ),

        const SizedBox(height: 24),
        const _SectionTitle('Mon espace'),
        RoleSwitchTile(me: me),

        const SizedBox(height: 24),
        const _SectionTitle('Mon compte'),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: const Text('Mes adresses'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.addresses),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Changer mon mot de passe'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.profilePassword),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: const Text('Appareils connectés'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(Routes.devices),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _signOut(context, ref),
          icon: const Icon(Icons.logout),
          label: const Text('Me déconnecter'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.push(Routes.deactivateAccount),
          style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
          child: const Text('Désactiver mon compte'),
        ),
      ],
    );
  }

  void _verify(
    BuildContext context,
    String target,
    VerificationChannel channel,
  ) => context.push(
    Routes.verifyFor(
      target: target,
      // `sms` côté service, `phone_verification` côté OTP : le canal fait le pont.
      purpose: channel.otpPurpose,
      origin: VerificationOrigin.contactChange.name,
    ),
  );

  /// Même geste que celui des écrans d'atterrissage — confirmation comprise.
  ///
  /// Le partager évite deux formulations de la même mise en garde, et deux endroits
  /// à corriger le jour où la purge changera.
  Future<void> _signOut(BuildContext context, WidgetRef ref) =>
      confirmAndSignOut(context, ref);
}

class _Identity extends StatelessWidget {
  const _Identity({required this.me});

  final Me me;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        CircleAvatar(
          radius: 32,
          child: Text(_initials, style: theme.textTheme.titleLarge),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(me.displayName, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Membre depuis ${DateLabels.dayWithYear(me.createdAt)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String get _initials {
    final String first = me.firstName?.trim() ?? '';
    final String last = me.lastName?.trim() ?? '';
    final String initials =
        (first.isEmpty ? '' : first[0]) + (last.isEmpty ? '' : last[0]);
    return initials.isEmpty ? '?' : initials.toUpperCase();
  }
}

/// Contact, avec sa pastille de vérification et l'issue qui va avec.
class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.icon,
    required this.value,
    required this.isVerified,
    required this.onVerify,
  });

  final IconData icon;
  final String value;
  final bool isVerified;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(value),
      subtitle: isVerified
          ? null
          : Text(
              'Non vérifié',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
      trailing: isVerified
          ? Icon(Icons.verified_outlined, color: theme.colorScheme.primary)
          : TextButton(onPressed: onVerify, child: const Text('Vérifier')),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
      ),
    ),
  );
}
