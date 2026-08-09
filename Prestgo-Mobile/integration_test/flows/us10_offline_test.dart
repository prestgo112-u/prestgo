// Point d'entrée « sur appareil » du parcours US10.
//
// Les scénarios eux-mêmes sont dans `us10_offline.dart` : ils sont aussi
// déroulés sans appareil par `test/flows/us10_offline_test.dart`, ce qui les
// place dans le périmètre de `flutter test` — donc de l'intégration continue.
//
// Exécution : `flutter test integration_test/flows/us10_offline_test.dart -d <appareil>`.

import 'package:integration_test/integration_test.dart';

import 'us10_offline.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runUs10Scenarios();
}
