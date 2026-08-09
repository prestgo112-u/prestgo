// Profil de l'espace prestataire (T159, complété par T209 ; FR-062, FR-066).
//
// Le verrou de `pending_review` est celui du SERVICE — `PATCH /providers/me`
// répond 400 dès que le corps touche l'identité. L'écran le matérialise :
// champs d'identité en lecture seule, bannière qui l'explique. L'interrupteur
// de disponibilité, lui, **reste actif** : c'est un réglage d'exploitation,
// envoyé strictement seul, et le service le laisse toujours passer
// (scénario 4.8).
//
// L'état vient de `providerOverviewProvider` (couche présentation de
// l'onboarding) : le dossier n'a qu'une vérité, quel que soit l'écran qui le
// regarde — et la couche `data/` d'une fonctionnalité ne s'importe pas depuis
// une autre (porte G5).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';
import 'package:prestgo_mobile/core/core_providers.dart';
import 'package:prestgo_mobile/core/files/file_avatar.dart';
import 'package:prestgo_mobile/core/files/file_ref.dart';
import 'package:prestgo_mobile/core/files/file_upload_service.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/core/widgets/error_view.dart';
import 'package:prestgo_mobile/core/widgets/loading_view.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/document_picker.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_overview_controller.dart';
import 'package:prestgo_mobile/features/provider_space/presentation/availability_switch.dart';

class ProviderSpaceProfileScreen extends ConsumerWidget {
  const ProviderSpaceProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<ProviderProfile> overview = ref.watch(
      providerOverviewProvider,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Mon profil prestataire')),
      body: switch (overview) {
        AsyncValue<ProviderProfile>(:final ProviderProfile value) =>
          _ProfileBody(profile: value),
        AsyncValue<ProviderProfile>(:final Object error?) =>
          error is ApiException
              ? ErrorView.fromException(
                  error,
                  onRetry: () =>
                      ref.read(providerOverviewProvider.notifier).reload(),
                )
              : ErrorView(
                  message: 'Une erreur est survenue. Réessayez.',
                  onRetry: () =>
                      ref.read(providerOverviewProvider.notifier).reload(),
                ),
        _ => const LoadingView(label: 'Chargement du profil…'),
      },
    );
  }
}

class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.profile});

  final ProviderProfile profile;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody>
    with FormSubmissionMixin<_ProfileBody> {
  late final TextEditingController _publicName = TextEditingController(
    text: widget.profile.publicName,
  );
  late final TextEditingController _bio = TextEditingController(
    text: widget.profile.bio,
  );
  late final TextEditingController _experienceYears = TextEditingController(
    text: widget.profile.experienceYears?.toString(),
  );

  @override
  void dispose() {
    _publicName.dispose();
    _bio.dispose();
    _experienceYears.dispose();
    super.dispose();
  }

  /// Publication de la photo de profil (T209, scénario 8.4).
  ///
  /// L'avertissement de visibilité PRÉCÈDE le choix du fichier : la photo part
  /// en visibilité `public` — elle sera sur la fiche, visible de tous, y
  /// compris sans compte. Publier sans le dire serait un piège.
  Future<void> _changePhoto() async {
    final bool? accepted = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Photo visible publiquement'),
        content: const Text(
          'Votre photo de profil apparaît sur votre fiche, visible par tous '
          'les visiteurs — y compris sans compte. Choisissez une image qui '
          'vous représente professionnellement.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Choisir une photo'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      return;
    }

    final UploadCandidate? candidate = await ref
        .read(documentPickerProvider)
        .pick();
    if (candidate == null || !mounted) {
      return;
    }

    final ProviderProfile? updated = await submit<ProviderProfile>(() async {
      // Images uniquement : le refus d'un PDF est local, avant tout réseau.
      final FileRef file = await ref
          .read(fileUploadServiceProvider)
          .upload(
            candidate,
            acceptedMimeTypes: FileLimits.imageOnlyMimeTypes,
            visibility: FileVisibility.public,
          );
      return ref
          .read(providerOverviewProvider.notifier)
          .updateIdentity(avatarFileId: file.id);
    });
    if (updated == null || !mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Photo de profil publiée')));
  }

  Future<void> _save() async {
    final ProviderProfile? updated = await submit<ProviderProfile>(
      () => ref
          .read(providerOverviewProvider.notifier)
          .updateIdentity(
            publicName: _publicName.text.trim(),
            bio: _bio.text.trim(),
            experienceYears: int.tryParse(_experienceYears.text.trim()),
          ),
    );
    if (updated == null || !mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Profil mis à jour')));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool locked = widget.profile.identityLocked;
    final bool editable = !locked && !isSubmitting;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // Photo de profil (T209) — contenu PUBLIC : elle est sur la fiche.
        Row(
          children: <Widget>[
            ProviderAvatar(
              name: widget.profile.publicName,
              fileId: widget.profile.avatarFileId,
              radius: 36,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Photo de profil', style: theme.textTheme.titleSmall),
                  Text(
                    'Visible publiquement sur votre fiche.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: editable ? _changePhoto : null,
              child: Text(
                widget.profile.avatarFileId == null ? 'Publier' : 'Changer',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (locked) ...<Widget>[
          // La bannière dit POURQUOI les champs sont grisés — un formulaire
          // muet en lecture seule ressemble à un défaut.
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Votre dossier est en cours de vérification : votre identité '
              'publique n’est plus modifiable. Votre disponibilité, elle, '
              'reste réglable ci-dessous.',
              style: TextStyle(color: theme.colorScheme.onTertiaryContainer),
            ),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _publicName,
          maxLength: ContentLimits.publicNameMaxLength,
          enabled: editable,
          decoration: InputDecoration(
            labelText: 'Nom public',
            border: const OutlineInputBorder(),
            errorText: fieldErrors['publicName'],
          ),
          onChanged: (String _) => clearFieldError('publicName'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _bio,
          maxLength: ContentLimits.providerBioMaxLength,
          maxLines: 5,
          enabled: editable,
          decoration: InputDecoration(
            labelText: 'Présentation',
            border: const OutlineInputBorder(),
            errorText: fieldErrors['bio'],
          ),
          onChanged: (String _) => clearFieldError('bio'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _experienceYears,
          keyboardType: TextInputType.number,
          enabled: editable,
          decoration: InputDecoration(
            labelText: 'Années d’expérience',
            border: const OutlineInputBorder(),
            errorText: fieldErrors['experienceYears'],
          ),
          onChanged: (String _) => clearFieldError('experienceYears'),
        ),
        if (formError case final String message) ...<Widget>[
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 8),
        if (!locked)
          FilledButton(
            onPressed: isSubmitting ? null : _save,
            child: isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Enregistrer'),
          ),
        const SizedBox(height: 24),
        Text('Ma disponibilité', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        AvailabilityControl(profile: widget.profile),
      ],
    );
  }
}

// L'interrupteur de disponibilité vit dans `availability_switch.dart` (T168) :
// le tableau de bord l'affiche en évidence, cet écran et le suivi P9 le
// réutilisent tel quel.
