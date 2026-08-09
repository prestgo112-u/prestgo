// Point d'entrée sans appareil du parcours US4 (T162).
//
// Les scénarios 4.1 à 4.9 ne touchent ni au matériel ni à un greffon de
// plateforme : le transport HTTP, la base locale, le stockage sécurisé et le
// sélecteur de fichier sont simulés. Ils tournent donc tels quels sous
// `flutter test`, et sont ainsi vérifiés à chaque intégration — ce que le
// dossier `integration_test/`, qui exige un appareil connecté, ne permet pas.

import '../../integration_test/flows/us4_provider_onboarding.dart';

void main() => runUs4Scenarios();
