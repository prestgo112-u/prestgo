// Modifier mes informations (T076, FR-017).
//
// La règle qui donne sa forme à cet écran : changer son email ou son téléphone remet
// le contact en **non vérifié** et déclenche l'envoi d'un code. Rendre la main sans
// enchaîner laisserait l'utilisateur avec un contact durablement marqué « non
// vérifié », sans savoir qu'un code l'attend.
//
// L'enchaînement se décide sur `pendingVerifications`, structure renvoyée par le
// service — jamais sur le texte du message, ni sur une comparaison locale entre
// l'ancien et le nouveau contact : c'est le service qui sait ce qu'il a réellement
// modifié.
//
// ⚠️ Le canal renvoyé vaut `sms` pour le téléphone, alors que le motif OTP
// correspondant est `phone_verification`. La correspondance est portée par
// `VerificationChannel.otpPurpose`, en un seul endroit.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/validation/validators.dart';
import 'package:prestgo_mobile/features/auth/presentation/auth_layout.dart';
import 'package:prestgo_mobile/features/auth/presentation/verify/verify_screen.dart';
import 'package:prestgo_mobile/features/profile/data/me_repository.dart';
import 'package:prestgo_mobile/features/profile/domain/me.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({required this.me, super.key});

  final Me me;

  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen>
    with FormSubmissionMixin<ProfileEditScreen> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  late final TextEditingController _firstName = TextEditingController(
    text: widget.me.firstName ?? '',
  );
  late final TextEditingController _lastName = TextEditingController(
    text: widget.me.lastName ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.me.email ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.me.phone ?? '',
  );

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  /// Ne transmet que ce qui a réellement changé.
  ///
  /// Renvoyer l'email inchangé serait sans effet côté service (il compare), mais
  /// cette économie garde la requête lisible dans les journaux et rend l'intention
  /// explicite à la relecture.
  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) {
      return;
    }

    final Me me = widget.me;
    final String email = _email.text.trim();
    final String phone = _phone.text.trim();

    final Me? updated = await submit<Me>(
      () => ref
          .read(meRepositoryProvider)
          .updateProfile(
            firstName: _valueIfChanged(_firstName.text.trim(), me.firstName),
            lastName: _valueIfChanged(_lastName.text.trim(), me.lastName),
            email: _valueIfChanged(email, me.email),
            phone: _valueIfChanged(phone, me.phone),
          ),
    );

    if (updated == null || !mounted) {
      return;
    }

    ref.read(meControllerProvider.notifier).adopt(updated);

    // FR-017 : enchaînement automatique, piloté par la structure renvoyée.
    final PendingVerification? next = updated.pendingVerifications.firstOrNull;
    if (next != null) {
      context.pushReplacement(
        Routes.verifyFor(
          target: next.target,
          purpose: next.channel.otpPurpose,
          origin: VerificationOrigin.contactChange.name,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Profil mis à jour.')));
    context.pop();
  }

  static String? _valueIfChanged(String value, String? previous) =>
      value == (previous ?? '') ? null : value;

  @override
  Widget build(BuildContext context) => AuthLayout(
    title: 'Modifier mon profil',
    subtitle:
        'Changer votre email ou votre téléphone demandera une nouvelle '
        'vérification par code.',
    error: formError,
    children: <Widget>[
      Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TextFormField(
              controller: _firstName,
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'Prénom',
                counterText: '',
                errorText: fieldErrors['firstName'],
              ),
              onChanged: (_) => clearFieldError('firstName'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _lastName,
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'Nom',
                counterText: '',
                errorText: fieldErrors['lastName'],
              ),
              onChanged: (_) => clearFieldError('lastName'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Adresse email',
                errorText: fieldErrors['email'],
              ),
              validator: (String? value) =>
                  Validators.email(value, required: false),
              onChanged: (_) => clearFieldError('email'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Numéro de téléphone',
                errorText: fieldErrors['phone'],
              ),
              validator: (String? value) =>
                  Validators.phone(value, required: false),
              onChanged: (_) => clearFieldError('phone'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      AuthSubmitButton(
        label: 'Enregistrer',
        isBusy: isSubmitting,
        onPressed: _save,
      ),
    ],
  );
}
