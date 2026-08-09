// Point d'entrée « sur appareil » du parcours US3.
//
// Les scénarios eux-mêmes sont dans `us3_mission_tracking.dart` : ils sont aussi
// déroulés sans appareil par `test/flows/us3_mission_tracking_test.dart`, ce qui
// les place dans le périmètre de `flutter test` — donc de l'intégration continue.
//
// Exécution : `flutter test integration_test/flows/us3_mission_tracking_test.dart -d <appareil>`.

import 'package:integration_test/integration_test.dart';

import 'us3_mission_tracking.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runUs3Scenarios();
}
