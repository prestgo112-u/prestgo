// Désactiver mon compte (T074, FR-012).
//
// Le vocabulaire est **« Désactiver »**, jamais « Supprimer », parce que rien n'est
// effacé : le statut passe à `deleted` et les données restent. Elles le doivent —
// les missions passées, les avis et les factures d'autres personnes référencent ce
// compte. Écrire « Supprimer » serait promettre quelque chose que le service ne fait
// pas, et la promesse compte autant que le geste.
//
// Double confirmation : case à cocher **et** mot de passe. La case dit « j'ai lu »,
// le mot de passe dit « c'est bien moi » — un jeton d'accès volé ne suffit pas.
//
// Le refus pour cause de mission en cours porte un décompte que le service seul
// connaît (« 2 mission(s) confirmée(s) ou en cours ») : il est affiché tel quel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/features/auth/presentation/auth_layout.dart';
import 'package:prestgo_mobile/features/profile/data/me_repository.dart';

class DeactivateAccountScreen extends ConsumerStatefulWidget {
  const DeactivateAccountScreen({super.key});

  @override
  ConsumerState<DeactivateAccountScreen> createState() =>
      _DeactivateAccountScreenState();
}

class _DeactivateAccountScreenState
    extends ConsumerState<DeactivateAccountScreen>
    with FormSubmissionMixin<DeactivateAccountScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _password = TextEditingController();

  bool _acknowledged = false;
  bool _hidden = true;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (!_acknowledged || !(_form.currentState?.validate() ?? false)) {
      return;
    }

    // Deuxième confirmation : le geste irréversible passe par une boîte de dialogue
    // dont l'action par défaut est l'annulation.
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Désactiver ce compte ?'),
            content: const Text(
              'Vous ne pourrez plus vous connecter. Vos missions passées et '
              'vos avis restent visibles pour les autres utilisateurs.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                ),
                child: const Text('Désactiver'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    final bool? done = await submit<bool>(() async {
      await ref.read(meRepositoryProvider).deactivate(password: _password.text);
      return true;
    });

    if (done == null || !mounted) {
      // Le message du service — décompte des missions bloquantes compris — est
      // déjà en bannière.
      return;
    }

    // Le service a révoqué toutes les sessions et désactivé les jetons push :
    // appeler `/auth/logout` n'aurait plus rien à fermer. Seule la purge locale
    // reste à faire.
    await ref.read(sessionControllerProvider.notifier).signOut();
    if (mounted) {
      context.go(Routes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return AuthLayout(
      title: 'Désactiver mon compte',
      error: formError,
      children: <Widget>[
        Card(
          margin: EdgeInsets.zero,
          color: theme.colorScheme.surfaceContainerHighest,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Ce qui est conservé'),
                SizedBox(height: 8),
                Text(
                  '• Vos missions passées et celles de vos prestataires\n'
                  '• Les avis que vous avez laissés et reçus\n'
                  '• Les échanges liés à vos missions',
                ),
                SizedBox(height: 16),
                Text('Ce qui change'),
                SizedBox(height: 8),
                Text(
                  '• Vous ne pouvez plus vous connecter\n'
                  '• Vous ne recevez plus de notifications\n'
                  '• Les données de cet appareil sont effacées',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'La désactivation est refusée tant qu’une mission est confirmée ou '
          'en cours. Terminez-la ou annulez-la d’abord.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _acknowledged,
          onChanged: (bool? value) =>
              setState(() => _acknowledged = value ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'J’ai compris que je ne pourrai plus me connecter à ce compte.',
          ),
        ),
        const SizedBox(height: 8),
        Form(
          key: _form,
          child: TextFormField(
            controller: _password,
            obscureText: _hidden,
            decoration: InputDecoration(
              labelText: 'Votre mot de passe',
              errorText: fieldErrors['password'],
              suffixIcon: IconButton(
                onPressed: () => setState(() => _hidden = !_hidden),
                icon: Icon(
                  _hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                tooltip: _hidden
                    ? 'Afficher le mot de passe'
                    : 'Masquer le mot de passe',
              ),
            ),
            validator: (String? value) => (value ?? '').isEmpty
                ? 'Saisissez votre mot de passe pour confirmer.'
                : null,
            onChanged: (_) => clearFieldError('password'),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _acknowledged && !isSubmitting ? _confirm : null,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: isSubmitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Text('Désactiver mon compte'),
        ),
      ],
    );
  }
}
