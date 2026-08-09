// Habillage commun aux écrans d'authentification.
//
// Les sept écrans du parcours partagent la même structure — titre, explication,
// bannière d'erreur, formulaire, action principale, actions secondaires. La factoriser
// garantit surtout une chose : la bannière d'erreur est **toujours** au même endroit,
// au-dessus des champs, où un lecteur d'écran la rencontre avant eux.

import 'package:flutter/material.dart';

class AuthLayout extends StatelessWidget {
  const AuthLayout({
    required this.title,
    required this.children,
    this.subtitle,
    this.error,
    this.notice,
    this.showBackButton = true,
    super.key,
  });

  final String title;
  final String? subtitle;

  /// Message de bannière — erreur de formulaire ou refus du service.
  final String? error;

  /// Information neutre : attente de débit, message de confirmation.
  final String? notice;

  final List<Widget> children;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        automaticallyImplyLeading: showBackButton,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: <Widget>[
            if (subtitle case final String value)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (notice case final String value)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AuthBanner(message: value, isError: false),
              ),
            if (error case final String value)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: AuthBanner(message: value),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Bannière de formulaire, annoncée comme zone vive.
///
/// `liveRegion` est ce qui fait qu'un refus de connexion est **lu** au lieu d'être
/// silencieusement posé à l'écran, où l'utilisateur ne le trouverait qu'en explorant.
class AuthBanner extends StatelessWidget {
  const AuthBanner({required this.message, this.isError = true, super.key});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color background = isError
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.secondaryContainer;
    final Color foreground = isError
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSecondaryContainer;

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              size: 20,
              color: foreground,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Action principale d'un écran d'authentification.
///
/// Un seul bouton par écran, et il porte l'état d'envoi : c'est lui qui empêche le
/// double appui, pas une garde ailleurs dans l'écran.
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    required this.label,
    required this.onPressed,
    this.isBusy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: isBusy ? null : onPressed,
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    child: isBusy
        ? const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        : Text(label),
  );
}
