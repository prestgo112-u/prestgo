// Point d'entrée sans appareil du parcours US7 (T205).
//
// Les charges utiles sont SIMULÉES — aucun fournisseur d'envoi n'existe sur
// l'environnement de développement (contracts/push-payloads.md §6) : le
// transport et la bannière sont des fausses implémentations des interfaces du
// socle, tout le reste est le code livré. Ces scénarios tournent donc tels
// quels sous `flutter test`, et sont vérifiés à chaque intégration.

import '../../integration_test/flows/us7_notifications.dart';

void main() => runUs7Scenarios();
