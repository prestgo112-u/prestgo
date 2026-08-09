// Portfolio — mes réalisations (T215, FR-068, FR-069 ; scénario 8.3).
//
// Quatre règles du contrat, matérialisées ici :
//
//   • **20 réalisations au maximum** : à 20, l'ajout est indisponible AVEC son
//     motif — pas un bouton muet, pas un 400 à retardement (8.3) ;
//   • **images uniquement**, refusées localement avant tout réseau ;
//   • **réordonnancement élément par élément** : il n'existe aucune route de
//     lot — chaque déplacement envoie un PATCH `displayOrder` par réalisation
//     déplacée, et le moindre échec fait replier l'écran sur l'ordre du
//     serveur, la seule vérité ;
//   • **le retrait ramène le fichier en `restricted`** : l'URL publique ne
//     sert plus rien — le cache d'image local est purgé dans la foulée.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/api/api_providers.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/files/file_avatar.dart';
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/core/files/file_upload_service.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/document_picker.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_self_access.dart';
import 'package:prestgo_mobile/features/provider_space/domain/portfolio_item.dart';

final FutureProvider<List<PortfolioItem>> portfolioProvider =
    FutureProvider.autoDispose<List<PortfolioItem>>(
      (Ref ref) => ref.watch(providerSelfRepositoryProvider).portfolio(),
    );

class ProviderPortfolioScreen extends ConsumerWidget {
  const ProviderPortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PortfolioItem>> items = ref.watch(portfolioProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Mes réalisations')),
      body: switch (items) {
        AsyncValue<List<PortfolioItem>>(:final List<PortfolioItem> value) =>
          _PortfolioBody(items: value),
        AsyncValue<List<PortfolioItem>>(:final Object error?) =>
          error is ApiException
              ? ErrorView.fromException(
                  error,
                  onRetry: () => ref.invalidate(portfolioProvider),
                )
              : ErrorView(
                  message: 'Impossible de charger vos réalisations. Réessayez.',
                  onRetry: () => ref.invalidate(portfolioProvider),
                ),
        _ => const LoadingView(label: 'Chargement de vos réalisations…'),
      },
    );
  }
}

class _PortfolioBody extends ConsumerStatefulWidget {
  const _PortfolioBody({required this.items});

  final List<PortfolioItem> items;

  @override
  ConsumerState<_PortfolioBody> createState() => _PortfolioBodyState();
}

class _PortfolioBodyState extends ConsumerState<_PortfolioBody> {
  bool _busy = false;
  String? _error;

  bool get _atCap => widget.items.length >= ContentLimits.portfolioItems;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) {
        ref.invalidate(portfolioProvider);
      }
    } on FileRejected catch (rejection) {
      if (mounted) {
        setState(() => _error = rejection.message);
      }
    } on ApiException catch (failure) {
      if (mounted) {
        setState(() => _error = failure.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _add() async {
    final UploadCandidate? candidate = await ref
        .read(documentPickerProvider)
        .pick();
    if (candidate == null || !mounted) {
      return;
    }

    final _ItemEdit? edit = await showDialog<_ItemEdit>(
      context: context,
      builder: (BuildContext context) => const _ItemEditDialog(),
    );
    if (edit == null || !mounted) {
      return;
    }

    await _run(() async {
      // Images uniquement : un PDF est refusé ICI, avant tout appel réseau.
      final FileRef file = await ref
          .read(fileUploadServiceProvider)
          .upload(
            candidate,
            acceptedMimeTypes: FileLimits.imageOnlyMimeTypes,
            visibility: FileVisibility.public,
          );
      await ref
          .read(providerSelfRepositoryProvider)
          .addPortfolioItem(
            fileId: file.id,
            title: edit.title,
            description: edit.description,
            displayOrder: widget.items.length,
          );
    });
    if (mounted && _error == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Réalisation ajoutée')));
    }
  }

  Future<void> _edit(PortfolioItem item) async {
    final _ItemEdit? edit = await showDialog<_ItemEdit>(
      context: context,
      builder: (BuildContext context) => _ItemEditDialog(item: item),
    );
    if (edit == null || !mounted) {
      return;
    }
    await _run(
      () async => ref
          .read(providerSelfRepositoryProvider)
          .updatePortfolioItem(
            item.id,
            title: edit.title ?? '',
            description: edit.description ?? '',
          ),
    );
  }

  /// Déplace [item] d'un cran — un PATCH `displayOrder` PAR réalisation
  /// déplacée (elle et sa voisine), jamais de lot. Au moindre échec, l'écran
  /// se replie sur l'ordre du serveur.
  Future<void> _move(PortfolioItem item, {required bool up}) async {
    final int index = widget.items.indexOf(item);
    final int targetIndex = up ? index - 1 : index + 1;
    if (targetIndex < 0 || targetIndex >= widget.items.length) {
      return;
    }
    final PortfolioItem neighbour = widget.items[targetIndex];

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ProviderSelfRepository repository = ref.read(
        providerSelfRepositoryProvider,
      );
      await repository.updatePortfolioItem(
        item.id,
        displayOrder: neighbour.displayOrder,
      );
      await repository.updatePortfolioItem(
        neighbour.id,
        displayOrder: item.displayOrder,
      );
    } on ApiException catch (failure) {
      // Repli : l'ordre affiché redevient celui du serveur, quel qu'il soit —
      // y compris si le premier PATCH est passé et pas le second.
      if (mounted) {
        setState(() => _error = failure.message);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        ref.invalidate(portfolioProvider);
      }
    }
  }

  Future<void> _remove(PortfolioItem item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Retirer cette réalisation ?'),
        content: const Text(
          'La photo disparaît de votre fiche publique. Elle n’est pas '
          'supprimée de nos serveurs mais n’est plus visible de personne.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final String baseUrl = ref.read(appEnvironmentProvider).apiBaseUrl;
    await _run(() async {
      await ref
          .read(providerSelfRepositoryProvider)
          .removePortfolioItem(item.id);
      // Le fichier est ramené en `restricted` : la copie du cache disque ne
      // correspond plus à rien de servi — purge immédiate (FR-069).
      await CachedNetworkImage.evictFromCache(
        '$baseUrl${item.file.contentPath}',
      );
    });
    if (mounted && _error == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Réalisation retirée')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      children: <Widget>[
        Expanded(
          child: widget.items.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Aucune réalisation. Ajoutez des photos de vos '
                      'chantiers : elles apparaissent sur votre fiche '
                      'publique et rassurent les clients.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: <Widget>[
                    for (final PortfolioItem item in widget.items)
                      _PortfolioTile(
                        item: item,
                        first: item == widget.items.first,
                        last: item == widget.items.last,
                        enabled: !_busy,
                        onEdit: () => _edit(item),
                        onMoveUp: () => _move(item, up: true),
                        onMoveDown: () => _move(item, up: false),
                        onRemove: () => _remove(item),
                      ),
                  ],
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_error case final String message) ...<Widget>[
                  Text(
                    message,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  const SizedBox(height: 8),
                ],
                // À 20, l'action est indisponible AVEC son motif (8.3).
                if (_atCap) ...<Widget>[
                  Text(
                    'Portfolio complet : ${ContentLimits.portfolioItems} '
                    'réalisations au maximum. Retirez-en une pour en '
                    'ajouter une nouvelle.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  onPressed: _busy || _atCap ? null : _add,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    'Ajouter une réalisation '
                    '(${widget.items.length}/${ContentLimits.portfolioItems})',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PortfolioTile extends StatelessWidget {
  const _PortfolioTile({
    required this.item,
    required this.first,
    required this.last,
    required this.enabled,
    required this.onEdit,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRemove,
  });

  final PortfolioItem item;
  final bool first;
  final bool last;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: 64,
                // Sans identifiant de fichier, il n'y a rien à demander au
                // service : un pavé neutre vaut mieux qu'une requête vide.
                child: item.file.id.isEmpty
                    ? ColoredBox(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.image_outlined,
                          color: theme.colorScheme.outline,
                        ),
                      )
                    : RemoteFileImage.public(fileId: item.file.id),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title ?? 'Sans titre',
                    style: theme.textTheme.titleSmall,
                  ),
                  if (item.description case final String description)
                    Text(
                      description,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              tooltip: 'Monter',
              onPressed: enabled && !first ? onMoveUp : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 18),
              tooltip: 'Descendre',
              onPressed: enabled && !last ? onMoveDown : null,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Modifier',
              onPressed: enabled ? onEdit : null,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              tooltip: 'Retirer',
              onPressed: enabled ? onRemove : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemEdit {
  const _ItemEdit({this.title, this.description});

  final String? title;
  final String? description;
}

class _ItemEditDialog extends StatefulWidget {
  const _ItemEditDialog({this.item});

  /// `null` = ajout. Le PATCH ne change JAMAIS l'image : remplacer la photo,
  /// c'est retirer la réalisation puis en ajouter une autre.
  final PortfolioItem? item;

  @override
  State<_ItemEditDialog> createState() => _ItemEditDialogState();
}

class _ItemEditDialogState extends State<_ItemEditDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.item?.title,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.item?.description,
  );

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.item == null
          ? 'Décrire la réalisation'
          : 'Modifier la réalisation',
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          controller: _title,
          maxLength: ContentLimits.portfolioTitleMaxLength,
          decoration: const InputDecoration(labelText: 'Titre (facultatif)'),
        ),
        TextField(
          controller: _description,
          maxLength: ContentLimits.portfolioDescriptionMaxLength,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Description (facultatif)',
          ),
        ),
      ],
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(
          _ItemEdit(
            title: _title.text.trim(),
            description: _description.text.trim(),
          ),
        ),
        child: const Text('Enregistrer'),
      ),
    ],
  );
}
