// Connexion par téléphone, sans mot de passe (T070, FR-005).
//
// Ce parcours existe parce qu'un compte inscrit avec un numéro seul n'a aucun moyen
// de se connecter : `POST /auth/login` n'accepte qu'un email. Le service a ouvert
// `purpose: "login"` sur les deux routes OTP pour ça.
//
// ⚠️ Deux pièges tenus par le type plutôt que par la vigilance :
//   1. `purpose: "login"` est **toujours** renseigné, à l'envoi comme à la
//      vérification. Omis, il vaut `phone_verification` : le code partirait bien,
//      mais la vérification renverrait `{ verified, activated }` au lieu des jetons
//      — et le parcours s'arrêterait là sans erreur visible. C'est pourquoi le
//      dépôt expose `signInWithCode`, qui ne sait rien faire d'autre ;
//   2. un **401** ici ne veut pas dire « code faux » : le code était bon, mais aucun
//      compte actif ne correspond au numéro. Le message doit le dire.
//
// La session obtenue est de plein droit : mêmes jetons, mêmes droits qu'une connexion
// par mot de passe.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/validation/validators.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';
import 'package:prestgo_mobile/features/auth/data/dto/otp_dto.dart';
import 'package:prestgo_mobile/features/auth/presentation/auth_layout.dart';
import 'package:prestgo_mobile/features/auth/presentation/rate_limit_handler.dart';
import 'package:prestgo_mobile/features/auth/presentation/session_entry.dart';

class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({this.redirectTo, super.key});

  final String? redirectTo;

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen>
    with FormSubmissionMixin<PhoneLoginScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _code = TextEditingController();
  final ActionCooldown _resend = resendCooldown();
  final ActionCooldown _throttled = ActionCooldown();

  bool _codeSent = false;

  @override
  void initState() {
    super.initState();
    _resend.addListener(_refresh);
    _throttled.addListener(_refresh);
  }

  @override
  void dispose() {
    _resend
      ..removeListener(_refresh)
      ..dispose();
    _throttled
      ..removeListener(_refresh)
      ..dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _sendCode() async {
    if (_throttled.isActive || _resend.isActive) {
      return;
    }
    if (!(_form.currentState?.validate() ?? false)) {
      return;
    }

    final OtpChallenge? challenge = await submit<OtpChallenge>(
      () => ref
          .read(authRepositoryProvider)
          .sendOtp(target: _phone.text.trim(), purpose: OtpPurpose.login),
    );

    if (!mounted) {
      return;
    }
    if (challenge == null) {
      _throttled.absorb(lastFailure);
      return;
    }
    setState(() => _codeSent = true);
    _resend.start();
  }

  Future<void> _signIn() async {
    final String? invalid = Validators.verificationCode(_code.text);
    if (invalid != null) {
      showFormError(invalid);
      return;
    }

    final AuthTokens? tokens = await submit<AuthTokens>(
      () => ref
          .read(authRepositoryProvider)
          .signInWithCode(target: _phone.text.trim(), code: _code.text),
    );

    if (!mounted) {
      return;
    }
    if (tokens == null) {
      final ApiException? failure = lastFailure;
      if (_throttled.absorb(failure)) {
        return;
      }
      if (failure?.isAuth ?? false) {
        // Le code était bon : c'est le compte qui n'est pas utilisable.
        showFormError(
          'Aucun compte actif n’est associé à ce numéro. '
          'Vérifiez le numéro ou créez un compte.',
        );
      }
      return;
    }

    await openSession(ref, tokens: tokens);
    if (!mounted) {
      return;
    }
    final String? target = widget.redirectTo;
    if (target != null && target.isNotEmpty) {
      context.go(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool waiting = _throttled.isActive;

    return AuthLayout(
      title: 'Connexion par SMS',
      subtitle: _codeSent
          ? 'Saisissez le code reçu au ${_phone.text.trim()}.'
          : 'Nous vous envoyons un code à usage unique. Aucun mot de passe '
                'n’est nécessaire.',
      notice: waiting ? _throttled.waitMessage : null,
      error: waiting ? null : formError,
      children: <Widget>[
        Form(
          key: _form,
          child: TextFormField(
            controller: _phone,
            enabled: !_codeSent,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Numéro de téléphone',
              errorText: fieldErrors['target'],
            ),
            validator: Validators.phone,
            onChanged: (_) => clearFieldError('target'),
          ),
        ),
        if (_codeSent) ...<Widget>[
          const SizedBox(height: 20),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: AuthLimits.verificationCodeLength,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(letterSpacing: 8),
            inputFormatters: <TextInputFormatter>[
              FilteringTextInputFormatter.digitsOnly,
            ],
            decoration: const InputDecoration(
              counterText: '',
              hintText: '••••••',
            ),
            onChanged: (String value) {
              showFormError(null);
              if (value.length == AuthLimits.verificationCodeLength) {
                unawaited(_signIn());
              }
            },
          ),
          const SizedBox(height: 20),
          AuthSubmitButton(
            label: 'Se connecter',
            isBusy: isSubmitting,
            onPressed: waiting ? null : _signIn,
          ),
          TextButton(
            onPressed: _resend.isActive || isSubmitting ? null : _sendCode,
            child: Text(
              _resend.isActive
                  ? 'Renvoyer le code dans ${_resend.remaining.inSeconds} s'
                  : 'Renvoyer le code',
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              _codeSent = false;
              _code.clear();
            }),
            child: const Text('Modifier le numéro'),
          ),
        ] else ...<Widget>[
          const SizedBox(height: 24),
          AuthSubmitButton(
            label: 'Recevoir un code',
            isBusy: isSubmitting,
            onPressed: waiting ? null : _sendCode,
          ),
        ],
        const Divider(height: 32),
        TextButton(
          onPressed: () => context.go(Routes.login),
          child: const Text('Se connecter avec un mot de passe'),
        ),
      ],
    );
  }
}
