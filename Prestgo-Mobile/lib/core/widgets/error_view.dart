// État d'erreur partagé, avec action de reprise.
//
// Le message affiché vient de `ApiException.message`, déjà assaini par
// l'intercepteur : cet écran ne réinterprète ni code HTTP ni message technique
// (porte G2).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({
    required this.message,
    super.key,
    this.onRetry,
    this.retryLabel = 'Réessayer',
    this.correlationId,
    this.icon = Icons.error_outline,
  });

  /// Construit l'état à partir d'une erreur du socle.
  ErrorView.fromException(
    ApiException error, {
    super.key,
    VoidCallback? onRetry,
    this.retryLabel = 'Réessayer',
  }) : message = error.message,
       correlationId = error.correlationId,
       icon = error.isNetwork ? Icons.wifi_off_outlined : Icons.error_outline,
       // Un débit dépassé ne se rejoue pas : proposer « Réessayer » inviterait à
       // aggraver la situation (porte G4).
       onRetry = error.isRateLimited ? null : onRetry;

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  /// Proposé en copie pour le support, jamais mis en avant (contrat §6).
  final String? correlationId;

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final VoidCallback? onRetry = this.onRetry;
    final String? correlationId = this.correlationId;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 44, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
            ],
            if (correlationId != null) ...<Widget>[
              const SizedBox(height: 16),
              _CorrelationIdAction(correlationId: correlationId),
            ],
          ],
        ),
      ),
    );
  }
}

/// Bandeau d'erreur compact, pour un bloc en échec dans un écran composé.
///
/// Le tableau de bord prestataire est bâti de blocs indépendants : un bloc en
/// erreur ne doit pas masquer les autres (scénario 5.1 de quickstart.md).
class ErrorTile extends StatelessWidget {
  const ErrorTile({required this.message, super.key, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final VoidCallback? onRetry = this.onRetry;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.error_outline,
            size: 20,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}

class _CorrelationIdAction extends StatelessWidget {
  const _CorrelationIdAction({required this.correlationId});

  final String correlationId;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () async {
      await Clipboard.setData(ClipboardData(text: correlationId));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Référence copiée.')));
      }
    },
    icon: const Icon(Icons.copy_all_outlined, size: 18),
    label: const Text('Copier la référence pour le support'),
  );
}
