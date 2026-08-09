// Réinitialisation du mot de passe (T072, FR-010).
//
// Le jeton fait 64 caractères hexadécimaux et arrive par email : personne ne le
// retape. D'où le champ multiligne et le bouton « Coller » — sans eux, cet écran
// serait inutilisable sur téléphone.
//
// Après succès, **toutes** les sessions du compte sont révoquées côté service, y
// compris celle de cet appareil s'il en avait une : la purge locale et le retour à la
// connexion ne sont donc pas une politesse, ils remettent l'application en accord
// avec l'état réel de la session.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/session/session_controller.dart';
import 'package:prestgo_mobile/core/validation/validators.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';
import 'package:prestgo_mobile/features/auth/presentation/auth_layout.dart';
import 'package:prestgo_mobile/features/auth/presentation/rate_limit_handler.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({this.token, super.key});

  /// Jeton pré-rempli, quand il est arrivé par un lien ou par la réponse de
  /// développement de la demande.
  final String? token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen>
    with FormSubmissionMixin<ResetPasswordScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _token = TextEditingController(
    text: widget.token ?? '',
  );
  final TextEditingController _password = TextEditingController();
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
    _token.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) {
      return;
    }
    setState(() => _token.text = text);
    clearFieldError('token');
  }

  Future<void> _reset() async {
    if (_cooldown.isActive || !(_form.currentState?.validate() ?? false)) {
      return;
    }

    final String? message = await submit<String>(
      () => ref
          .read(authRepositoryProvider)
          .resetPassword(token: _token.text.trim(), password: _password.text),
    );

    if (message == null) {
      _cooldown.absorb(lastFailure);
      return;
    }

    // Toutes les sessions sont tombées côté service : on aligne l'appareil.
    await ref.read(sessionControllerProvider.notifier).signOut();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Nouveau mot de passe',
    subtitle:
        'Collez le code reçu par email, puis choisissez un nouveau mot de '
        'passe.',
    notice: _cooldown.isActive ? _cooldown.waitMessage : null,
    error: _cooldown.isActive ? null : formError,
    children: <Widget>[
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextFormField(
              controller: _token,
              // Le jeton est long : un champ d'une ligne le rendrait illisible.
              maxLines: 3,
              minLines: 2,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Code de réinitialisation',
                alignLabelWithHint: true,
                errorText: fieldErrors['token'],
              ),
              validator: Validators.passwordResetToken,
              onChanged: (_) => clearFieldError('token'),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _paste,
                icon: const Icon(Icons.content_paste_outlined, size: 18),
                label: const Text('Coller'),
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _password,
              obscureText: _hidden,
              decoration: InputDecoration(
                labelText: 'Nouveau mot de passe',
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
              validator: Validators.password,
              onChanged: (_) => clearFieldError('password'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmation,
              obscureText: _hidden,
              decoration: const InputDecoration(
                labelText: 'Confirmez le mot de passe',
              ),
              validator: (String? value) =>
                  Validators.passwordConfirmation(value, _password.text),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      AuthSubmitButton(
        label: 'Changer mon mot de passe',
        isBusy: isSubmitting,
        onPressed: _cooldown.isActive ? null : _reset,
      ),
      const SizedBox(height: 8),
      Text(
        'Toutes vos sessions ouvertes seront fermées.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}
