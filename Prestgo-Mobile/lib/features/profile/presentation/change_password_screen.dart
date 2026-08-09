// Changer mon mot de passe (T077, FR-018).
//
// Deux points qui distinguent cet écran de la réinitialisation :
//
//   • **la session courante survit** — le service épargne la session qui fait la
//     demande et ferme toutes les autres. L'utilisateur n'a donc pas à se
//     reconnecter, et c'est bien ce qu'on attend après avoir perdu un téléphone ;
//   • **le nombre de sessions fermées vient du service** — « 2 autre(s) session(s)
//     fermée(s) ». L'application ne sait pas les compter et n'essaie pas : le
//     message est affiché tel quel (FR-088).
//
// Un mot de passe actuel erroné répond **401**. Le dépôt marque donc la requête pour
// que l'intercepteur n'y voie pas une session expirée — sans quoi une faute de frappe
// déconnecterait.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/validation/validators.dart';
import 'package:prestgo_mobile/features/auth/presentation/auth_layout.dart';
import 'package:prestgo_mobile/features/auth/presentation/rate_limit_handler.dart';
import 'package:prestgo_mobile/features/profile/data/me_repository.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen>
    with FormSubmissionMixin<ChangePasswordScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();
  final ActionCooldown _cooldown = ActionCooldown();

  bool _hidden = true;

  @override
  void initState() {
    super.initState();
    _cooldown.addListener(_refresh);
  }

  @override
  void dispose() {
    _cooldown
      ..removeListener(_refresh)
      ..dispose();
    _current.dispose();
    _next.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _change() async {
    if (_cooldown.isActive || !(_form.currentState?.validate() ?? false)) {
      return;
    }

    final PasswordChangeResult? result = await submit<PasswordChangeResult>(
      () => ref
          .read(meRepositoryProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          ),
    );

    if (!mounted) {
      return;
    }
    if (result == null) {
      _cooldown.absorb(lastFailure);
      return;
    }

    // Message du service, chiffre compris.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
    context.pop();
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Changer mon mot de passe',
    subtitle:
        'Vos autres appareils seront déconnectés. Celui-ci reste connecté.',
    notice: _cooldown.isActive ? _cooldown.waitMessage : null,
    error: _cooldown.isActive ? null : formError,
    children: <Widget>[
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextFormField(
              controller: _current,
              obscureText: _hidden,
              decoration: InputDecoration(
                labelText: 'Mot de passe actuel',
                errorText: fieldErrors['currentPassword'],
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _hidden = !_hidden),
                  icon: Icon(
                    _hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  tooltip: _hidden
                      ? 'Afficher les mots de passe'
                      : 'Masquer les mots de passe',
                ),
              ),
              // Aucun contrôle de forme : le mot de passe existant peut être
              // antérieur aux règles actuelles.
              validator: (String? value) => (value ?? '').isEmpty
                  ? 'Renseignez votre mot de passe actuel.'
                  : null,
              onChanged: (_) => clearFieldError('currentPassword'),
            ),
            const Divider(height: 32),
            TextFormField(
              controller: _next,
              obscureText: _hidden,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
                errorText: fieldErrors['newPassword'],
              ),
              validator: Validators.password,
              onChanged: (_) => clearFieldError('newPassword'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmation,
              obscureText: _hidden,
              decoration: const InputDecoration(
                labelText: 'Confirmez le nouveau mot de passe',
              ),
              validator: (String? value) =>
                  Validators.passwordConfirmation(value, _next.text),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      AuthSubmitButton(
        label: 'Enregistrer',
        isBusy: isSubmitting,
        onPressed: _cooldown.isActive ? null : _change,
      ),
    ],
  );
}
