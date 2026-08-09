// Zone de saisie d'un message (T184, FR-076).
//
// Les plafonds sont ceux du service, appliqués **avant** l'envoi (FR-090) :
// 1 à 4000 caractères, au plus 3 pièces jointes distinctes. Les pièces jointes
// partent **au préalable** par `POST /files/upload` — jamais rejoué — et seuls
// leurs identifiants accompagnent le message. L'envoi lui-même est optimiste :
// la bulle apparaît immédiatement, le contrôleur d'envoi porte son sort (T185).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/connectivity/offline_gate.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/core/files/file_upload_service.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/messaging/presentation/message_attachment_picker.dart';
import 'package:prestgo_mobile/features/messaging/presentation/message_send_controller.dart';

/// Pièce jointe en préparation — envoyée dès son choix, avant le message.
class _Attachment {
  _Attachment({required this.candidate});

  final UploadCandidate candidate;

  /// Référence rendue par le service — la pièce est prête à être jointe.
  FileRef? ref;

  /// Message de refus, local ou du service.
  String? error;

  bool get isReady => ref != null;
  bool get isFailed => error != null;
  bool get isUploading => ref == null && error == null;

  String get name => candidate.fileName ?? candidate.path;
}

class MessageComposer extends ConsumerStatefulWidget {
  const MessageComposer({required this.threadId, super.key});

  final String threadId;

  @override
  ConsumerState<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends ConsumerState<MessageComposer> {
  final TextEditingController _text = TextEditingController();
  final List<_Attachment> _attachments = <_Attachment>[];

  @override
  void initState() {
    super.initState();
    _text.addListener(_onChanged);
  }

  @override
  void dispose() {
    _text
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _canAttach =>
      _attachments.length < ContentLimits.attachmentsPerMessage;

  /// Prêt à partir : un texte non vide dans le plafond, aucune pièce jointe en
  /// cours d'envoi ni en échec.
  bool get _canSend {
    final String text = _text.text.trim();
    return text.isNotEmpty &&
        text.length <= ContentLimits.messageMaxLength &&
        _attachments.every((_Attachment a) => a.isReady);
  }

  Future<void> _pick() async {
    final UploadCandidate? candidate = await ref
        .read(messageAttachmentPickerProvider)
        .pick();
    if (candidate == null || !mounted) {
      return;
    }
    final _Attachment attachment = _Attachment(candidate: candidate);
    setState(() => _attachments.add(attachment));
    await _upload(attachment);
  }

  /// Envoi préalable de la pièce (opération 61) — le message n'attend que des
  /// identifiants. Un refus local (type, taille) s'affiche sans appel réseau.
  Future<void> _upload(_Attachment attachment) async {
    try {
      final FileRef uploaded = await ref
          .read(fileUploadServiceProvider)
          .upload(attachment.candidate);
      if (!mounted) {
        return;
      }
      setState(() {
        attachment
          ..ref = uploaded
          ..error = null;
      });
    } on FileRejected catch (rejection) {
      if (mounted) {
        setState(() => attachment.error = rejection.message);
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => attachment.error = error.message);
      }
    }
  }

  Future<void> _retry(_Attachment attachment) {
    setState(() => attachment.error = null);
    return _upload(attachment);
  }

  void _remove(_Attachment attachment) =>
      setState(() => _attachments.remove(attachment));

  void _send() {
    if (!_canSend) {
      return;
    }
    final String text = _text.text.trim();
    final List<String> fileIds = <String>[
      for (final _Attachment a in _attachments) a.ref!.id,
    ];
    // Optimiste : la bulle apparaît tout de suite, la zone se vide sans attendre.
    ref
        .read(messageSendControllerProvider(widget.threadId).notifier)
        .send(text: text, fileIds: fileIds);
    setState(() {
      _text.clear();
      _attachments.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int length = _text.text.trim().length;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 4,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (_attachments.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final _Attachment attachment in _attachments)
                        _AttachmentChip(
                          attachment: attachment,
                          onRetry: () => _retry(attachment),
                          onRemove: () => _remove(attachment),
                        ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  IconButton(
                    onPressed: _canAttach ? _pick : null,
                    icon: const Icon(Icons.attach_file),
                    tooltip: _canAttach
                        ? 'Joindre un fichier'
                        : 'Pas plus de ${ContentLimits.attachmentsPerMessage} '
                              'pièces jointes par message',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: ContentLimits.messageMaxLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Votre message…',
                        border: InputBorder.none,
                        // Le compteur permanent est du bruit sur un champ de
                        // discussion : il n'apparaît qu'à l'approche du plafond.
                        counterText: '',
                      ),
                    ),
                  ),
                  // Hors ligne, l'envoi est indisponible avec son explication
                  // — RIEN n'est mis en file (10.2, T234).
                  OfflineWriteGuard(
                    explanation: 'Envoi indisponible hors ligne.',
                    builder: (BuildContext context, bool canWrite) =>
                        IconButton(
                          onPressed: canWrite && _canSend ? _send : null,
                          icon: const Icon(Icons.send),
                          tooltip: 'Envoyer',
                          color: theme.colorScheme.primary,
                        ),
                  ),
                ],
              ),
              if (length > ContentLimits.messageMaxLength - 200)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    '$length/${ContentLimits.messageMaxLength} caractères',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: length >= ContentLimits.messageMaxLength
                          ? theme.colorScheme.error
                          : theme.colorScheme.outline,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.onRetry,
    required this.onRemove,
  });

  final _Attachment attachment;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    if (attachment.isUploading) {
      return Chip(
        avatar: const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: Text(attachment.name, overflow: TextOverflow.ellipsis),
        onDeleted: onRemove,
      );
    }
    if (attachment.isFailed) {
      return Tooltip(
        message: attachment.error ?? 'Envoi refusé',
        child: InputChip(
          avatar: Icon(Icons.error_outline, color: theme.colorScheme.error),
          label: Text(attachment.name, overflow: TextOverflow.ellipsis),
          onPressed: onRetry,
          onDeleted: onRemove,
        ),
      );
    }
    return Chip(
      avatar: const Icon(Icons.check_circle_outline, size: 18),
      label: Text(attachment.name, overflow: TextOverflow.ellipsis),
      onDeleted: onRemove,
    );
  }
}
