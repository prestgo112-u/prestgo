// Mot de passe oublié — demande (T071, FR-010).
//
// La règle qui gouverne cet écran est une règle de **sécurité**, pas d'ergonomie : le
// service répond exactement la même chose que l'adresse soit inscrite ou non. Il
// serait tentant d'afficher « Adresse inconnue » quand rien n'arrive — ce serait
// transformer cet écran en annuaire des comptes de la plateforme.
//
// Conséquence directe : la navigation vers la saisie du jeton est **systématique**.
// Elle ne dépend d'aucune condition, parce qu'il n'y a rien à conditionner.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/validation/validators.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';
import 'package:prestgo_mobile/features/auth/data/dto/auth_requests.dart';
import 'package:prestgo_mobile/features/auth/presentation/auth_layout.dart';
import 'package:prestgo_mobile/features/auth/presentation/rate_limit_handler.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen>
    with FormSubmissionMixin<ForgotPasswordScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final ActionCooldown _cooldown = ActionCooldown();

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
    _email.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _request() async {
    if (_cooldown.isActive || !(_form.currentState?.validate() ?? false)) {
      return;
    }

    final PasswordResetRequestResult? result =
        await submit<PasswordResetRequestResult>(
          () => ref
              .read(authRepositoryProvider)
              .requestPasswordReset(_email.text.trim()),
        );

    if (!mounted) {
      return;
    }
    if (result == null) {
      _cooldown.absorb(lastFailure);
      return;
    }

    // Navigation inconditionnelle : voir l'en-tête de fichier.
    // `devToken` n'est renseigné qu'en développement ; il pré-remplit le champ pour
    // rendre le parcours déroulable sans transport email.
    final String? devToken = result.devToken;
    context.go(
      devToken == null
          ? Routes.resetPassword
          : Routes.resetPasswordWithToken(devToken),
    );
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Mot de passe oublié',
    subtitle:
        'Indiquez l’adresse email de votre compte. Vous recevrez un code de '
        'réinitialisation, valable 30 minutes.',
    notice: _cooldown.isActive ? _cooldown.waitMessage : null,
    error: _cooldown.isActive ? null : formError,
    children: <Widget>[
      Form(
        key: _form,
        child: TextFormField(
          controller: _email,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          decoration: InputDecoration(
            labelText: 'Adresse email',
            errorText: fieldErrors['email'],
          ),
          validator: Validators.email,
          onChanged: (_) => clearFieldError('email'),
          onFieldSubmitted: (_) => _request(),
        ),
      ),
      const SizedBox(height: 24),
      AuthSubmitButton(
        label: 'Envoyer le code',
        isBusy: isSubmitting,
        onPressed: _cooldown.isActive ? null : _request,
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => context.go(Routes.resetPassword),
        child: const Text('J’ai déjà un code'),
      ),
    ],
  );
}
