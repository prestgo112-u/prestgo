// Écran C5 — transition après activation (T068, FR-004).
//
// Le compte vient de passer de `pending` à `active`. Demander de retaper l'email et
// le mot de passe qu'on vient de choisir, à trois écrans d'intervalle, n'aurait
// aucun sens : la connexion se fait toute seule, à partir du brouillon d'inscription
// resté en mémoire.
//
// Deux chemins de repli, tous deux normaux :
//   • **inscription par téléphone** — `POST /auth/login` n'accepte qu'un email ; il
//     n'y a rien à tenter, l'écran renvoie vers la connexion par code ;
//   • **brouillon absent** — l'utilisateur est arrivé ici depuis l'écran de
//     connexion (« Vérifier mon compte »), le mot de passe n'a jamais transité :
//     retour à la connexion, compte désormais utilisable.
//
// Le brouillon est effacé dans tous les cas, y compris en cas d'échec : il porte un
// mot de passe en clair (porte G6).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/session/secure_token_store.dart';
import 'package:prestgo_mobile/features/auth/data/auth_repository.dart';
import 'package:prestgo_mobile/features/auth/data/dto/auth_requests.dart';
import 'package:prestgo_mobile/features/auth/presentation/auth_layout.dart';
import 'package:prestgo_mobile/features/auth/presentation/register/registration_draft.dart';
import 'package:prestgo_mobile/features/auth/presentation/session_entry.dart';

class AutoLoginScreen extends ConsumerStatefulWidget {
  const AutoLoginScreen({super.key});

  @override
  ConsumerState<AutoLoginScreen> createState() => _AutoLoginScreenState();
}

class _AutoLoginScreenState extends ConsumerState<AutoLoginScreen> {
  String? _failure;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _signIn());
  }

  Future<void> _signIn() async {
    final RegistrationDraft? draft = ref.read(registrationDraftProvider);

    if (draft == null || !draft.canSignInWithPassword) {
      ref.read(registrationDraftProvider.notifier).clear();
      if (mounted) {
        context.go(Routes.login);
      }
      return;
    }

    try {
      final AuthTokens tokens = await ref
          .read(authRepositoryProvider)
          .signIn(LoginRequest(email: draft.contact, password: draft.password));
      await openSession(ref, tokens: tokens);
      // Le gardien conduit vers l'atterrissage du compte dès que le profil est là.
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _failure = error.message);
      }
    } finally {
      ref.read(registrationDraftProvider.notifier).clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? failure = _failure;
    if (failure == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              SizedBox.square(
                dimension: 36,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(height: 20),
              Text('Compte activé. Connexion en cours…'),
            ],
          ),
        ),
      );
    }

    return AuthLayout(
      title: 'Compte activé',
      subtitle:
          'Votre compte est prêt. La connexion automatique n’a pas abouti, '
          'connectez-vous pour continuer.',
      error: failure,
      showBackButton: false,
      children: <Widget>[
        AuthSubmitButton(
          label: 'Aller à la connexion',
          onPressed: () => context.go(Routes.login),
        ),
      ],
    );
  }
}
