// Point d'entrée sans appareil du parcours US2 (T119).
//
// Les scénarios 2.1 à 2.10 ne touchent ni au matériel ni à un greffon de plateforme :
// le transport HTTP, la base locale, le stockage sécurisé et la localisation sont
// simulés. Ils tournent donc tels quels sous `flutter test`, et sont ainsi vérifiés à
// chaque intégration — ce que le dossier `integration_test/`, qui exige un appareil
// connecté, ne permet pas.

import '../../integration_test/flows/us2_booking_flow.dart';

void main() => runUs2Scenarios();
