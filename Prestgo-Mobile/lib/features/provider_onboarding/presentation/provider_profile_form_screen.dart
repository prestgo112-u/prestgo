// P2 — Création (et correction) du profil public (T150, FR-052).
//
// Deux usages, un seul formulaire :
//   • **création** (`existing == null`) : `POST /providers/me`. Le 409 « profil
//     déjà là » est absorbé par le dépôt — la reprise d'un parcours interrompu
//     arrive sur le hub sans voir la moindre erreur (scénario 4.3). Le profil
//     venant d'apparaître, `GET /me` est relu : c'est lui qui fait basculer
//     l'aiguillage du gardien ;
//   • **correction** (`existing != null`, ouvert depuis la ligne « profil » du
//     hub) : `PATCH /providers/me`, retour au hub avec l'aperçu adopté.
//
// La présentation est facultative pour le service mais exigée par la checklist
// (piège n°1 de P8) : le champ l'annonce plutôt que de laisser l'utilisateur
// découvrir une ligne rouge inexpliquée.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:prestgo_mobile/app/routes.dart';
import 'package:prestgo_mobile/core/forms/form_submission.dart';
import 'package:prestgo_mobile/core/settings/app_constants.dart';
import 'package:prestgo_mobile/features/profile/presentation/me_controller.dart';
import 'package:prestgo_mobile/features/provider_onboarding/data/provider_self_repository.dart';
import 'package:prestgo_mobile/features/provider_onboarding/domain/provider_profile.dart';
import 'package:prestgo_mobile/features/provider_onboarding/presentation/provider_overview_controller.dart';

class ProviderProfileFormScreen extends ConsumerStatefulWidget {
  const ProviderProfileFormScreen({this.existing, super.key});

  /// Profil déjà créé — le formulaire corrige au lieu de créer.
  final ProviderProfile? existing;

  @override
  ConsumerState<ProviderProfileFormScreen> createState() =>
      _ProviderProfileFormScreenState();
}

class _ProviderProfileFormScreenState
    extends ConsumerState<ProviderProfileFormScreen>
    with FormSubmissionMixin<ProviderProfileFormScreen> {
  late final TextEditingController _publicName = TextEditingController(
    text: widget.existing?.publicName,
  );
  late final TextEditingController _bio = TextEditingController(
    text: widget.existing?.bio,
  );
  late final TextEditingController _experienceYears = TextEditingController(
    text: widget.existing?.experienceYears?.toString(),
  );

  bool get _isCreation => widget.existing == null;

  @override
  void dispose() {
    _publicName.dispose();
    _bio.dispose();
    _experienceYears.dispose();
    super.dispose();
  }

  String? _localCheck() {
    final String publicName = _publicName.text.trim();
    if (publicName.length < ContentLimits.publicNameMinLength) {
      return 'Le nom public doit contenir au moins '
          '${ContentLimits.publicNameMinLength} caractères.';
    }
    final String experience = _experienceYears.text.trim();
    if (experience.isNotEmpty) {
      final int? years = int.tryParse(experience);
      if (years == null ||
          years < ContentLimits.experienceYearsMin ||
          years > ContentLimits.experienceYearsMax) {
        return 'L’expérience est un nombre d’années entre '
            '${ContentLimits.experienceYearsMin} et '
            '${ContentLimits.experienceYearsMax}.';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    final String? localError = _localCheck();
    if (localError != null) {
      showFormError(localError);
      return;
    }

    final String publicName = _publicName.text.trim();
    final String bio = _bio.text.trim();
    final int? experienceYears = int.tryParse(_experienceYears.text.trim());
    final ProviderSelfRepository repository = ref.read(
      providerSelfRepositoryProvider,
    );

    final ProviderProfile? profile = await submit<ProviderProfile>(
      () => _isCreation
          ? repository.createProfile(
              publicName: publicName,
              bio: bio.isEmpty ? null : bio,
              experienceYears: experienceYears,
            )
          : repository.updateProfile(
              publicName: publicName,
              bio: bio,
              experienceYears: experienceYears,
            ),
    );
    if (profile == null || !mounted) {
      return;
    }

    ref.read(providerOverviewProvider.notifier).adopt(profile);

    if (_isCreation) {
      // `hasProviderProfile` vient de basculer : le gardien route sur `GET /me`,
      // pas sur l'aperçu — le relire est ce qui ouvre l'onboarding (FR-013).
      await ref.read(meControllerProvider.notifier).reload();
      if (mounted) {
        context.go(Routes.providerChecklist);
      }
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCreation ? 'Mon profil prestataire' : 'Profil public'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Ces informations composent votre fiche publique, celle que '
              'les clients consultent avant de réserver.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _publicName,
              maxLength: ContentLimits.publicNameMaxLength,
              enabled: !isSubmitting,
              decoration: InputDecoration(
                labelText: 'Nom public',
                hintText: 'Ex. : Koffi Électricité Générale',
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
              enabled: !isSubmitting,
              decoration: InputDecoration(
                labelText: 'Présentation',
                helperText:
                    'Facultative pour créer le profil, mais '
                    'obligatoire pour soumettre le dossier.',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                errorText: fieldErrors['bio'],
              ),
              onChanged: (String _) => clearFieldError('bio'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _experienceYears,
              keyboardType: TextInputType.number,
              enabled: !isSubmitting,
              decoration: InputDecoration(
                labelText: 'Années d’expérience (facultatif)',
                border: const OutlineInputBorder(),
                errorText: fieldErrors['experienceYears'],
              ),
              onChanged: (String _) => clearFieldError('experienceYears'),
            ),
            if (formError case final String message) ...<Widget>[
              const SizedBox(height: 8),
              Text(message, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isSubmitting ? null : _submit,
              child: isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isCreation ? 'Créer mon profil' : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
