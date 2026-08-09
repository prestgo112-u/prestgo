// Inscription — écrans C1, C2 et C3 (T066, FR-001).
//
// Les trois étapes vivent sous une seule route `/register` et un seul `Stepper` de
// navigation interne. Ce choix tient à une exigence : un compte n'est créé qu'au
// tout dernier geste, quand mot de passe et confirmation concordent. Trois routes
// distinctes laisseraient l'utilisateur revenir en arrière sur un compte déjà créé,
// et la deuxième tentative se heurterait à « Un compte existe déjà ».
//
// La confirmation du mot de passe est **purement locale** : le service ne la connaît
// pas, il n'y a donc rien à lui envoyer et rien à attendre de lui sur ce point.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/validation/validators.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';
import 'package:prestgo_mobile/features/auth/data/dto/auth_requests.dart';
import 'package:prestgo_mobile/features/auth/presentation/auth_layout.dart';
import 'package:prestgo_mobile/features/auth/presentation/rate_limit_handler.dart';
import 'package:prestgo_mobile/features/auth/presentation/register/registration_draft.dart';
import 'package:prestgo_mobile/features/auth/presentation/verify/verify_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with FormSubmissionMixin<RegisterScreen> {
  final GlobalKey<FormState> _identityForm = GlobalKey<FormState>();
  final GlobalKey<FormState> _passwordForm = GlobalKey<FormState>();

  final TextEditingController _contact = TextEditingController();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirmation = TextEditingController();
  final ActionCooldown _cooldown = ActionCooldown();

  /// 0 = C1 choix du canal, 1 = C2 identité, 2 = C3 mot de passe.
  int _step = 0;
  RegistrationChannel? _channel;
  bool _passwordHidden = true;

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
    _contact.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _chooseChannel(RegistrationChannel channel) {
    ref.read(registrationDraftProvider.notifier).start(channel);
    setState(() {
      _channel = channel;
      _step = 1;
    });
  }

  void _submitIdentity() {
    if (!(_identityForm.currentState?.validate() ?? false)) {
      return;
    }
    ref
        .read(registrationDraftProvider.notifier)
        .update(
          contact: _contact.text.trim(),
          firstName: _firstName.text.trim(),
          lastName: _lastName.text.trim(),
        );
    setState(() => _step = 2);
  }

  Future<void> _createAccount() async {
    if (_cooldown.isActive ||
        !(_passwordForm.currentState?.validate() ?? false)) {
      return;
    }

    final RegistrationChannel channel = _channel!;
    final String contact = _contact.text.trim();
    final RegisterRequest request = RegisterRequest(
      password: _password.text,
      email: channel == RegistrationChannel.email ? contact : null,
      phone: channel == RegistrationChannel.phone ? contact : null,
      firstName: _firstName.text.trim().isEmpty ? null : _firstName.text.trim(),
      lastName: _lastName.text.trim().isEmpty ? null : _lastName.text.trim(),
    );

    final RegisteredAccount? account = await submit<RegisteredAccount>(
      () => ref.read(authRepositoryProvider).register(request),
    );

    if (!mounted) {
      return;
    }
    if (account == null) {
      if (_cooldown.absorb(lastFailure)) {
        return;
      }
      // Un conflit porte sur le contact, saisi à l'étape précédente : y ramener
      // évite d'avoir à chercher où corriger.
      if (lastFailure?.isConflict ?? false) {
        setState(() => _step = 1);
      }
      return;
    }

    // Le mot de passe reste en mémoire pour la connexion automatique (C5).
    ref
        .read(registrationDraftProvider.notifier)
        .update(password: _password.text);

    context.go(
      Routes.verifyFor(
        target: account.verificationTarget ?? contact,
        purpose: channel.otpPurpose.wireValue,
        origin: VerificationOrigin.activation.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Créer un compte',
    notice: _cooldown.isActive ? _cooldown.waitMessage : null,
    error: _cooldown.isActive ? null : formError,
    children: <Widget>[
      Stepper(
        currentStep: _step,
        physics: const NeverScrollableScrollPhysics(),
        controlsBuilder: (BuildContext context, ControlsDetails details) =>
            const SizedBox.shrink(),
        onStepTapped: (int step) {
          // On ne remonte que vers une étape déjà franchie.
          if (step < _step) {
            setState(() => _step = step);
          }
        },
        steps: <Step>[
          Step(
            title: const Text('Comment vous joindre ?'),
            isActive: _step == 0,
            state: _step > 0 ? StepState.complete : StepState.indexed,
            content: _ChannelChoice(onChosen: _chooseChannel),
          ),
          Step(
            title: const Text('Vos coordonnées'),
            isActive: _step == 1,
            state: _step > 1 ? StepState.complete : StepState.indexed,
            content: _IdentityStep(
              formKey: _identityForm,
              channel: _channel ?? RegistrationChannel.email,
              contact: _contact,
              firstName: _firstName,
              lastName: _lastName,
              fieldErrors: fieldErrors,
              onFieldChanged: clearFieldError,
              onContinue: _submitIdentity,
            ),
          ),
          Step(
            title: const Text('Votre mot de passe'),
            isActive: _step == 2,
            content: _PasswordStep(
              formKey: _passwordForm,
              password: _password,
              confirmation: _confirmation,
              hidden: _passwordHidden,
              onToggleVisibility: () =>
                  setState(() => _passwordHidden = !_passwordHidden),
              fieldErrors: fieldErrors,
              onFieldChanged: clearFieldError,
              isBusy: isSubmitting,
              onSubmit: _cooldown.isActive ? null : _createAccount,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: () => context.go(Routes.login),
        child: const Text('J’ai déjà un compte'),
      ),
    ],
  );
}

/// C1 — un compte se crée avec un email **ou** un numéro ; au moins l'un des deux.
class _ChannelChoice extends StatelessWidget {
  const _ChannelChoice({required this.onChosen});

  final void Function(RegistrationChannel channel) onChosen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        'Le code de vérification vous sera envoyé sur ce contact.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      FilledButton.tonalIcon(
        onPressed: () => onChosen(RegistrationChannel.phone),
        icon: const Icon(Icons.sms_outlined),
        label: const Text('Par SMS'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        onPressed: () => onChosen(RegistrationChannel.email),
        icon: const Icon(Icons.mail_outline),
        label: const Text('Par email'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      ),
    ],
  );
}

/// C2 — contact et identité. Nom et prénom restent facultatifs (FR-001).
class _IdentityStep extends StatelessWidget {
  const _IdentityStep({
    required this.formKey,
    required this.channel,
    required this.contact,
    required this.firstName,
    required this.lastName,
    required this.fieldErrors,
    required this.onFieldChanged,
    required this.onContinue,
  });

  final GlobalKey<FormState> formKey;
  final RegistrationChannel channel;
  final TextEditingController contact;
  final TextEditingController firstName;
  final TextEditingController lastName;
  final Map<String, String> fieldErrors;
  final void Function(String field) onFieldChanged;
  final VoidCallback onContinue;

  String get _field => channel == RegistrationChannel.email ? 'email' : 'phone';

  @override
  Widget build(BuildContext context) => Form(
    key: formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextFormField(
          controller: contact,
          keyboardType: channel == RegistrationChannel.email
              ? TextInputType.emailAddress
              : TextInputType.phone,
          decoration: InputDecoration(
            labelText: channel.label,
            errorText: fieldErrors[_field],
          ),
          validator: (String? value) => channel == RegistrationChannel.email
              ? Validators.email(value)
              : Validators.phone(value),
          onChanged: (_) => onFieldChanged(_field),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: firstName,
          textCapitalization: TextCapitalization.words,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: 'Prénom (facultatif)',
            counterText: '',
            errorText: fieldErrors['firstName'],
          ),
          onChanged: (_) => onFieldChanged('firstName'),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: lastName,
          textCapitalization: TextCapitalization.words,
          maxLength: 80,
          decoration: InputDecoration(
            labelText: 'Nom (facultatif)',
            counterText: '',
            errorText: fieldErrors['lastName'],
          ),
          onChanged: (_) => onFieldChanged('lastName'),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onContinue,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text('Continuer'),
        ),
      ],
    ),
  );
}

/// C3 — mot de passe et confirmation locale.
class _PasswordStep extends StatelessWidget {
  const _PasswordStep({
    required this.formKey,
    required this.password,
    required this.confirmation,
    required this.hidden,
    required this.onToggleVisibility,
    required this.fieldErrors,
    required this.onFieldChanged,
    required this.isBusy,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController password;
  final TextEditingController confirmation;
  final bool hidden;
  final VoidCallback onToggleVisibility;
  final Map<String, String> fieldErrors;
  final void Function(String field) onFieldChanged;
  final bool isBusy;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) => Form(
    key: formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextFormField(
          controller: password,
          obscureText: hidden,
          decoration: InputDecoration(
            labelText: 'Mot de passe',
            helperText:
                '${AuthLimits.passwordMinLength} caractères minimum, '
                'dont une lettre et un chiffre',
            helperMaxLines: 2,
            errorText: fieldErrors['password'],
            suffixIcon: IconButton(
              onPressed: onToggleVisibility,
              icon: Icon(
                hidden
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              tooltip: hidden
                  ? 'Afficher le mot de passe'
                  : 'Masquer le mot de passe',
            ),
          ),
          validator: Validators.password,
          onChanged: (_) => onFieldChanged('password'),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: confirmation,
          obscureText: hidden,
          decoration: const InputDecoration(
            labelText: 'Confirmez le mot de passe',
          ),
          // Contrôle purement local : le service ne connaît pas ce champ.
          validator: (String? value) =>
              Validators.passwordConfirmation(value, password.text),
        ),
        const SizedBox(height: 20),
        AuthSubmitButton(
          label: 'Créer mon compte',
          isBusy: isBusy,
          onPressed: onSubmit,
        ),
      ],
    ),
  );
}
