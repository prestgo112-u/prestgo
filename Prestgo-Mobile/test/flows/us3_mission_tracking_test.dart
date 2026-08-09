// Point d'entrée sans appareil du parcours US3 (T137).
//
// Les scénarios 3.1 à 3.5 ne touchent ni au matériel ni à un greffon de
// plateforme : le transport HTTP, la base locale et le stockage sécurisé sont
// simulés. Ils tournent donc tels quels sous `flutter test`, et sont ainsi
// vérifiés à chaque intégration — ce que le dossier `integration_test/`, qui
// exige un appareil connecté, ne permet pas.

import '../../integration_test/flows/us3_mission_tracking.dart';

void main() => runUs3Scenarios();
