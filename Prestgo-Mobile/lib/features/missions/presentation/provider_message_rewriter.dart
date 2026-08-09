// Reformulation des messages de disponibilité côté prestataire (T175, FR-049).
//
// Les contrôles d'agenda du service parlent toujours à la troisième personne :
// « Le prestataire ne travaille pas sur ce créneau ». Côté client, c'est juste ;
// côté prestataire, ces messages le désignent **lui-même** — affichés bruts, ils
// sont déroutants (« quel prestataire ? c'est moi »). C'est l'un des rares cas
// où le texte serveur ne doit PAS être repris tel quel (§4.5 du cahier des
// charges).
//
// La table est **fermée et exacte** : seuls les messages de disponibilité connus
// sont reformulés, tout le reste passe inchangé — un message inédit du service
// vaut mieux exact et impersonnel que réécrit de travers. Les comparaisons de
// logique (kSlotGoneMessage…) restent sur le message BRUT : la réécriture ne
// sert qu'à l'affichage.

/// Messages de disponibilité → leur forme à la deuxième personne.
const Map<String, String> _secondPersonRewrites = <String, String>{
  'Le prestataire ne travaille pas sur ce créneau':
      'Vous ne travaillez pas sur ce créneau',
  'Le prestataire est absent à cette date': 'Vous êtes absent à cette date',
  'Le prestataire a déjà une mission sur ce créneau':
      'Vous avez déjà une mission sur ce créneau',
  "Le prestataire n'est plus disponible sur ce créneau":
      "Vous n'êtes plus disponible sur ce créneau",
  "Le prestataire n'est pas disponible sur ce créneau":
      "Vous n'êtes pas disponible sur ce créneau",
};

/// Reformule [message] à la deuxième personne quand il désigne le prestataire.
String rewriteForProvider(String message) =>
    _secondPersonRewrites[message] ?? message;

/// [message], reformulé seulement si le lecteur **est** le prestataire.
String availabilityMessage(String message, {required bool asProvider}) =>
    asProvider ? rewriteForProvider(message) : message;
