// Point d'entrée sans appareil du parcours US6 (T191).
//
// Les scénarios 6.1 à 6.4 ne touchent ni au matériel ni à un greffon de
// plateforme : le transport HTTP, la base locale et le stockage sécurisé sont
// simulés. Ils tournent donc tels quels sous `flutter test`, et sont ainsi
// vérifiés à chaque intégration — ce que le dossier `integration_test/`, qui
// exige un appareil connecté, ne permet pas.

import '../../integration_test/flows/us6_messaging.dart';

void main() => runUs6Scenarios();
