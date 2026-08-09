// Écran C4 — saisie du code de vérification (T067, FR-002 à FR-004).
//
// Quatre règles, toutes vérifiables à l'écran :
//
//   1. **envoi dès l'arrivée** (FR-002) — sauf quand le code vient d'être émis par
//      l'appel précédent : `PATCH /me` en envoie un lui-même, en redemander un
//      invaliderait celui que l'utilisateur est peut-être déjà en train de lire, et
//      consommerait un des cinq envois autorisés par minute ;
//   2. **compte à rebours fondé sur `expiresInMinutes`** — la valeur vient du
//      service, jamais d'une constante locale (porte G3) ; `AuthLimits` ne sert que
//      de repli si le service ne l'a pas renvoyée ;
//   3. **cinq essais sur un même code** — au-delà, le service répond 401 et le code
//      est brûlé : la saisie se ferme et seul le renvoi reste possible. Le compteur
//      est aussi tenu localement, pour fermer la saisie sans attendre le refus ;
//   4. **un seul message d'échec** — code faux, expiré ou déjà consommé sont
//      indiscernables, côté service comme à l'écran.
//
// La suite du parcours se décide sur `activated`, **pas** sur le texte du message
// (FR-004) : « Compte activé » et « Code vérifié » ne sont pas des données.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/validation/validators.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';
import 'package:prestgo_mobile/features/auth/data/dto/otp_dto.dart';
import 'package:prestgo_mobile/features/auth/presentation/auth_layout.dart';
import 'package:prestgo_mobile/features/auth/presentation/rate_limit_handler.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';

/// Ce qui a conduit à cet écran — c'est ce qui décide de la suite.
enum VerificationOrigin {
  /// Compte neuf à activer : la vérification enchaîne sur la connexion (C5).
  activation,

  /// Contact modifié depuis le profil : retour au profil avec confirmation.
  contactChange;

  static VerificationOrigin parse(String? raw) => switch (raw) {
    'contactChange' => VerificationOrigin.contactChange,
    _ => VerificationOrigin.activation,
  };

  /// Vrai si le code a **déjà** été émis par l'appel qui a mené ici.
  bool get codeAlreadySent => this == VerificationOrigin.contactChange;
}

class VerifyScreen extends ConsumerStatefulWidget {
  const VerifyScreen({
    required this.target,
    required this.purpose,
    required this.origin,
    super.key,
  });

  /// Destinataire du code : numéro de téléphone ou adresse email.
  final String target;
  final OtpPurpose purpose;
  final VerificationOrigin origin;

  @override
  ConsumerState<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends ConsumerState<VerifyScreen>
    with FormSubmissionMixin<VerifyScreen> {
  final TextEditingController _code = TextEditingController();
  final ActionCooldown _resend = resendCooldown();
  final ActionCooldown _throttled = ActionCooldown();

  Timer? _expiryTicker;
  DateTime? _expiresAt;
  int _failedAttempts = 0;
  bool _codeBurnt = false;
  String? _notice;

  /// Vrai tant que la saisie est utilisable.
  bool get _canType =>
      !_codeBurnt &&
      _failedAttempts < AuthLimits.verificationMaxAttempts &&
      !_isExpired;

  bool get _isExpired {
    final DateTime? expiresAt = _expiresAt;
    return expiresAt != null && !expiresAt.isAfter(DateTime.now());
  }

  Duration get _remaining {
    final DateTime? expiresAt = _expiresAt;
    if (expiresAt == null) {
      return Duration.zero;
    }
    final Duration left = expiresAt.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void initState() {
    super.initState();
    _resend.addListener(_refresh);
    _throttled.addListener(_refresh);
    // FR-002 : le code part à l'arrivée, sans geste supplémentaire.
    if (widget.origin.codeAlreadySent) {
      _startExpiry(AuthLimits.verificationCodeFallbackLifetime);
      _resend.start();
    } else {
      unawaited(_sendCode(isResend: false));
    }
  }

  @override
  void dispose() {
    _expiryTicker?.cancel();
    _resend
      ..removeListener(_refresh)
      ..dispose();
    _throttled
      ..removeListener(_refresh)
      ..dispose();
    _code.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _startExpiry(Duration lifetime) {
    _expiryTicker?.cancel();
    _expiresAt = DateTime.now().add(lifetime);
    _expiryTicker = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_isExpired) {
        timer.cancel();
        _expiryTicker = null;
      }
      _refresh();
    });
  }

  Future<void> _sendCode({required bool isResend}) async {
    if (isResend && _resend.isActive) {
      return;
    }

    final OtpChallenge? challenge = await submit<OtpChallenge>(
      () => ref
          .read(authRepositoryProvider)
          .sendOtp(target: widget.target, purpose: widget.purpose),
    );

    if (!mounted) {
      return;
    }
    if (challenge == null) {
      _throttled.absorb(lastFailure);
      return;
    }

    setState(() {
      _failedAttempts = 0;
      _codeBurnt = false;
      _code.clear();
      _notice = isResend ? 'Un nouveau code vous a été envoyé.' : null;
    });
    // Le compte à rebours suit la durée annoncée par le service (porte G3).
    _startExpiry(
      challenge.expiresIn ?? AuthLimits.verificationCodeFallbackLifetime,
    );
    _resend.start();
  }

  Future<void> _verify() async {
    final String? invalid = Validators.verificationCode(_code.text);
    if (invalid != null) {
      showFormError(invalid);
      return;
    }

    final OtpVerification? result = await submit<OtpVerification>(
      () => ref
          .read(authRepositoryProvider)
          .verifyContact(
            target: widget.target,
            code: _code.text,
            purpose: widget.purpose,
          ),
    );

    if (!mounted) {
      return;
    }

    if (result == null) {
      final ApiException? failure = lastFailure;
      if (_throttled.absorb(failure)) {
        return;
      }
      setState(() {
        _failedAttempts++;
        // 401 sur cette route ne parle pas de session : ce code-ci est brûlé.
        _codeBurnt = failure?.isAuth ?? false;
      });
      return;
    }

    await _onVerified(result);
  }

  Future<void> _onVerified(OtpVerification result) async {
    // FR-004 : la suite se décide sur `activated`, jamais sur le message.
    if (widget.origin == VerificationOrigin.activation && result.activated) {
      if (mounted) {
        context.go(Routes.autoLogin);
      }
      return;
    }

    // Vérification d'un contact : le profil a changé, on le relit avant de rendre
    // la main pour que la pastille « non vérifié » disparaisse.
    await ref.read(meControllerProvider.notifier).reload();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Votre $_channelLabel est vérifié.')),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(Routes.profile);
    }
  }

  String get _channelLabel => widget.purpose == OtpPurpose.emailVerification
      ? 'adresse email'
      : 'numéro de téléphone';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool waiting = _throttled.isActive;

    return AuthLayout(
      title: 'Code de vérification',
      subtitle:
          'Saisissez le code à ${AuthLimits.verificationCodeLength} chiffres '
          'envoyé à ${widget.target}.',
      notice: waiting ? _throttled.waitMessage : _notice,
      error: waiting ? null : _errorMessage,
      children: <Widget>[
        TextField(
          controller: _code,
          enabled: _canType && !isSubmitting,
          autofocus: true,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          maxLength: AuthLimits.verificationCodeLength,
          style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
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
              unawaited(_verify());
            }
          },
        ),
        const SizedBox(height: 8),
        _ExpiryLine(remaining: _remaining, isExpired: _isExpired),
        const SizedBox(height: 20),
        AuthSubmitButton(
          label: 'Vérifier',
          isBusy: isSubmitting,
          onPressed: _canType ? _verify : null,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _resend.isActive || isSubmitting
              ? null
              : () => _sendCode(isResend: true),
          child: Text(
            _resend.isActive
                ? 'Renvoyer le code dans ${_resend.remaining.inSeconds} s'
                : 'Renvoyer le code',
          ),
        ),
      ],
    );
  }

  /// Un seul message d'échec, quelle qu'en soit la cause exacte (FR-003).
  String? get _errorMessage {
    if (_codeBurnt || _failedAttempts >= AuthLimits.verificationMaxAttempts) {
      return 'Trop de tentatives sur ce code. Demandez-en un nouveau.';
    }
    if (_isExpired && _expiresAt != null) {
      return 'Ce code a expiré. Demandez-en un nouveau.';
    }
    return formError;
  }
}

/// Temps de validité restant.
class _ExpiryLine extends StatelessWidget {
  const _ExpiryLine({required this.remaining, required this.isExpired});

  final Duration remaining;
  final bool isExpired;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (isExpired) {
      return Text(
        'Code expiré',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }
    final int minutes = remaining.inMinutes;
    final int seconds = remaining.inSeconds % 60;
    return Text(
      'Valable encore $minutes:${seconds.toString().padLeft(2, '0')}',
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
