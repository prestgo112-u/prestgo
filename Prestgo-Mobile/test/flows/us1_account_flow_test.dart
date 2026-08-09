// Point d'entrée sans appareil du parcours US1 (T082).
//
// Les scénarios 1.1 à 1.10 ne touchent ni au matériel ni à un greffon de plateforme :
// le transport HTTP, la base locale et le stockage sécurisé sont simulés. Ils tournent
// donc tels quels sous `flutter test`, et sont ainsi vérifiés à chaque intégration —
// ce que le dossier `integration_test/`, qui exige un appareil connecté, ne permet
// pas.

import '../../integration_test/flows/us1_account_flow.dart';

void main() => runUs1Scenarios();
