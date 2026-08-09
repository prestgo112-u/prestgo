// P7 — Justificatifs (T156, T160 ; FR-057, FR-058, FR-059).
//
// L'écran se construit depuis `requiredTypes` — RIEN n'est codé en dur : le
// back-office peut exiger un second type demain, et cet écran l'affichera sans
// changement de code.
//
// L'envoi est en deux temps, volontairement : le binaire part d'abord
// (`POST /files/upload`, visibilité `sensitive`, refus local du type et de la
// taille AVANT tout réseau — scénario 4.6), la règle métier ensuite
// (`POST /providers/me/documents`).
//
// Après CHAQUE dépôt réussi (T160) :
//   • la vue des documents est relue — la nouvelle version doit apparaître ;
//   • **l'aperçu du dossier est relu** : en `changes_requested`, le dépôt seul
//     a repassé le dossier en `pending_review` — l'écran l'annonce (« reparti
//     en vérification ») et le bouton « Re-soumettre » du hub disparaît de
//     lui-même, `canSubmit` étant retombé (scénario 4.9).
//
// Un document `approved` ne se redépose pas : l'action est retirée de sa ligne.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/core/files/file_upload_service.dart';
import 'package:prestgo_mobile/core/format/datetime.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/document_picker.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_overview_controller.dart';
import 'package:prestgo_mobile/features/provider_space/domain/provider_document.dart';

final FutureProvider<ProviderDocumentsOverview> _documentsProvider =
    FutureProvider.autoDispose<ProviderDocumentsOverview>(
      (Ref ref) => ref.watch(providerSelfRepositoryProvider).documents(),
    );

class DocumentsStepScreen extends ConsumerStatefulWidget {
  const DocumentsStepScreen({super.key});

  @override
  ConsumerState<DocumentsStepScreen> createState() =>
      _DocumentsStepScreenState();
}

class _DocumentsStepScreenState extends ConsumerState<DocumentsStepScreen> {
  /// Type en cours de dépôt — sa ligne affiche l'attente, les autres restent
  /// actives.
  String? _uploadingType;
  String? _error;

  Future<void> _deposit(String type) async {
    setState(() => _error = null);

    final UploadCandidate? candidate = await ref
        .read(documentPickerProvider)
        .pick();
    if (candidate == null || !mounted) {
      return;
    }

    setState(() => _uploadingType = type);
    try {
      // Étape 1 — le binaire. Type et taille sont refusés LOCALEMENT avant tout
      // appel : un dépassement des 10 Mo ne part jamais sur le réseau (4.6).
      final FileRef file = await ref
          .read(fileUploadServiceProvider)
          .upload(candidate, visibility: FileVisibility.sensitive);

      // Étape 2 — la règle métier : rattacher le fichier au type exigé.
      await ref
          .read(providerSelfRepositoryProvider)
          .attachDocument(type: type, fileId: file.id);

      // T160 — après chaque dépôt : relire la vue ET l'aperçu. Le statut du
      // dossier a pu changer tout seul (changes_requested → pending_review).
      final ProviderValidationStatus? before = ref
          .read(providerOverviewProvider)
          .value
          ?.validationStatus;
      ref.invalidate(_documentsProvider);
      await ref.read(providerOverviewProvider.notifier).reload();

      if (!mounted) {
        return;
      }
      final ProviderValidationStatus? after = ref
          .read(providerOverviewProvider)
          .value
          ?.validationStatus;
      final bool backInReview =
          before == ProviderValidationStatus.changesRequested &&
          after == ProviderValidationStatus.pendingReview;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            backInReview
                ? 'Justificatif transmis — votre dossier est reparti en '
                      'vérification.'
                : 'Justificatif transmis',
          ),
        ),
      );
    } on FileRejected catch (rejection) {
      setState(() => _error = rejection.message);
    } on ApiException catch (failure) {
      setState(
        () => _error = failure.isNotFound
            // « Fichier introuvable ou ne vous appartenant pas » : l'étape 1
            // est à refaire — le dire mieux que le message brut.
            ? 'Le fichier n’a pas pu être rattaché. Reprenez le dépôt.'
            : failure.message,
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingType = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<ProviderDocumentsOverview> data = ref.watch(
      _documentsProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Justificatifs')),
      body: switch (data) {
        AsyncValue<ProviderDocumentsOverview>(
          :final ProviderDocumentsOverview value,
        ) =>
          _buildBody(value),
        AsyncValue<ProviderDocumentsOverview>(:final Object error?) =>
          ErrorView(
            message: error is ApiException
                ? error.message
                : 'Impossible de charger les justificatifs. Réessayez.',
            onRetry: () => ref.invalidate(_documentsProvider),
          ),
        _ => const LoadingView(label: 'Chargement des justificatifs…'),
      },
    );
  }

  Widget _buildBody(ProviderDocumentsOverview overview) {
    final ThemeData theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Déposez chaque document demandé : photo nette ou PDF, '
          '10 Mo au maximum. Nos équipes les examinent à la soumission du '
          'dossier.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        if (_error case final String message) ...<Widget>[
          Text(message, style: TextStyle(color: theme.colorScheme.error)),
          const SizedBox(height: 8),
        ],
        // Les lignes viennent de `requiredTypes`, dans l'ordre du service.
        for (final String type in overview.requiredTypes)
          _DocumentTile(
            type: type,
            current: overview.currentFor(type),
            versions: overview.versionsFor(type),
            missing: overview.isMissing(type),
            uploading: _uploadingType == type,
            onDeposit: _uploadingType == null ? () => _deposit(type) : null,
          ),
      ],
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.type,
    required this.current,
    required this.versions,
    required this.missing,
    required this.uploading,
    required this.onDeposit,
  });

  final String type;
  final ProviderDocument? current;
  final List<ProviderDocument> versions;
  final bool missing;
  final bool uploading;
  final VoidCallback? onDeposit;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ProviderDocument? current = this.current;
    final bool locked = current?.isLocked ?? false;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  switch (current?.status) {
                    ProviderDocumentStatus.approved => Icons.verified,
                    ProviderDocumentStatus.rejected => Icons.cancel_outlined,
                    ProviderDocumentStatus.pending => Icons.hourglass_top,
                    null => Icons.upload_file_outlined,
                  },
                  color: switch (current?.status) {
                    ProviderDocumentStatus.approved => Colors.green.shade700,
                    ProviderDocumentStatus.rejected => theme.colorScheme.error,
                    _ => theme.colorScheme.onSurfaceVariant,
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        documentTypeLabel(type),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        current == null
                            ? 'Aucun document déposé'
                            : '${current.status.label} · '
                                  'version ${current.version}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: missing
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (uploading)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (!locked)
                  TextButton(
                    onPressed: onDeposit,
                    child: Text(current == null ? 'Déposer' : 'Remplacer'),
                  ),
              ],
            ),
            // Le motif de refus est LA donnée de l'écran de correction.
            if (current?.rejectionReason case final String reason) ...<Widget>[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  reason,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
            if (locked) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Document validé — il ne peut plus être remplacé.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            // L'historique complet, replié : chaque redépôt crée une version,
            // aucune n'écrase la précédente.
            if (versions.length > 1)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                shape: const Border(),
                title: Text(
                  'Historique des versions (${versions.length})',
                  style: theme.textTheme.bodySmall,
                ),
                children: <Widget>[
                  for (final ProviderDocument version in versions)
                    ListTile(
                      dense: true,
                      leading: Text('v${version.version}'),
                      title: Text(version.file.originalName),
                      subtitle: Text(
                        version.createdAt == null
                            ? version.status.label
                            : '${version.status.label} · '
                                  '${DateLabels.dayAndTime(version.createdAt!)}',
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
