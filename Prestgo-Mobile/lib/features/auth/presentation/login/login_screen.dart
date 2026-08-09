// Connexion par email et mot de passe (T069, FR-005, FR-006).
//
// Deux règles qui ne se voient pas dans le code mais qui le gouvernent :
//
//   1. **message unique et non discriminant** — le service renvoie
//      `Invalid credentials` pour un email inconnu comme pour un mot de passe faux ;
//      l'application affiche « Email ou mot de passe incorrect. » dans les deux cas.
//      Rien ne doit permettre de savoir si l'adresse est inscrite ;
//   2. **`Account is not active` est autre chose** — là, l'utilisateur existe et son
//      mot de passe est bon : lui répéter « identifiants incorrects » l'enverrait
//      dans une impasse. L'écran propose la vérification.
//
// Un 429 ne déclenche **aucun** rejeu : le bouton se ferme le temps du compte à
// rebours (porte G4).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/core/validation/validators.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';
import 'package:prestgo_mobile/features/auth/data/dto/auth_requests.dart';
import 'package:prestgo_mobile/features/auth/data/dto/otp_dto.dart';
import 'package:prestgo_mobile/features/auth/presentation/auth_layout.dart';
import 'package:prestgo_mobile/features/auth/presentation/rate_limit_handler.dart';
import 'package:prestgo_mobile/features/auth/presentation/session_entry.dart';
import 'package:prestgo_mobile/features/auth/presentation/verify/verify_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({this.redirectTo, super.key});

  /// Route à restaurer après authentification (`/login?from=…`, scénario 2.4).
  final String? redirectTo;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with FormSubmissionMixin<LoginScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final ActionCooldown _cooldown = ActionCooldown();

  bool _passwordHidden = true;

  /// Renseigné quand le refus vient du statut du compte et non des identifiants :
  /// l'écran propose alors la vérification plutôt que la seule relecture du mot de
  /// passe.
  bool _accountNotActive = false;

  @override
  void initState() {
    super.initState();
    _cooldown.addListener(_onCooldownTick);
  }

  @override
  void dispose() {
    _cooldown
      ..removeListener(_onCooldownTick)
      ..dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onCooldownTick() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _signIn() async {
    if (_cooldown.isActive || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() => _accountNotActive = false);

    final AuthTokens? tokens = await submit<AuthTokens>(
      () => ref
          .read(authRepositoryProvider)
          .signIn(
            LoginRequest(email: _email.text.trim(), password: _password.text),
          ),
    );

    if (tokens == null) {
      final ApiException? failure = lastFailure;
      if (_cooldown.absorb(failure)) {
        return;
      }
      if (failure?.isAccountNotActive ?? false) {
        setState(() => _accountNotActive = true);
      }
      return;
    }

    await openSession(ref, tokens: tokens);
    if (!mounted) {
      return;
    }
    // Sans route mémorisée, on ne navigue pas : le gardien conduit lui-même vers
    // l'atterrissage du compte, qui dépend du profil en cours de chargement.
    final String? target = widget.redirectTo;
    if (target != null && target.isNotEmpty) {
      context.go(target);
    }
  }

  void _goToVerification() => context.go(
    Routes.verifyFor(
      target: _email.text.trim(),
      purpose: OtpPurpose.emailVerification.wireValue,
      origin: VerificationOrigin.activation.name,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bool waiting = _cooldown.isActive;

    return AuthLayout(
      title: 'Connexion',
      subtitle: 'Retrouvez vos réservations et vos échanges.',
      // Pas de `showBackButton` ici : `AuthLayout` s'en remet à
      // `automaticallyImplyLeading`, et une `AppBar` n'affiche la flèche que si
      // `Navigator.canPop()` est vrai. Porte d'entrée de l'application, cet écran
      // n'en a donc aucune ; atteint depuis une action protégée (`?from=`), il la
      // retrouve. Interroger `go_router` ici couplerait l'écran au routeur pour un
      // résultat que Flutter donne déjà — et ferait échouer tout test qui monte cet
      // écran sans routeur.
      notice: waiting ? _cooldown.waitMessage : null,
      // Le compte non actif porte sa propre bannière, avec l'issue qui va avec :
      // la bannière générale ferait doublon.
      error: waiting || _accountNotActive ? null : formError,
      children: <Widget>[
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextFormField(
                controller: _email,
                autofillHints: const <String>[AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Adresse email',
                  errorText: fieldErrors['email'],
                ),
                validator: Validators.email,
                onChanged: (_) => clearFieldError('email'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                autofillHints: const <String>[AutofillHints.password],
                obscureText: _passwordHidden,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  errorText: fieldErrors['password'],
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _passwordHidden = !_passwordHidden),
                    icon: Icon(
                      _passwordHidden
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    tooltip: _passwordHidden
                        ? 'Afficher le mot de passe'
                        : 'Masquer le mot de passe',
                  ),
                ),
                // Aucun contrôle de forme ici : un mot de passe existant peut être
                // antérieur aux règles actuelles. Seule la présence est exigée.
                validator: (String? value) => (value ?? '').isEmpty
                    ? 'Le mot de passe est obligatoire'
                    : null,
                onFieldSubmitted: (_) => _signIn(),
                onChanged: (_) => clearFieldError('password'),
              ),
              if (_accountNotActive) ...<Widget>[
                const SizedBox(height: 12),
                _AccountNotActiveHint(onVerify: _goToVerification),
              ],
              const SizedBox(height: 24),
              AuthSubmitButton(
                label: 'Se connecter',
                isBusy: isSubmitting,
                onPressed: waiting ? null : _signIn,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.push(Routes.forgotPassword),
          child: const Text('Mot de passe oublié ?'),
        ),
        TextButton(
          onPressed: () => context.push(Routes.phoneLogin),
          child: const Text('Se connecter avec un code par SMS'),
        ),
        const Divider(height: 32),
        OutlinedButton(
          onPressed: () => context.push(Routes.register),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          child: const Text('Créer un compte'),
        ),
        // La consultation sans compte reste ouverte (spec.md §89-90) : elle n'est
        // plus le point d'entrée, elle est une sortie offerte depuis la connexion.
        // `push` — et non `go` — pour qu'un retour arrière ramène ici.
        TextButton(
          onPressed: () => context.push(Routes.home),
          child: const Text('Découvrir sans compte'),
        ),
      ],
    );
  }
}

/// Sortie proposée quand le compte existe mais n'est pas encore utilisable.
class _AccountNotActiveHint extends StatelessWidget {
  const _AccountNotActiveHint({required this.onVerify});

  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      const AuthBanner(message: ApiFallbackMessages.accountNotActive),
      const SizedBox(height: 8),
      TextButton(
        onPressed: onVerify,
        child: const Text('Vérifier mon compte avec un code'),
      ),
    ],
  );
}
