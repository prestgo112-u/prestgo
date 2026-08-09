// Envoi d'un formulaire : occupation, erreur de bannière, erreurs par champ.
//
// Ces trois états reviennent sur chaque écran de saisie de l'application. Les tenir
// ici évite qu'un écran oublie de rouvrir son bouton après un échec, ou affiche une
// erreur de champ en bannière alors que le service a désigné le champ fautif.
//
// Règle de répartition, tirée du §4 du contrat d'enveloppe :
//   • `errors[]` avec un `field`  → sous le champ concerné ;
//   • message de l'enveloppe      → bannière du formulaire.
// Un conflit métier (409) n'a pas de `field` : il va donc en bannière, ce qui est
// exactement ce qu'on veut pour « Un compte existe déjà avec cet email ».

import 'package:flutter/widgets.dart';
import 'package:prestgo_mobile/core/api/api_exception.dart';

mixin FormSubmissionMixin<T extends StatefulWidget> on State<T> {
  /// Vrai pendant l'appel : le bouton d'envoi est désactivé, pas seulement grisé.
  bool get isSubmitting => _isSubmitting;
  bool _isSubmitting = false;

  /// Message de bannière, ou `null`.
  String? get formError => _formError;
  String? _formError;

  /// Erreurs désignant un champ, indexées par nom de champ.
  Map<String, String> get fieldErrors => _fieldErrors;
  Map<String, String> _fieldErrors = const <String, String>{};

  /// Dernier échec, conservé pour les décisions que le message ne porte pas
  /// (débit dépassé, compte non actif, coupure réseau).
  ApiException? get lastFailure => _lastFailure;
  ApiException? _lastFailure;

  /// Exécute [action] en tenant les trois états, et renvoie `null` en cas d'échec.
  ///
  /// Ne relance pas : un formulaire ne doit pas faire remonter d'exception dans
  /// l'arbre de widgets. L'appelant teste le `null`, ou consulte [lastFailure]
  /// lorsqu'il doit distinguer la nature de l'échec.
  Future<R?> submit<R>(Future<R> Function() action) async {
    if (_isSubmitting) {
      return null;
    }
    setState(() {
      _isSubmitting = true;
      _formError = null;
      _fieldErrors = const <String, String>{};
      _lastFailure = null;
    });

    try {
      final R result = await action();
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
      return result;
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _lastFailure = error;
          _fieldErrors = error.fieldMessages;
          // Quand le service a désigné les champs, la bannière ferait doublon : le
          // message de tête est de toute façon le premier de la liste.
          _formError = error.hasFieldErrors ? null : error.message;
        });
      }
      return null;
    }
  }

  /// Efface l'erreur d'un champ à la première frappe : la garder affichée pendant
  /// que l'utilisateur corrige donne l'impression que la correction est refusée.
  void clearFieldError(String field) {
    if (!_fieldErrors.containsKey(field)) {
      return;
    }
    setState(() {
      _fieldErrors = Map<String, String>.of(_fieldErrors)..remove(field);
    });
  }

  /// Pose un message de bannière sans passer par le réseau — contrôle local.
  void showFormError(String? message) => setState(() => _formError = message);
}
