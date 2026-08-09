# Phase 0 — Recherche et décisions techniques

**Feature**: Application mobile PRESTGO (client + prestataire)
**Date**: 2026-07-30
**Entrées**: [spec.md](./spec.md), [docs/PRESTGO-Mobile-Flutter-Cahier-des-charges.md](../../docs/PRESTGO-Mobile-Flutter-Cahier-des-charges.md)

Toutes les inconnues du *Technical Context* sont résolues ci-dessous. Aucune
**NEEDS CLARIFICATION** ne subsiste.

Le cahier des charges tranche déjà une partie de la pile (§1.1) après vérification
dans le code du service ; ces choix sont repris tels quels et ne sont pas
re-débattus ici — ils figurent en **R1** pour mémoire. Les décisions **R2** à
**R14** portent sur ce que le cahier des charges laissait ouvert.

---

## R1 — Pile applicative de base (héritée du cahier des charges §1.1)

**Décision** : Riverpod (état), dio (HTTP), go_router (navigation),
flutter_secure_storage (jetons), freezed + json_serializable (modèles),
firebase_messaging (push), uuid (idempotence).

**Justification** :
- **Riverpod plutôt que Bloc** : l'application est très majoritairement de la
  lecture (appeler, afficher, gérer chargement/erreur/vide) — `AsyncValue` couvre ce
  triptyque nativement ; la machine à états des missions vit côté serveur et ne doit
  pas être dupliquée (porte G1) ; l'invalidation en cascade après écriture
  (`ref.invalidate` sur trois providers) est plus directe qu'un bus d'évènements.
- **dio plutôt que http** : le renouvellement de session exige une file d'attente de
  requêtes suspendues et un rejeu de la requête d'origine ; `QueuedInterceptor` le
  fournit, `http` obligerait à le réécrire.
- **go_router** : le gardien d'authentification **et** l'aiguillage client /
  prestataire s'écrivent dans un unique `redirect`, au lieu d'être répétés par écran.
- **flutter_secure_storage** : le jeton de renouvellement vaut 7 jours ; le placer
  dans `SharedPreferences` reviendrait à le stocker en clair.

**Alternatives écartées** : Bloc (impose un `State` scellé par écran pour un gain
nul ici, et invite à dupliquer la machine à états), Navigator 1.0 (gardien réparti),
`chopper`/`retrofit` (génération de client typée inutile : l'enveloppe unique et les
trois formes de `data` se traitent mieux à la main, cf. **R9**).

**Note** : si l'équipe est déjà rodée à Bloc, seule la couche de présentation change ;
le contrat d'API et le socle `core/` restent identiques.

---

## R2 — Cache de lecture persistant : `drift`

**Décision** : `drift` (SQLite typé) pour le cache de lecture persistant ; cache
mémoire simple (providers Riverpod) pour la recherche, la fiche publique et les
notifications.

**Justification** :
- Le cache doit répondre à des lectures **filtrées et paginées** (missions par
  statut et par date, messages par fil avec ordre et page) : c'est du relationnel,
  pas du clé-valeur.
- L'invalidation par entité (une mission, un fil) et la purge globale à la
  déconnexion (FR-011, SC-012) s'expriment en une requête.
- Chaque ligne portant un `fetchedAt`, l'affichage « Mis à jour il y a N min »
  (FR-096) est direct, sans structure parallèle.
- `drift` est typé à la compilation et testable sur une base mémoire — les tests de
  cache ne touchent pas le disque.

**Alternatives écartées** : `hive` (rapide et simple, mais toute requête filtrée se
réécrit en parcours mémoire — coûteux sur des listes de missions et de messages, et
les migrations de schéma sont manuelles) ; `sqflite` nu (même moteur sans la sûreté
de typage ni la génération) ; `shared_preferences` (inadapté au volume et à la
structure) ; aucun cache (contredit FR-096/FR-097 et US10).

**Portée** : conforme au tableau §5.4 du cahier des charges. `GET /providers/search`
et `/providers/:id/public` restent **en mémoire uniquement** — les servir depuis le
disque afficherait des créneaux périmés.

---

## R3 — Sélecteur de position : `geolocator` + `flutter_map` (tuiles OSM)

**Décision** : `geolocator` pour la position courante et la permission,
`flutter_map` + `latlong2` pour la carte d'ajustement du marqueur.

**Justification** :
- Une adresse **sans coordonnées ne peut pas être créée** (FR-019) et sert au
  contrôle de zone d'intervention à la réservation : le sélecteur est structurant, pas
  décoratif.
- `flutter_map` ne demande **aucune clé d'API ni facturation** — le projet n'a pas
  d'arbitrage de coût cartographique tranché, et un blocage de clé casserait la
  création d'adresse, donc la réservation.
- Le besoin réel est modeste : afficher une carte, déplacer un marqueur, lire
  latitude/longitude. Ni itinéraire, ni recherche d'adresse textuelle, ni geocoding
  inverse (l'API ne les consomme pas — `city`, `commune` et `details` sont saisis).

**Alternatives écartées** : `google_maps_flutter` (meilleur rendu et couverture
d'Abidjan, mais impose une clé, une facturation et une configuration par plateforme —
à reconsidérer si le projet ouvre un compte Google Cloud) ; saisie manuelle de
latitude/longitude (inutilisable pour un particulier) ; position GPS seule sans
ajustement (une position relevée dans un bâtiment est régulièrement fausse de
plusieurs dizaines de mètres, ce qui peut faire échouer le contrôle de zone).

**Conditions d'usage** : permission refusée → la carte s'ouvre sur le centre
d'Abidjan et l'utilisateur pose le marqueur à la main ; le parcours n'est jamais
bloqué par un refus de permission.

---

## R4 — Configuration d'environnement : `--dart-define` + saveurs Android/iOS

**Décision** : trois environnements (`dev`, `staging`, `prod`) portés par
`--dart-define-from-file=env/<env>.json` (base d'API, activation Sentry, activation
des journaux réseau), doublés d'une saveur Android / configuration iOS pour
l'identifiant applicatif et le fichier Firebase.

**Justification** :
- Le préfixe `api/v1` est déjà présent dans tous les chemins : la base configurée
  est `http(s)://<hôte>/api/v1` et **aucun code ne la reconstruit** — évite le double
  préfixe signalé par le cahier des charges.
- Sur émulateur Android, `localhost` désigne l'émulateur : la valeur `dev` doit être
  `http://10.0.2.2:3000/api/v1` (et `http://localhost:3000/api/v1` sur simulateur
  iOS). Le noter dans la configuration évite l'heure perdue classique.
- `--dart-define` n'embarque pas de fichier de secrets dans le paquet et reste
  lisible par la CI.

**Alternatives écartées** : `flutter_dotenv` (le `.env` est embarqué comme ressource,
donc extractible, et charge à l'exécution un réglage nécessaire dès le démarrage) ;
constantes commentées/décommentées à la main (source d'erreur de livraison).

**Trafic en clair** : `dev` seul autorise le HTTP non chiffré
(`usesCleartextTraffic` Android limité à la saveur `dev`, exception ATS iOS limitée
au domaine de développement) ; `staging` et `prod` sont en HTTPS strict.

---

## R5 — Rapport d'incident : `sentry_flutter`

**Décision** : `sentry_flutter`, avec le `meta.correlationId` de chaque erreur
attaché en étiquette (`tag`) de l'évènement.

**Justification** :
- FR-091 et SC-010 exigent que **100 %** des incidents portent l'identifiant de
  corrélation : c'est la clé qui relie une plainte utilisateur à la trace serveur.
  Sentry accepte des étiquettes indexées et interrogeables, ce qui rend la recherche
  par corrélation immédiate.
- Fonctionne sans dépendre de Firebase, ce qui laisse le push et le rapport
  d'incident indépendants (un projet Firebase encore incomplet ne prive pas l'équipe
  de télémétrie).
- Capture les erreurs Dart non interceptées, les erreurs de rendu et les traces de
  performance des écrans clés (mesure directe de SC-005).

**Alternatives écartées** : Firebase Crashlytics (excellent sur le natif, mais les
étiquettes personnalisées sont moins exploitables en recherche et les couples
clé/valeur sont plafonnés ; couple la télémétrie à la configuration Firebase) ;
journalisation locale seule (ne remonte rien depuis le terrain).

**Confidentialité** : ni jeton, ni mot de passe, ni corps de requête ne sont
transmis ; seuls la route, le code de statut, le `correlationId` et la trace sont
envoyés. Sentry est **désactivé en `dev`**.

---

## R6 — Push : `firebase_messaging` + `flutter_local_notifications`

**Décision** : `firebase_messaging` pour le transport (cohérent avec le canal `push`
FCM déjà câblé côté service) et `flutter_local_notifications` pour la présentation au
premier plan sur Android.

**Justification** :
- Android n'affiche **pas** de bannière système quand l'application est au premier
  plan : sans notification locale, un message arrivé pendant l'usage passerait
  inaperçu (US6 scénario 6, US7).
- Les trois points d'entrée sont nécessaires et distincts : `onMessage` (premier
  plan → bannière interne + rafraîchissement des compteurs), `onMessageOpenedApp`
  (arrière-plan → routage), `getInitialMessage()` (application tuée → routage après
  démarrage du routeur). Un seul routeur les sert (FR-083).
- La charge utile `data` du push est **identique** à celle de la notification
  interne : une unique fonction de routage couvre les deux, cf.
  [contracts/push-payloads.md](./contracts/push-payloads.md).

**Alternatives écartées** : notifications internes seules (perte de réactivité sur
l'acceptation de mission et la messagerie) ; interrogation périodique (coût réseau et
batterie sans bénéfice — le cahier des charges la déconseille explicitement).

**Point de vigilance vérifié** : aucun fournisseur FCM n'est configuré sur
l'environnement de développement (`FCM_*` commentées). Le développement et les tests
du routage se font donc avec des charges utiles **simulées** injectées dans le
routeur, la validation en conditions réelles étant reportée à un environnement doté
d'identifiants FCM. La permission refusée n'entrave aucun parcours (FR-085).

---

## R7 — Envoi de fichiers : filtrage et compression avant envoi

**Décision** : `image_picker` (photos, portfolio, avatar), `file_picker`
(justificatifs PDF), `flutter_image_compress` (réduction avant envoi, cible ≤ 2 Mo,
côté long ≤ 2000 px), contrôle de type et de taille **avant** tout appel réseau.

**Justification** :
- Le service plafonne à 10 Mo et n'accepte que `image/jpeg`, `image/png`,
  `image/webp`, `application/pdf`, `text/plain`, `text/csv` ; un dépassement est
  rejeté après l'envoi complet du fichier — inacceptable sur connexion mobile.
- Une photo de téléphone récent dépasse fréquemment 5 Mo : sans compression, chaque
  justificatif est un envoi long et faillible.
- Les envois **ne passent pas** par le rejeu automatique (le corps multipart est un
  flux à usage unique) : réduire la taille réduit d'autant la probabilité d'une
  reprise manuelle.

**Alternatives écartées** : envoi du fichier d'origine (échecs et lenteur) ;
compression côté serveur (n'existe pas et ne résoudrait pas le temps d'envoi).

**Règles retenues** : avatar et portfolio filtrés sur `image/*` uniquement (le
service les refuse sinon) ; justificatifs autorisant en plus le PDF ; visibilité
`sensitive` demandée au dépôt d'un justificatif (le service la force de toute façon
au rattachement).

---

## R8 — Renouvellement de session : `QueuedInterceptor` + verrou explicite

**Décision** : intercepteur d'authentification fondé sur `QueuedInterceptor`, avec un
`Future` de renouvellement partagé (« un seul en vol »), une seconde instance `Dio`
**sans** cet intercepteur pour l'appel de renouvellement, un marqueur de rejeu unique
par requête, et une liste de routes publiques exclues. Renouvellement **proactif**
optionnel à T−60 s en décodant l'expiration du jeton.

**Justification** :
- Le renouvellement **tourne** : l'ancien jeton est révoqué. Ne pas remplacer celui
  du stockage déconnecte l'utilisateur au renouvellement suivant.
- Le débit est de 30 appels/minute : dix requêtes parallèles qui déclencheraient dix
  renouvellements atteindraient le plafond avant de comprendre le problème.
- Sans instance `Dio` séparée, un échec en 401 de l'appel de renouvellement
  relancerait un renouvellement — récursion infinie.
- Les droits sont relus en base à chaque renouvellement : un compte suspendu
  entre-temps est refusé et sa session fermée ; l'application doit alors purger et
  revenir à la connexion, pas boucler.

**Alternatives écartées** : `Interceptor` simple (n'ordonne pas les requêtes
concurrentes) ; renouvellement à l'échec, requête par requête (rafale de
renouvellements) ; renouvellement uniquement proactif (ne couvre pas un jeton
invalidé côté serveur avant son expiration).

**Exclusion explicite** : `POST /files/upload` ne passe pas par le rejeu automatique
(**R7**) ; son 401 remonte à l'écran, qui propose la reprise de l'action.

---

## R9 — Couche d'accès : `ApiEnvelope<T>` écrit à la main, pas de client généré

**Décision** : un modèle d'enveloppe générique unique et une fonction d'accès unique
(`getData<T>(path, parse)`), modèles de domaine générés par `freezed` +
`json_serializable`. Pas de génération de client depuis le document OpenAPI.

**Justification** :
- `data` prend **trois formes** dans le périmètre (objet, tableau, et — avant
  correction de l'écart n°15 — objet contenant un tableau) : un `parse` explicite par
  appel est plus sûr et plus lisible qu'un client généré qui masque la variation.
- Le document OpenAPI est fiable mais a connu des écarts de forme récents (avis,
  pagination de la messagerie) : un client régénéré à chaque évolution du service
  produirait des différences massives et illisibles en revue.
- Le contrat d'erreur (message affichable, `errors[]` avec `field`,
  `meta.correlationId`) doit être converti **une seule fois** en `ApiException` ; un
  client généré n'apporte rien sur ce point.

**Alternatives écartées** : `openapi-generator` / `swagger_parser` (30 % du contrat
généré serait réécrit à la main pour l'enveloppe et les erreurs) ; `retrofit`
(annotations pratiques, mais impose un type de retour par route et cohabite mal avec
l'enveloppe générique).

**Règle d'équipe associée (porte G2)** : aucun écran ni dépôt ne lit
`response.data['data']` et aucun ne teste un code HTTP ; tout passe par
`ApiEnvelope` et `ApiException`.

---

## R10 — Pagination et rafraîchissement : `AsyncNotifier` paginé + « stale-while-revalidate »

**Décision** : un `AsyncNotifier` par liste, exposant `loadMore()` fondé sur
`meta.page`/`meta.limit`/`meta.total`, et servant d'abord le cache disque quand il
existe, puis remplaçant par la réponse réseau à son arrivée.

**Justification** :
- `meta` porte déjà tout ce qu'il faut pour le défilement infini (FR-025) — aucun
  curseur n'est disponible côté service.
- Le motif « servir le cache, revalider » donne un premier écran instantané au
  démarrage et rend le mode hors ligne (US10) une conséquence du même code, pas un
  chemin parallèle.
- Les tris par défaut **diffèrent selon le rôle** (missions client : plus récentes
  d'abord ; missions prestataire : chronologique croissant) : ils sont pris tels quels
  du service, sans re-tri local (FR-038).

**Alternatives écartées** : `infinite_scroll_pagination` (contrôleur propre, doublon
avec Riverpod) ; rechargement complet à chaque page (coûteux et saccadé) ;
interrogation périodique (déconseillée par le cahier des charges, cf. **R6**).

**Cas particulier messagerie** : la page 1 correspond au **début** du fil (tri
croissant par défaut). L'écran de conversation demande explicitement l'ordre
décroissant pour afficher la fin du fil d'abord, puis remonte l'historique (FR-075).

---

## R11 — Localisation et formats : `intl` + `flutter_localizations`, locale unique `fr`

**Décision** : `flutter_localizations` avec un unique jeu de traductions `fr` et des
formats calés sur `fr_CI` (`intl`), un formateur monétaire centralisé pour XOF, et
les messages métier du service affichés tels quels.

**Justification** :
- Le service renvoie déjà des messages en français destinés à l'utilisateur final,
  et certains contiennent un nombre interpolé (missions bloquantes, sessions fermées,
  délais) : les retraduire côté client produirait des textes faux (FR-088).
- Le franc CFA n'a pas de sous-unité : le formateur affiche des montants entiers avec
  séparateur de milliers et suffixe, sans décimale.
- Les traductions locales couvrent uniquement les libellés propres à l'application
  (boutons, titres, états vides, reformulations prestataire de **FR-049**).

**Alternatives écartées** : multilingue dès la V1 (aucun besoin exprimé, coût de
maintenance immédiat) ; textes en dur dans les widgets (empêche la relecture
éditoriale et toute ouverture ultérieure).

**Fuseaux** : les heures d'agenda (`HH:MM`) sont manipulées **comme des chaînes**,
jamais converties dans le fuseau de l'appareil (un prestataire en déplacement verrait
son agenda décalé) ; les dates d'intervention sont converties en UTC à l'envoi et
affichées en heure locale de l'appareil, qui coïncide avec UTC en Côte d'Ivoire.

---

## R12 — Stratégie de test : contrat rejoué sur captures réelles

**Décision** : trois niveaux — unitaires (validateurs, formateurs, politique de
rejeu, calculs de prix et de durée), **contrat** (chaque dépôt rejoue les captures
JSON réelles du cahier des charges via `http_mock_adapter`, y compris les corps
d'erreur), et intégration (`integration_test`) sur les parcours de
[quickstart.md](./quickstart.md) contre l'API de démonstration.

**Justification** :
- Les captures du cahier des charges sont des **réponses réelles**, pas des exemples
  reconstruits : les rejouer verrouille l'interprétation du contrat (porte G7) et fait
  échouer le test le jour où le service change de forme.
- Les corps d'erreur sont aussi importants que les corps de succès : messages
  ambigus volontaires, `field` présent ou absent, `correlationId` — chacun pilote une
  décision d'interface testable.
- Les parcours réellement critiques (idempotence de la réservation, renouvellement
  de session concurrent, transitions de mission) se vérifient au niveau du dépôt et du
  socle, sans piloter d'interface.

**Alternatives écartées** : tests d'interface uniquement (lents, fragiles, muets sur
le contrat) ; tests en direct contre l'API seule (dépendants de l'état de la base de
démonstration, inutilisables en intégration continue).

**Couverture visée** : `core/api`, `core/session`, `core/push`, les dépôts et les
validateurs près de 100 % ; les écrans par leurs états (vide, erreur, chargement,
succès) plutôt que ligne à ligne.

---

## R13 — Bornes de plateforme et permissions

**Décision** : Android 8.0 (API 26) et plus, iOS 14 et plus. Permissions demandées
**au moment de l'usage**, jamais au démarrage : notifications après connexion,
position à l'ouverture du sélecteur d'adresse ou au premier tri par distance,
appareil photo / photothèque au premier dépôt de fichier.

**Justification** :
- Ces planchers sont ceux exigés par `firebase_messaging`, `flutter_secure_storage`
  (chiffrement Android moderne) et `geolocator` dans leurs versions actuelles.
- Android 13 et plus exige une permission explicite de notification : la demander à
  froid au premier lancement fait chuter le taux d'acceptation, alors que la demander
  juste après une connexion réussie la rend compréhensible.
- Un refus de permission ne bloque **aucun** parcours (FR-085, **R3**) : le tri par
  distance est simplement indisponible, le marqueur se pose à la main, les
  notifications restent consultables dans l'application.

**Alternatives écartées** : demande groupée au premier lancement (refus en masse) ;
plancher Android plus bas (le chiffrement du stockage sécurisé se dégrade) ; plancher
iOS 12 (non supporté par les greffons retenus).

---

## R14 — Aiguillage par rôle et purge de session

**Décision** : un unique `redirect` `go_router` fondé sur l'état de session et sur
`GET /me` (mis en cache) décide de l'écran d'atterrissage ; la déconnexion recrée le
`ProviderContainer` plutôt que d'invalider les providers un par un.

**Justification** :
- L'aiguillage dépend de deux informations seulement (`hasProviderProfile`,
  `providerValidationStatus`) et d'un tableau de correspondance figé : le concentrer
  dans le `redirect` évite qu'un écran oublie une branche (dossier suspendu, refusé
  avec re-soumission bloquée).
- Le champ `roles` est vide pour les clients et les prestataires ordinaires : il ne
  doit **jamais** servir à l'aiguillage.
- Une invalidation providers par providers laisse passer les caches oubliés :
  recréer le conteneur garantit SC-012 (aucune donnée du compte précédent visible
  après changement de compte).

**Alternatives écartées** : gardien par écran (répétition et oublis) ; deux
applications distinctes (les deux surfaces partagent un tiers des routes et un même
jeton — le service ne distingue pas une session client d'une session prestataire) ;
choix de rôle demandé à la connexion (l'utilisateur ne sait pas répondre, et un
compte à double casquette bascule sans se reconnecter).

---

## Points explicitement non tranchés par le contrat (assumés, non bloquants)

| Sujet | Position retenue | Conséquence |
|---|---|---|
| Lien profond de réinitialisation du mot de passe | Absent côté service (écart n°3, en attente d'un nom de domaine) | Écran de saisie / collage du jeton (64 caractères) ; la route de lien profond sera ajoutée sans réécriture le jour venu |
| Écrans de litige | Structure contractualisée mais non capturée en appel réel | Ouverture et suivi minimalistes ; l'écran sera précisé au moment du développement, contre le service |
| Tableau de bord prestataire | Aucun endpoint d'agrégation (écart n°10) | Composition de 3 à 4 appels indépendants ; premier candidat à l'optimisation si la latence se dégrade |
| Devise | Aucun champ côté API (décision produit) | Constante `XOF` et formateur unique centralisé |
| Messages d'erreur du service de disponibilité | Textes exacts non capturés | Les deux règles (fin après début, pas de chevauchement) sont reproduites côté client ; le message local prime |
