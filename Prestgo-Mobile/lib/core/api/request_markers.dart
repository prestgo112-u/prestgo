// Marqueurs posés sur `RequestOptions.extra` par les dépôts, lus par les
// intercepteurs.
//
// Ils vivent dans leur propre fichier, et non dans `auth_interceptor.dart`, pour une
// raison de frontière (porte G5) : les intercepteurs sont un détail du socle qu'une
// fonctionnalité n'a pas le droit d'importer, alors qu'elle doit pouvoir **déclarer**
// comment sa requête est traitée. C'est ce fichier-ci qui porte ce vocabulaire
// commun.

/// Exclut la requête de l'ajout d'en-tête **et** du renouvellement.
const String kSkipAuthExtra = 'prestgo.skipAuth';

/// Envoie l'en-tête d'autorisation, mais interdit le renouvellement sur 401.
///
/// Indispensable aux deux routes qui répondent 401 pour une raison **étrangère à la
/// session** : `POST /me/password` et `DELETE /me` vérifient un mot de passe saisi,
/// et le refusent avec ce même code. Sans ce marqueur, l'intercepteur y verrait une
/// session périmée : il renouvellerait, rejouerait la requête avec le même mauvais
/// mot de passe, recevrait un second 401 — et fermerait la session. Un utilisateur
/// se ferait déconnecter pour une faute de frappe.
const String kSkipRefreshExtra = 'prestgo.skipRefresh';

/// Marqueur de rejeu, posé par l'intercepteur d'authentification.
const String kAuthRetriedExtra = 'prestgo.authRetried';

/// Jeton d'accès effectivement employé par la requête.
///
/// Permet de reconnaître un 401 déjà résolu par le renouvellement d'une autre
/// requête, et donc de ne pas en déclencher un second.
const String kAccessTokenUsedExtra = 'prestgo.accessTokenUsed';
