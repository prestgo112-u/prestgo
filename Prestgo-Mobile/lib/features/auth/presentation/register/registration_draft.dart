// Brouillon d'inscription — les trois écrans C1, C2, C3 et la transition C5.
//
// ⚠️ Ce brouillon contient un **mot de passe en clair**. Il vit donc en mémoire
// seulement, jamais sur disque, ni en cache, ni dans une chaîne de requête, ni dans
// un journal (porte G6). C'est la raison d'être de ce fichier : sans un endroit
// nommé pour ce secret, il finirait par transiter dans un paramètre de navigation.
//
// Il est effacé dès que la connexion automatique a abouti, ou dès que l'utilisateur
// quitte le parcours.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/features/auth/data/dto/otp_dto.dart';

/// Canal choisi à l'écran C1.
enum RegistrationChannel {
  email,
  phone;

  String get label => switch (this) {
    RegistrationChannel.email => 'Adresse email',
    RegistrationChannel.phone => 'Numéro de téléphone',
  };

  OtpPurpose get otpPurpose => switch (this) {
    RegistrationChannel.email => OtpPurpose.emailVerification,
    RegistrationChannel.phone => OtpPurpose.phoneVerification,
  };
}

class RegistrationDraft {
  const RegistrationDraft({
    required this.channel,
    this.contact = '',
    this.firstName = '',
    this.lastName = '',
    this.password = '',
  });

  final RegistrationChannel channel;

  /// Email ou numéro, selon [channel].
  final String contact;
  final String firstName;
  final String lastName;

  /// En mémoire uniquement — cf. l'avertissement en tête de fichier.
  final String password;

  bool get isEmail => channel == RegistrationChannel.email;

  /// Vrai si le couple peut servir à `POST /auth/login` : la connexion automatique
  /// n'est possible qu'avec un email, le service n'acceptant pas le téléphone.
  bool get canSignInWithPassword => isEmail && contact.isNotEmpty;

  RegistrationDraft copyWith({
    RegistrationChannel? channel,
    String? contact,
    String? firstName,
    String? lastName,
    String? password,
  }) => RegistrationDraft(
    channel: channel ?? this.channel,
    contact: contact ?? this.contact,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    password: password ?? this.password,
  );
}

class RegistrationDraftController extends Notifier<RegistrationDraft?> {
  @override
  RegistrationDraft? build() => null;

  void start(RegistrationChannel channel) =>
      state = RegistrationDraft(channel: channel);

  void update({
    String? contact,
    String? firstName,
    String? lastName,
    String? password,
  }) {
    final RegistrationDraft? current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(
      contact: contact,
      firstName: firstName,
      lastName: lastName,
      password: password,
    );
  }

  /// Efface le brouillon — et le mot de passe qu'il porte.
  void clear() => state = null;
}

final NotifierProvider<RegistrationDraftController, RegistrationDraft?>
registrationDraftProvider =
    NotifierProvider<RegistrationDraftController, RegistrationDraft?>(
      RegistrationDraftController.new,
    );
