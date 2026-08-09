// Point d'entrée « sur appareil » du parcours US2.
//
// Les scénarios eux-mêmes sont dans `us2_booking_flow.dart` : ils sont aussi
// déroulés sans appareil par `test/flows/us2_booking_flow_test.dart`, ce qui les
// place dans le périmètre de `flutter test` — donc de l'intégration continue.
//
// Exécution : `flutter test integration_test/flows/us2_booking_flow_test.dart -d <appareil>`.

import 'package:integration_test/integration_test.dart';

import 'us2_booking_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runUs2Scenarios();
}
