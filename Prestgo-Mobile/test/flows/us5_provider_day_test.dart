// Point d'entrée sans appareil du parcours US5 (T177).
//
// Les scénarios 5.1 à 5.6 ne touchent ni au matériel ni à un greffon de
// plateforme : le transport HTTP, la base locale et le stockage sécurisé sont
// simulés. Ils tournent donc tels quels sous `flutter test`, et sont ainsi
// vérifiés à chaque intégration — ce que le dossier `integration_test/`, qui
// exige un appareil connecté, ne permet pas.

import '../../integration_test/flows/us5_provider_day.dart';

void main() => runUs5Scenarios();
